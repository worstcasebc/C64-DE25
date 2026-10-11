"""Simuliert Testbenches mit Icarus Verilog.

Aufruf (aus dem Projektverzeichnis):
    python tb/run_sim.py              alle tb/tb_*.v
    python tb/run_sim.py tb_blink     nur eine Testbench
    python tb/run_sim.py tb_blink -w  zusätzlich GTKWave mit der .vcd öffnen

Jede Testbench muss am Ende "PASS: <name>" ausgeben; jede Zeile mit "FAIL"
gilt als Fehler. Wellenformen landen in tb/build/<name>.vcd.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "tb" / "build"
ICARUS_DIR = Path(r"C:\iverilog")  # Standardpfad des Windows-Installers


def find_tool(name: str, fallback: Path) -> str:
    """Sucht ein Werkzeug im PATH, sonst am Standard-Installationsort."""
    found = shutil.which(name)
    if found:
        return found
    if fallback.exists():
        return str(fallback)
    sys.exit(f"{name} nicht gefunden (weder im PATH noch unter {fallback})")


def run_tb(name: str, plusargs: tuple[str, ...] = ()) -> bool:
    """Übersetzt und simuliert eine Testbench; plusargs gehen an die Simulation."""
    iverilog = find_tool("iverilog", ICARUS_DIR / "bin" / "iverilog.exe")
    vvp = find_tool("vvp", ICARUS_DIR / "bin" / "vvp.exe")
    rtl = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "rtl").rglob("*.v"))]
    # Hilfsmodule für Testbenches: alle tb/*.v, die keine Testbench sind.
    helpers = [f"tb/{p.name}" for p in sorted((ROOT / "tb").glob("*.v")) if not p.name.startswith("tb_")]
    out = BUILD / f"{name}.vvp"

    compile_cmd = [iverilog, "-g2005", "-Wall", "-Wno-timescale", "-s", name, "-o", str(out),
                   f"tb/{name}.v", *helpers, *rtl]
    comp = subprocess.run(compile_cmd, cwd=ROOT, capture_output=True, text=True)
    if comp.returncode != 0 or comp.stderr.strip():
        print(comp.stdout + comp.stderr)
        if comp.returncode != 0:
            return False

    sim = subprocess.run([vvp, str(out), *plusargs], cwd=ROOT, capture_output=True, text=True)
    output = sim.stdout + sim.stderr
    print(output.strip())
    return sim.returncode == 0 and f"PASS: {name}" in output and "FAIL" not in output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("testbench", nargs="*", help="z. B. tb_blink (Default: alle)")
    parser.add_argument("-w", "--wave", action="store_true", help="GTKWave öffnen")
    args = parser.parse_args()

    BUILD.mkdir(parents=True, exist_ok=True)
    # Die ROM-Abbilder werden von tb_soc_mini/tb_soc_c64 (und Quartus) gelesen.
    if subprocess.run([sys.executable, str(ROOT / "sw" / "py" / "build_rom.py")], cwd=ROOT).returncode != 0:
        return 1
    names = args.testbench or [p.stem for p in sorted((ROOT / "tb").glob("tb_*.v"))]

    failed = [n for n in names if not run_tb(n)]

    if args.wave:
        gtkwave = find_tool("gtkwave", ICARUS_DIR / "gtkwave" / "bin" / "gtkwave.exe")
        for n in names:
            subprocess.Popen([gtkwave, str(BUILD / f"{n}.vcd")])

    print(f"\n{len(names) - len(failed)}/{len(names)} Testbenches bestanden")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
