"""Tastatur-Terminal und Programm-Lader für den C64 auf dem DE25-Nano (Windows).

Aufruf:
    python sw/py/c64_term.py                      Port COM12
    python sw/py/c64_term.py COM7                 anderer Port
    python sw/py/c64_term.py --load spiel.prg     erst Programm laden
    python sw/py/c64_term.py --load demo.prg --run    laden und RUN tippen

Schickt jeden Tastendruck sofort über den UART ans FPGA (115200 Baud, 8N1),
statt wie viele Terminalprogramme erst die ganze Zeile bei Enter. Das FPGA
tippt die Zeichen auf der C64-Tastatur (rtl/io/ascii_key_typer.v).

    Enter                RETURN
    Rücktaste, Entf      DEL (Zeichen links vom Cursor löschen)
    Esc                  RUN/STOP
    Pfeiltasten          Cursor
    Pos1                 HOME            Einfg    INS
    F1 bis F8            F1 bis F8
    Strg+L               .PRG-Datei laden (fragt nach dem Dateinamen)
    Strg+C               Terminal beenden

Eine .PRG-Datei beginnt mit zwei Bytes Ladeadresse, dann folgt das Programm.
Der Lader schreibt es am Rechner vorbei direkt ins RAM (rtl/io/prg_loader.v).
Bei BASIC-Programmen (Ladeadresse $0801) setzt er zusätzlich den Zeiger auf
das Programmende, so wie es der LOAD-Befehl täte; danach genügt RUN.

Benötigt pyserial:  python -m pip install pyserial
"""
import argparse
import msvcrt
import sys
from pathlib import Path

BAUD = 115200
BASIC_START = 0x0801    # hier beginnen BASIC-Programme
BASIC_END_PTR = 0x002D  # Zeiger des BASIC auf das Programmende (2 Bytes)

# Sondertasten liefert msvcrt als zwei Zeichen: Vorzeichen (\x00 oder \xe0)
# und Tastencode. Rechts steht der Steuercode des C64 (PETSCII), den das
# FPGA versteht.
SPECIAL_KEYS = {
    "H": 0x91,  # Pfeil hoch
    "P": 0x11,  # Pfeil runter
    "K": 0x9D,  # Pfeil links
    "M": 0x1D,  # Pfeil rechts
    "G": 0x13,  # Pos1 -> HOME
    "R": 0x94,  # Einfg -> INS
    "S": 0x14,  # Entf -> DEL
    ";": 0x85,  # F1
    "<": 0x89,  # F2
    "=": 0x86,  # F3
    ">": 0x8A,  # F4
    "?": 0x87,  # F5
    "@": 0x8B,  # F6
    "A": 0x88,  # F7
    "B": 0x8C,  # F8
}


def load_block(address: int, data: bytes) -> bytes:
    """Ein Ladeblock für prg_loader: $FF, Adresse, Länge, Daten."""
    if not 0 < len(data) <= 0xFFFF:
        raise ValueError(f"Blocklänge {len(data)} nicht im Bereich 1..65535")
    return bytes([0xFF, address & 0xFF, address >> 8, len(data) & 0xFF, len(data) >> 8]) + data


def prg_to_blocks(prg: bytes) -> bytes:
    """Macht aus dem Inhalt einer .PRG-Datei die Bytes, die ans FPGA gehen."""
    if len(prg) < 3:
        raise ValueError("Datei zu kurz für eine .PRG-Datei")
    address = prg[0] | (prg[1] << 8)
    data = prg[2:]
    end = address + len(data)
    if end > 0x10000:
        raise ValueError(f"Programm reicht über $FFFF hinaus (Ende ${end:X})")
    blocks = load_block(address, data)
    if address == BASIC_START:
        blocks += load_block(BASIC_END_PTR, bytes([end & 0xFF, end >> 8]))
    return blocks


def load_prg(port, path: Path, run: bool = False) -> None:
    try:
        blocks = prg_to_blocks(path.read_bytes())
    except (OSError, ValueError) as err:
        print(f"Laden fehlgeschlagen: {err}")
        return
    seconds = len(blocks) * 10 / BAUD
    print(f"Lade {path.name} ({len(blocks)} Bytes, etwa {seconds:.1f} s) ...", end="", flush=True)
    port.write(blocks)
    port.flush()
    print(" fertig.")
    if run:
        port.write(b"RUN\r")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("port", nargs="?", default="COM12", help="serieller Port (Default: COM12)")
    parser.add_argument("--load", type=Path, metavar="DATEI", help=".PRG-Datei, die zuerst geladen wird")
    parser.add_argument("--run", action="store_true", help="nach --load RUN tippen")
    args = parser.parse_args()

    try:
        import serial
    except ImportError:
        sys.exit("pyserial fehlt. Installieren mit:  python -m pip install pyserial")

    try:
        port = serial.Serial(args.port, BAUD)
    except serial.SerialException as err:
        sys.exit(f"{args.port} lässt sich nicht öffnen (anderes Terminal noch offen?): {err}")

    print(f"Verbunden mit {args.port}. Tippen geht direkt an den C64, "
          "Strg+L lädt eine .PRG-Datei, Strg+C beendet.")
    with port:
        if args.load:
            load_prg(port, args.load, args.run)
        while True:
            key = msvcrt.getwch()
            if key == "\x03":                   # Strg+C
                return 0
            if key == "\x0c":                   # Strg+L
                name = input("PRG-Datei: ").strip().strip('"')
                if name:
                    load_prg(port, Path(name))
                continue
            if key in ("\x00", "\xe0"):         # Sondertaste: zweites Zeichen holen
                code = SPECIAL_KEYS.get(msvcrt.getwch())
            elif ord(key) < 0x80:
                code = ord(key)
            else:
                code = None                     # Umlaute usw. kennt der C64 nicht
            if code is not None:
                port.write(bytes([code]))


if __name__ == "__main__":
    sys.exit(main())
