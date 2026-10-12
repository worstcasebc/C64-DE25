"""Programm-Lader und Tastatur für den C64, von Linux auf dem HPS aus.

Läuft auf dem Board, nicht auf dem PC. Dazu diese Datei und c64_blocks.py
ins selbe Verzeichnis auf dem Board kopieren.

Aufruf (root nötig, weil /dev/mem geöffnet wird):
    sudo python3 c64_hps.py --load spiel.prg          Programm laden
    sudo python3 c64_hps.py --load demo.prg --run     laden und RUN tippen
    sudo python3 c64_hps.py --type "PRINT 1+1"        Text tippen, dann RETURN

Die Bytes sind dieselben, die c64_term.py vom PC über den UART schickt. Hier
gehen sie über die Brücke zwischen HPS und FPGA in das Register von
rtl/io/hps_byte_port.v:
    0x2001_0100  DATA    Schreiben: ein Byte für den C64
    0x2001_0104  STATUS  Bit 0 = 1, solange das letzte Byte noch unterwegs ist
Vor jedem Byte wird gewartet, bis STATUS frei meldet. Nicht gleichzeitig vom
PC aus laden: Beide Wege münden im FPGA in denselben Strom.
"""
import argparse
import mmap
import os
import sys
import time
from pathlib import Path

from c64_blocks import prg_to_blocks

PAGE_BASE = 0x2001_0000     # Anfang der Speicherseite mit den Registern
DATA = 0x100 // 4           # Register als Index in 32-Bit-Worten
STATUS = 0x104 // 4
TIMEOUT_S = 2.0


def send(reg, data: bytes) -> None:
    """Schickt die Bytes einzeln und wartet jeweils, bis der Port frei ist."""
    for value in data:
        deadline = time.monotonic() + TIMEOUT_S
        while reg[STATUS] & 1:
            if time.monotonic() > deadline:
                sys.exit("Der C64 nimmt kein Byte an (Reset gedrückt? Falsches Design geladen?)")
        reg[DATA] = value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--load", type=Path, metavar="DATEI", help=".PRG-Datei, die geladen wird")
    parser.add_argument("--run", action="store_true", help="nach --load RUN tippen")
    parser.add_argument("--type", metavar="TEXT", help="Text tippen, danach RETURN")
    args = parser.parse_args()

    data = b""
    if args.load:
        try:
            data += prg_to_blocks(args.load.read_bytes())
        except (OSError, ValueError) as err:
            sys.exit(f"Laden fehlgeschlagen: {err}")
        if args.run:
            data += b"RUN\r"
    if args.type:
        data += args.type.encode("ascii", errors="ignore") + b"\r"
    if not data:
        parser.error("nichts zu tun: --load oder --type angeben")

    try:
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    except OSError as err:
        sys.exit(f"/dev/mem lässt sich nicht öffnen (mit sudo gestartet?): {err}")
    with mmap.mmap(fd, mmap.PAGESIZE, offset=PAGE_BASE) as page:
        # Als 32-Bit-Worte ansprechen: So wird aus jedem Zugriff genau ein
        # Lese- oder Schreibvorgang auf dem Bus.
        reg = memoryview(page).cast("I")
        start = time.monotonic()
        send(reg, data)
        reg.release()
    print(f"{len(data)} Bytes in {time.monotonic() - start:.2f} s geschickt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
