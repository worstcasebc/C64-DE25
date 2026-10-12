"""Erzeugt ein Bildschirmfoto des simulierten C64 als PNG.

Aufruf (aus dem Projektverzeichnis):
    python tb/screenshot.py              Original-ROMs aus roms/ (BASIC-Start)
    python tb/screenshot.py --roms test  Test-ROMs (sw/asm/banktest.s)
    python tb/screenshot.py --wait 500000 -o bild.png
    python tb/screenshot.py --type "PRINT3+4"   nach dem Start Text + Enter tippen
    python tb/screenshot.py --load demo.prg --type RUN   erst Programm laden

Lässt tb_c64_video laufen: Der Rechner arbeitet --wait CPU-Takte lang, dann
wird ein Bild des VIC-II aufgezeichnet (504 x 312 Pixel, das ganze PAL-Raster
einschließlich der Lücken). Das Original-KERNAL braucht für Speichertest und
Startmeldung gut 2,5 Millionen CPU-Takte; die Simulation läuft über Questa
und dauert dafür rund eine Viertelstunde.
"""
import argparse
import struct
import subprocess
import sys
import zlib
from pathlib import Path

import run_sim

sys.path.insert(0, str(run_sim.ROOT / "sw" / "py"))
import c64_blocks  # noqa: E402  (liefert die Ladeblöcke für eine .PRG-Datei)

ROOT = run_sim.ROOT
BUILD = run_sim.BUILD
ROM_DIR = "sw/asm/build"
CLKS_PER_CPU_CYCLE = 8  # tb_c64_video simuliert mit PIX_DIV = 1


def ppm_to_png(ppm: Path, png: Path) -> None:
    """Wandelt eine Text-PPM-Datei (P3) in ein PNG um, ohne Zusatzbibliothek."""
    tokens = ppm.read_text().split()
    if tokens[0] != "P3" or tokens[3] != "255":
        sys.exit(f"{ppm.name}: unerwartetes Format")
    width, height = int(tokens[1]), int(tokens[2])
    pixels = bytes(int(t) for t in tokens[4:])
    if len(pixels) != width * height * 3:
        sys.exit(f"{ppm.name}: {len(pixels)} Farbwerte, erwartet {width * height * 3}")

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    # Jede Bildzeile beginnt mit einem Filterbyte (0 = ungefiltert).
    rows = b"".join(b"\x00" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    png.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--roms", choices=["c64", "test"], default="c64", help="ROM-Satz (Default: c64)")
    parser.add_argument("--wait", type=int, help="CPU-Takte vor der Aufnahme")
    parser.add_argument("--load", type=Path, metavar="DATEI", help=".PRG-Datei, die nach der Wartezeit geladen wird")
    parser.add_argument("--type", dest="text", help="Text, der nach der Wartezeit getippt wird (ohne Leerzeichen)")
    parser.add_argument("--after", type=int, help="CPU-Takte zwischen Tippen und Aufnahme")
    parser.add_argument("-o", "--output", type=Path, default=BUILD / "screenshot.png")
    args = parser.parse_args()

    BUILD.mkdir(parents=True, exist_ok=True)
    if subprocess.run([sys.executable, str(ROOT / "sw" / "py" / "build_rom.py")], cwd=ROOT).returncode != 0:
        return 1

    if args.roms == "c64":
        files = {"basic": "c64_basic", "char": "c64_chargen", "kernal": "c64_kernal"}
        missing = [f for f in files.values() if not (ROOT / ROM_DIR / f"{f}.hex").exists()]
        if missing:
            sys.exit(f"Original-ROMs fehlen ({', '.join(missing)}), siehe roms/README.md")
        plusargs = [f"+{key}={ROM_DIR}/{name}.hex" for key, name in files.items()]
        plusargs += [f"+wait={(args.wait or 3_000_000) * CLKS_PER_CPU_CYCLE}", "+nocheck"]
    else:
        plusargs = [f"+wait={(args.wait or 100_000) * CLKS_PER_CPU_CYCLE}"]

    if args.load:
        blocks = c64_blocks.prg_to_blocks(args.load.read_bytes())
        (BUILD / "load_bytes.hex").write_text("".join(f"{b:02X}\n" for b in blocks))
        plusargs += ["+load=tb/build/load_bytes.hex", f"+loadlen={len(blocks)}"]
    if args.text:
        plusargs.append(f"+type={args.text}")
    if args.after:
        plusargs.append(f"+after={args.after * CLKS_PER_CPU_CYCLE}")

    if not run_sim.run_tb("tb_c64_video", tuple(plusargs)):
        return 1
    ppm_to_png(BUILD / "tb_c64_video.ppm", args.output)
    print(f"Bildschirmfoto: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
