"""Erzeugt ein kleines BASIC-Programm als .PRG-Datei zum Testen des Laders.

Aufruf (aus dem Projektverzeichnis):
    python sw/py/make_demo_prg.py        schreibt sw/asm/build/demo.prg

Das Programm:
    10 PRINT"GELADEN UEBER DEN UART"
    20 POKE53280,5

So liegt ein BASIC-Programm im Speicher: Jede Zeile beginnt mit der Adresse
der nächsten Zeile (2 Bytes) und der Zeilennummer (2 Bytes), dann folgt der
Text, wobei Befehle zu einem Byte ("Token") verkürzt sind, und ein 0-Byte
als Zeilenende. Nach der letzten Zeile steht als "nächste Adresse" 0.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "sw" / "asm" / "build" / "demo.prg"

BASIC_START = 0x0801
PRINT, POKE = 0x99, 0x97    # Tokens der beiden Befehle

LINES = [
    (10, bytes([PRINT]) + b'"GELADEN UEBER DEN UART"'),
    (20, bytes([POKE]) + b"53280,5"),
]


def build() -> bytes:
    prg = bytearray(BASIC_START.to_bytes(2, "little"))      # Ladeadresse
    address = BASIC_START
    for number, text in LINES:
        next_address = address + 2 + 2 + len(text) + 1
        prg += next_address.to_bytes(2, "little") + number.to_bytes(2, "little") + text + b"\x00"
        address = next_address
    return bytes(prg + b"\x00\x00")                         # Programmende


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(build())
    print(f"Geschrieben: {OUT.relative_to(ROOT)} ({OUT.stat().st_size} Bytes)")
