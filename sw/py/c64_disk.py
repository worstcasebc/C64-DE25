"""Legt eine Diskette (.D64 oder .G64) in das Laufwerk 1541 des C64 ein.

Läuft auf dem Board unter Linux, nicht auf dem PC.

Aufruf (root nötig, weil /dev/mem geöffnet wird):
    sudo python3 c64_disk.py spiel.d64
Die Diskette bleibt eingelegt, solange das Skript läuft. Strg+C nimmt sie
heraus; das Laufwerk ist dann wie ausgeschaltet (DEVICE NOT PRESENT).
Nach dem Einlegen braucht das Laufwerk gut zwei Sekunden, bis es bereit ist.

Das Laufwerk im FPGA hat keine Diskette, sondern fordert Spuren an. Dieses
Skript ist der Lieferant: Es wartet auf Anforderungen, liest die Blöcke aus
der Abbilddatei und schreibt sie in den Puffer von rtl/drive/hps_disk_port.v:
    0x2001_4000  REQUEST  Bit 0 = Laufwerk will lesen, Bit 1 = schreiben,
                          Bit 13..8 = Anzahl Blöcke - 1, Bit 31..16 = erster
                          Block (ein Block = 256 Bytes)
    0x2001_4004  CONTROL  schreiben 1: geliefert; lesen Bit 0: beschäftigt
    0x2001_4008  MOUNT    Bit 0 = Diskette vorhanden, Bit 1 = Schreibschutz,
                          Bit 2 = Format (0 = .D64, 1 = .G64)
    0x2001_6000  Puffer, 8192 Bytes
Eine .D64 ist einfach die Folge aller Sektoren; Block N steht in der Datei
ab Byte N * 256. Bei einer .G64 ist ein "Block" eine halbe Spur; wo sie in
der Datei steht, sagt eine Tabelle am Dateianfang.

Die Diskette ist schreibgeschützt: Schreiben setzt hps_disk_port noch nicht
um. Auf dem Board läuft .D64; der Weg für .G64 ist noch nicht ausprobiert.
"""
import argparse
import mmap
import os
import signal
import struct
import sys
import time
from pathlib import Path

PAGE_BASE = 0x2001_4000     # Anfang des Bereichs von hps_disk_port
SPAN = 0x4000
REQUEST = 0                 # Register als Index in 32-Bit-Worten
CONTROL = 1
MOUNT = 2
BUFFER = 0x2000 // 4

MOUNT_PRESENT = 1
MOUNT_READONLY = 2
MOUNT_G64 = 4

BLOCK = 256
D64_SIZES = (174848, 175531, 196608, 197376)   # 35/40 Spuren, ohne/mit Fehlerliste
G64_MAGIC = b"GCR-1541"
G64_TRACK_TABLE = 12        # ab hier je halber Spur 4 Bytes: Ort in der Datei
G64_TRACK_BYTES = 8192      # so viel überträgt das Laufwerk je halber Spur


def blocks_d64(image: bytes, lba: int, count: int) -> bytes:
    """Sektoren lba .. lba+count-1 einer .D64; hinter dem Dateiende Nullen."""
    data = image[lba * BLOCK:(lba + count) * BLOCK]
    return data.ljust(count * BLOCK, b"\x00")


def blocks_g64(image: bytes, half_track: int, count: int) -> bytes:
    """Eine halbe Spur einer .G64: zwei Bytes Länge, dann die Bits der Spur.

    Hat die Datei für diese halbe Spur nichts, kommen Nullen (Länge 0); das
    Laufwerk macht daraus eine leere Spur.
    """
    entry = G64_TRACK_TABLE + 4 * half_track
    offset = struct.unpack_from("<I", image, entry)[0] if entry + 4 <= len(image) else 0
    data = image[offset:offset + G64_TRACK_BYTES] if offset else b""
    return data.ljust(count * BLOCK, b"\x00")[:count * BLOCK]


def stop(signum, frame):
    """Beenden durch systemd (SIGTERM) wie Strg+C behandeln: Diskette herausnehmen."""
    raise KeyboardInterrupt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image", type=Path, help="Abbilddatei .d64 oder .g64")
    parser.add_argument("-v", "--verbose", action="store_true", help="jede Anforderung anzeigen")
    args = parser.parse_args()

    try:
        image = args.image.read_bytes()
    except OSError as err:
        sys.exit(f"Abbild lässt sich nicht lesen: {err}")
    is_g64 = image.startswith(G64_MAGIC)
    if not is_g64 and len(image) not in D64_SIZES:
        sys.exit(f"{args.image.name}: {len(image)} Bytes sind weder eine .D64 "
                 f"({', '.join(map(str, D64_SIZES))}) noch eine .G64")
    supply = blocks_g64 if is_g64 else blocks_d64

    try:
        mem = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    except OSError as err:
        sys.exit(f"/dev/mem lässt sich nicht öffnen (mit sudo gestartet?): {err}")
    signal.signal(signal.SIGTERM, stop)

    with mmap.mmap(mem, SPAN, offset=PAGE_BASE) as page:
        # Als 32-Bit-Worte ansprechen: So wird aus jedem Zugriff genau ein
        # Lese- oder Schreibvorgang auf dem Bus.
        reg = memoryview(page).cast("I")
        served = 0
        try:
            reg[MOUNT] = MOUNT_PRESENT | MOUNT_READONLY | (MOUNT_G64 if is_g64 else 0)
            print(f"{args.image.name} eingelegt ({'.G64' if is_g64 else '.D64'}, schreibgeschützt). "
                  "Strg+C nimmt die Diskette heraus.", flush=True)
            while True:
                request = reg[REQUEST]
                if request & 1:
                    lba = request >> 16
                    count = ((request >> 8) & 0x3F) + 1
                    data = supply(image, lba, count)
                    for i, word in enumerate(struct.unpack(f"<{len(data) // 4}I", data)):
                        reg[BUFFER + i] = word
                    reg[CONTROL] = 1
                    while reg[CONTROL] & 1:
                        pass
                    served += 1
                    if args.verbose:
                        print(f"geliefert: Block {lba}, {count} Blöcke", flush=True)
                elif request & 2:
                    reg[CONTROL] = 1        # Schreibwunsch: annehmen und verwerfen
                    while reg[CONTROL] & 1:
                        pass
                    if args.verbose:
                        print(f"Schreibwunsch verworfen: Block {request >> 16}", flush=True)
                else:
                    time.sleep(0.0002)
        except KeyboardInterrupt:
            pass
        finally:
            reg[MOUNT] = 0
            reg.release()
    print(f"Diskette herausgenommen, {served} Anforderungen bedient.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
