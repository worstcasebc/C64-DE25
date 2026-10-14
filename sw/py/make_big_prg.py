"""Erzeugt ein großes, selbstprüfendes Programm als .PRG-Datei.

Aufruf (aus dem Projektverzeichnis):
    python sw/py/make_big_prg.py            schreibt sw/asm/build/big.prg
    python sw/py/make_big_prg.py --fehler   dieselbe Datei mit einem falschen
                                            Byte (big_fehler.prg), um die
                                            Prüfung selbst zu prüfen

Das Programm füllt den ganzen BASIC-Speicher von $0801 bis $9FFF (38911
Bytes) und testet damit den Lader (rtl/io/prg_loader.v über c64_hps.py,
c64d.py oder c64_term.py). Nach RUN prüft es sich selbst:
    Rahmen grün, "OK"                    alles angekommen
    Rahmen rot, "FEHLER BEI $xxxx"       erstes falsches Byte
    Rahmen rot, "ENDE-ZEIGER FALSCH"     $2D/$2E zeigt nicht auf $A000

Aufbau im Speicher:
    $0801  BASIC-Zeile 10 SYS2061, die den Maschinencode startet
    $080D  Maschinencode der Prüfung (unten von Hand übersetzt)
    danach Füllbytes bis $9FFF

Die Füllbytes kommen aus einem Zufallsgenerator, den der C64 selbst
nachrechnen kann: ein 16-Bit-Schieberegister mit Rückkopplung (LFSR). Wie
bei zwei Leuten, die dieselbe Würfeltabelle haben — der Empfänger würfelt
nicht neu, sondern liest Zahl für Zahl mit und merkt sofort, wenn eine
fehlt oder falsch ist. Eine einfache Summe würde vertauschte oder
verschobene Bytes nicht bemerken; die Folge wiederholt sich erst nach 65535
Schritten, ist also länger als das Programm.

Danach steht BASIC kein Platz für Variablen mehr zur Verfügung; für neue
Eingaben den C64 zurücksetzen.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR = ROOT / "sw" / "asm" / "build"

BASIC_START = 0x0801
CODE_START = 0x080D     # = 2061, Ziel von SYS
END = 0xA000            # erstes Byte hinter dem Programm; muss auf $xx00 enden
SEED = 0xACE1           # Startwert des LFSR, nicht 0
TAPS = 0xB400           # Rückkopplung für die volle Periode von 65535

CHROUT = 0xFFD2         # KERNAL: Zeichen ausgeben
BORDER = 0xD020
GREEN, RED = 5, 2
ZP_LFSR = 0xFB          # $FB/$FC: LFSR, $FD/$FE: Zeiger (frei laut KERNAL)
ZP_PTR = 0xFD
BASIC_END_PTR = 0x2D


def lfsr_bytes(count: int) -> bytes:
    """Die Füllbytes: je ein Schritt nach rechts, dann das untere Byte."""
    state, out = SEED, bytearray()
    for _ in range(count):
        carry = state & 1
        state >>= 1
        if carry:
            state ^= TAPS
        out.append(state & 0xFF)
    return bytes(out)


class Asm:
    """Kleinster Assembler für 6502: Bytes sammeln, Sprungziele nachtragen."""

    def __init__(self, origin: int):
        self.origin, self.code = origin, bytearray()
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str, str]] = []    # (Stelle, Marke, Art)

    @property
    def pc(self) -> int:
        return self.origin + len(self.code)

    def label(self, name: str) -> None:
        self.labels[name] = self.pc

    def op(self, *values: int) -> None:
        self.code += bytes(values)

    def branch(self, opcode: int, target: str) -> None:
        self.op(opcode, 0)
        self.fixups.append((len(self.code) - 1, target, "rel"))

    def immediate(self, opcode: int, target: str, kind: str) -> None:
        """Operand aus einer Marke: "lo"/"hi" = Byte der Adresse,
        "off" = Abstand zur Marke texts (für LDX vor print)."""
        self.op(opcode, 0)
        self.fixups.append((len(self.code) - 1, target, kind))

    def absolute(self, opcode: int, target: str | int) -> None:
        if isinstance(target, int):
            self.op(opcode, target & 0xFF, target >> 8)
        else:
            self.op(opcode, 0, 0)
            self.fixups.append((len(self.code) - 2, target, "abs"))

    def text(self, name: str, value: str) -> None:
        self.label(name)
        self.code += value.encode("ascii") + b"\x00"

    def build(self) -> bytes:
        for where, name, kind in self.fixups:
            target = self.labels[name]
            if kind == "abs":
                self.code[where:where + 2] = target.to_bytes(2, "little")
            elif kind == "lo":
                self.code[where] = target & 0xFF
            elif kind == "hi":
                self.code[where] = target >> 8
            elif kind == "off":
                offset = target - self.labels["texts"]
                if not 0 <= offset <= 255:
                    raise ValueError(f"Text {name} liegt zu weit hinten")
                self.code[where] = offset
            else:
                offset = target - (self.origin + where + 1)
                if not -128 <= offset <= 127:
                    raise ValueError(f"Sprung nach {name} zu weit")
                self.code[where] = offset & 0xFF
        return bytes(self.code)


def check_code() -> bytes:
    """Maschinencode der Prüfung ab $080D."""
    a = Asm(CODE_START)
    LDA_IMM, LDA_ZP, LDA_ABSX, STA_ZP, STA_ABS = 0xA9, 0xA5, 0xBD, 0x85, 0x8D
    LDX_IMM, LDY_IMM, CMP_IMM, CMP_INDY, EOR_IMM = 0xA2, 0xA0, 0xC9, 0xD1, 0x49
    LSR_ZP, ROR_ZP, INC_ZP, LSR_A, AND_IMM, ADC_IMM = 0x46, 0x66, 0xE6, 0x4A, 0x29, 0x69
    BCC, BNE, BEQ, JSR, JMP, RTS, INX, PHA, PLA = 0x90, 0xD0, 0xF0, 0x20, 0x4C, 0x60, 0xE8, 0x48, 0x68

    a.immediate(LDX_IMM, "t_check", "off")
    a.absolute(JSR, "print")
    a.op(LDA_IMM, SEED & 0xFF, STA_ZP, ZP_LFSR)
    a.op(LDA_IMM, SEED >> 8, STA_ZP, ZP_LFSR + 1)
    a.immediate(LDA_IMM, "data", "lo")  # Zeiger auf das erste Füllbyte
    a.op(STA_ZP, ZP_PTR)
    a.immediate(LDA_IMM, "data", "hi")
    a.op(STA_ZP, ZP_PTR + 1)
    a.op(LDY_IMM, 0)

    a.label("loop")                     # LFSR einen Schritt weiter
    a.op(LSR_ZP, ZP_LFSR + 1)
    a.op(ROR_ZP, ZP_LFSR)
    a.branch(BCC, "same")
    a.op(LDA_ZP, ZP_LFSR + 1, EOR_IMM, TAPS >> 8, STA_ZP, ZP_LFSR + 1)
    a.label("same")
    a.op(LDA_ZP, ZP_LFSR)               # erwartet ...
    a.op(CMP_INDY, ZP_PTR)              # ... gegen das, was im RAM steht
    a.branch(BNE, "bad_byte")
    a.op(INC_ZP, ZP_PTR)
    a.branch(BNE, "next")
    a.op(INC_ZP, ZP_PTR + 1)
    a.label("next")
    a.op(LDA_ZP, ZP_PTR + 1, CMP_IMM, END >> 8)
    a.branch(BNE, "loop")

    a.op(LDA_ZP, BASIC_END_PTR)         # $2D/$2E muss auf das Ende zeigen
    a.branch(BNE, "bad_ptr")
    a.op(LDA_ZP, BASIC_END_PTR + 1, CMP_IMM, END >> 8)
    a.branch(BNE, "bad_ptr")
    a.op(LDA_IMM, GREEN)
    a.absolute(STA_ABS, BORDER)
    a.immediate(LDX_IMM, "t_ok", "off")
    a.absolute(JMP, "print")

    a.label("bad_ptr")
    a.op(LDA_IMM, RED)
    a.absolute(STA_ABS, BORDER)
    a.immediate(LDX_IMM, "t_ptr", "off")
    a.absolute(JMP, "print")

    a.label("bad_byte")
    a.op(LDA_IMM, RED)
    a.absolute(STA_ABS, BORDER)
    a.immediate(LDX_IMM, "t_bad", "off")
    a.absolute(JSR, "print")
    a.op(LDA_ZP, ZP_PTR + 1)
    a.absolute(JSR, "hex")
    a.op(LDA_ZP, ZP_PTR)
    a.absolute(JSR, "hex")
    a.op(LDA_IMM, 0x0D)
    a.absolute(JMP, CHROUT)

    a.label("hex")                      # A als zwei Hexziffern ausgeben
    a.op(PHA, LSR_A, LSR_A, LSR_A, LSR_A)
    a.absolute(JSR, "digit")
    a.op(PLA, AND_IMM, 0x0F)
    a.label("digit")
    a.op(CMP_IMM, 10)
    a.branch(BCC, "decimal")
    a.op(ADC_IMM, 6)                    # Carry ist 1: +7 springt von '9'+1 auf 'A'
    a.label("decimal")
    a.op(ADC_IMM, 0x30)
    a.absolute(JMP, CHROUT)

    a.label("print")                    # Text ab texts+X bis zum 0-Byte
    a.absolute(LDA_ABSX, "texts")
    a.branch(BEQ, "done")
    a.absolute(JSR, CHROUT)
    a.op(INX)
    a.branch(BNE, "print")
    a.label("done")
    a.op(RTS)

    a.label("texts")
    a.text("t_check", "\rPRUEFE $0801-$9FFF ...\r")
    a.text("t_ok", "OK\r")
    a.text("t_ptr", "ENDE-ZEIGER FALSCH\r")
    a.text("t_bad", "FEHLER BEI $")
    a.label("data")                     # hier beginnen die Füllbytes
    return a.build()


def build(damage: bool = False) -> bytes:
    stub = bytes([0x0B, 0x08, 10, 0, 0x9E]) + b"2061" + b"\x00\x00\x00"   # 10 SYS2061
    assert BASIC_START + len(stub) == CODE_START
    code = check_code()
    data_start = CODE_START + len(code)
    filler = bytearray(lfsr_bytes(END - data_start))
    if damage:
        filler[0x8000 - data_start] ^= 0x01     # ein Bit bei $8000 kippen
    return BASIC_START.to_bytes(2, "little") + stub + code + bytes(filler)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fehler", action="store_true", help="ein Byte absichtlich verfälschen")
    args = parser.parse_args()
    out = OUT_DIR / ("big_fehler.prg" if args.fehler else "big.prg")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(build(args.fehler))
    print(f"Geschrieben: {out.relative_to(ROOT)} ({out.stat().st_size} Bytes, "
          f"${BASIC_START:04X}-${END - 1:04X})")


if __name__ == "__main__":
    main()
