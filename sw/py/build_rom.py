"""Baut die ROMs: .s -> .o -> .bin -> .hex.

Aufruf (aus dem Projektverzeichnis):
    python sw/py/build_rom.py            baut alle Programme aus TARGETS und
                                         wandelt die Original-ROMs aus roms/ um
    python sw/py/build_rom.py name       baut nur sw/asm/name.s

Ergebnis in sw/asm/build/: <name>.bin (Rohdaten), <name>.map und <name>.lst
zum Nachlesen sowie je ROM eine Hex-Datei (ein Byte pro Zeile für $readmemh):
    banktest  -> banktest_basic.hex, banktest_char.hex,
                 banktest_kernal.hex                        (C64-Speicherkarte)

Die Original-ROMs des C64 sind urheberrechtlich geschützt und liegen nur
lokal in roms/ (siehe C64_ROMS). Sind sie vorhanden, entstehen daraus
c64_basic.hex, c64_chargen.hex und c64_kernal.hex; fehlende werden mit
einem Hinweis übersprungen. Dasselbe gilt für das ROM des Laufwerks 1541:
Aus ihm entsteht c1541_rom.hex.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ASM = ROOT / "sw" / "asm"
BUILD = ASM / "build"
CC65_BIN = ROOT / "tools" / "cc65" / "bin"  # lokaler cc65-Snapshot

# Programm -> (Linker-Konfiguration, ROMs in der Reihenfolge der .bin-Datei
# als (Namenszusatz, Größe))
TARGETS = {
    "banktest": ("c64.cfg", [("_basic", 0x2000), ("_char", 0x1000), ("_kernal", 0x2000)]),
}


# Original-ROMs: Name der Hex-Datei -> (Datei in roms/, Größe)
C64_ROMS = {
    "c64_basic": ("basic-901226-01.bin", 0x2000),
    "c64_chargen": ("chargen-901225-01.bin", 0x1000),
    "c64_kernal": ("kernal-901227-03.bin", 0x2000),
    "c1541_rom": ("dos1541-325302-01+901229-05.bin", 0x4000),
}


def write_hex(hex_file: Path, data: bytes) -> None:
    hex_file.write_text("".join(f"{b:02X}\n" for b in data))



def convert_c64_roms() -> list[Path]:
    """Wandelt die vorhandenen Original-ROMs aus roms/ in Hex-Dateien um."""
    BUILD.mkdir(parents=True, exist_ok=True)
    hex_files = []
    for name, (rom_name, size) in C64_ROMS.items():
        rom = ROOT / "roms" / rom_name
        if not rom.exists():
            print(f"Hinweis: roms/{rom_name} fehlt, {name}.hex wird nicht erzeugt")
            continue
        data = rom.read_bytes()
        if len(data) != size:
            sys.exit(f"roms/{rom_name} hat {len(data)} Bytes, erwartet {size}")
        write_hex(BUILD / f"{name}.hex", data)
        hex_files.append(BUILD / f"{name}.hex")

    return hex_files


def find_tool(name: str) -> str:
    """Sucht ein cc65-Werkzeug im PATH, sonst unter tools/cc65/bin."""
    found = shutil.which(name)
    if found:
        return found
    local = CC65_BIN / f"{name}.exe"
    if local.exists():
        return str(local)
    sys.exit(f"{name} nicht gefunden (weder im PATH noch unter {CC65_BIN})")


def build(name: str) -> list[Path]:
    if name not in TARGETS:
        sys.exit(f"Unbekanntes Programm '{name}' (bekannt: {', '.join(TARGETS)})")
    cfg, roms = TARGETS[name]

    BUILD.mkdir(parents=True, exist_ok=True)
    obj, binary = BUILD / f"{name}.o", BUILD / f"{name}.bin"

    subprocess.run(
        [find_tool("ca65"), "-t", "none", "-l", str(BUILD / f"{name}.lst"),
         "-o", str(obj), str(ASM / f"{name}.s")],
        check=True,
    )
    subprocess.run(
        [find_tool("ld65"), "-C", str(ASM / cfg), "-m", str(BUILD / f"{name}.map"),
         "-o", str(binary), str(obj)],
        check=True,
    )

    data = binary.read_bytes()
    total = sum(size for _, size in roms)
    if len(data) != total:
        sys.exit(f"{binary.name} hat {len(data)} Bytes, erwartet {total}")

    hex_files, offset = [], 0
    for suffix, size in roms:
        hex_file = BUILD / f"{name}{suffix}.hex"
        write_hex(hex_file, data[offset:offset + size])
        hex_files.append(hex_file)
        offset += size
    return hex_files


if __name__ == "__main__":
    try:
        outs = [f for name in (sys.argv[1:] or TARGETS) for f in build(name)]
    except subprocess.CalledProcessError as err:
        sys.exit(err.returncode)
    if len(sys.argv) == 1:
        outs += convert_c64_roms()
    for out in outs:
        print(f"ROM gebaut: {out.relative_to(ROOT)}")
