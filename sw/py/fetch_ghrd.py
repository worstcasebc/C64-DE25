"""Holt die Terasic-Dateien für quartus_hps/ aus dem Beispiel GHRD.

Aufruf (aus dem Projektverzeichnis):
    python sw/py/fetch_ghrd.py <Pfad zum GHRD>

Der Pfad ist der Ordner Demonstration/SoC_FPGA/GHRD aus Terasics
Ressourcen-Paket zum DE25-Nano. Kopiert werden nur Quellen: das
Platform-Designer-System (.qsys), seine Bausteine (.ip), custom_ip/ und der
Bootloader. Diese Dateien dürfen nicht weitergegeben werden und stehen
deshalb nicht im Repository (siehe quartus_hps/README.md).
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
TARGET = ROOT / "quartus_hps"

# Muster relativ zum GHRD-Ordner. Bauerzeugnisse (qdb/, output_files/, die
# erzeugten Unterordner neben den .ip-Dateien) bleiben so außen vor.
PATTERNS = [
    "qsys_top.qsys",
    "*_subsys/*.qsys",
    "ip/*.ip",
    "ip/qsys_top/*.ip",
    "*_subsys/ip/*/*.ip",
    "custom_ip/**/*",
    "software/u-boot/spl/u-boot-spl-dtb.hex",
]


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ghrd = Path(sys.argv[1])
    if not (ghrd / "qsys_top.qsys").is_file():
        sys.exit(f"{ghrd} sieht nicht nach dem GHRD aus (qsys_top.qsys fehlt)")

    # "._*" sind Reste von macOS im Paket, "*.BAK.*" Sicherungen, die Quartus
    # bei "Upgrade IP Components" anlegt — beides keine Quellen.
    files = sorted({f for p in PATTERNS for f in ghrd.glob(p)
                    if f.is_file() and not f.name.startswith("._") and ".BAK." not in f.name})
    for src in files:
        dst = TARGET / src.relative_to(ghrd)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        print(dst.relative_to(ROOT))
    print(f"{len(files)} Dateien nach {TARGET.relative_to(ROOT)}/ kopiert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
