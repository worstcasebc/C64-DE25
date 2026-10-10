"""Baut das ROM des Mini-Systems: .s -> .o -> .bin -> .hex.

Aufruf (aus dem Projektverzeichnis):
    python sw/py/build_rom.py            baut sw/asm/hello.s
    python sw/py/build_rom.py name       baut sw/asm/name.s

Ergebnis in sw/asm/build/: <name>.bin (Rohdaten), <name>.hex (ein Byte pro
Zeile für $readmemh), <name>.map und <name>.lst zum Nachlesen.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ASM = ROOT / "sw" / "asm"
BUILD = ASM / "build"
CC65_BIN = ROOT / "tools" / "cc65" / "bin"  # lokaler cc65-Snapshot
ROM_SIZE = 0x2000


def find_tool(name: str) -> str:
    """Sucht ein cc65-Werkzeug im PATH, sonst unter tools/cc65/bin."""
    found = shutil.which(name)
    if found:
        return found
    local = CC65_BIN / f"{name}.exe"
    if local.exists():
        return str(local)
    sys.exit(f"{name} nicht gefunden (weder im PATH noch unter {CC65_BIN})")


def build(name: str) -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    obj, binary = BUILD / f"{name}.o", BUILD / f"{name}.bin"

    subprocess.run(
        [find_tool("ca65"), "-t", "none", "-l", str(BUILD / f"{name}.lst"),
         "-o", str(obj), str(ASM / f"{name}.s")],
        check=True,
    )
    subprocess.run(
        [find_tool("ld65"), "-C", str(ASM / "mini.cfg"), "-m", str(BUILD / f"{name}.map"),
         "-o", str(binary), str(obj)],
        check=True,
    )

    data = binary.read_bytes()
    if len(data) != ROM_SIZE:
        sys.exit(f"{binary.name} hat {len(data)} Bytes, erwartet {ROM_SIZE}")

    hex_file = BUILD / f"{name}.hex"
    hex_file.write_text("".join(f"{b:02X}\n" for b in data))
    return hex_file


if __name__ == "__main__":
    try:
        out = build(sys.argv[1] if len(sys.argv) > 1 else "hello")
    except subprocess.CalledProcessError as err:
        sys.exit(err.returncode)
    print(f"ROM gebaut: {out.relative_to(ROOT)}")
