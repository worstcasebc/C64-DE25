"""Simuliert Testbenches mit Icarus Verilog oder Questa.

Aufruf (aus dem Projektverzeichnis):
    python tb/run_sim.py              alle tb/tb_*.v
    python tb/run_sim.py tb_blink     nur eine Testbench
    python tb/run_sim.py tb_blink -w  zusätzlich GTKWave mit der .vcd öffnen

Jede Testbench muss am Ende "PASS: <name>" ausgeben; jede Zeile mit "FAIL"
gilt als Fehler. Wellenformen landen in tb/build/<name>.vcd.

Normalerweise läuft Icarus. Icarus kann aber kein VHDL und liest hier kein
SystemVerilog; Testbenches, die CPU oder VIC-II (rtl/**/*.vhd) oder den SID
aus MiSTer (rtl/**/*.sv) brauchen, tragen deshalb die Zeile
"// Simulator: Questa" und laufen über Questa (im Quartus-Paket enthalten),
das alle drei Sprachen gemeinsam simuliert. Eine Zeile
"// Questa-Optionen: ..." in der Testbench gibt Schalter an den Optimierer von
Questa weiter, etwa "+initreg+0", damit Register bei 0 statt unbestimmt
beginnen (nötig für Fremdcode, der sich auf den Startwert im FPGA verlässt).

Testbenches mit der Zeile "// Laufzeit: lang" brauchen Minuten. Sie laufen
nur, wenn man sie beim Namen nennt, nicht beim Aufruf ohne Namen.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "tb" / "build"
ICARUS_DIR = Path(r"C:\iverilog")  # Standardpfad des Windows-Installers
QUESTA_DIR = Path(r"C:\altera_pro\26.1\questa_fse\win64")
QUESTA_MARKER = "// Simulator: Questa"
QUESTA_OPTIONS = "// Questa-Optionen:"
LONG_MARKER = "// Laufzeit: lang"
# Die VHDL-Bibliotheken warnen bei jedem Vergleich mit einem noch unbestimmten
# Wert. Beim VIC-II sind das Millionen Zeilen, solange Register unbeschrieben
# sind (wie beim echten Chip nach dem Einschalten) — deshalb abgeschaltet.
QUESTA_DO = "set NumericStdNoWarnings 1; set StdArithNoWarnings 1; run -all; quit -f"


def find_tool(name: str, fallback: Path) -> str:
    """Sucht ein Werkzeug im PATH, sonst am Standard-Installationsort."""
    found = shutil.which(name)
    if found:
        return found
    if fallback.exists():
        return str(fallback)
    sys.exit(f"{name} nicht gefunden (weder im PATH noch unter {fallback})")


def run_tb_questa(name: str, rtl: list[str], helpers: list[str], plusargs: tuple[str, ...]) -> bool:
    """Übersetzt VHDL und Verilog in eine Questa-Bibliothek und simuliert."""
    tool = {t: find_tool(t, QUESTA_DIR / f"{t}.exe") for t in ("vlib", "vcom", "vlog", "vsim")}
    vhdl = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "rtl").rglob("*.vhd"))]
    sysv = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "rtl").rglob("*.sv"))]
    work = BUILD / "questa" / name
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    # Questa versteht in Bibliotheksnamen nur Schrägstriche; Pfade relativ zu ROOT.
    rel = work.relative_to(ROOT).as_posix()
    lib = f"{rel}/work"

    subprocess.run([tool["vlib"], lib], cwd=ROOT, capture_output=True, text=True)

    # VHDL-Dateien bauen aufeinander auf (z. B. T65.vhd auf T65_Pack.vhd) und
    # müssen in der passenden Reihenfolge übersetzt werden. Statt die
    # Reihenfolge zu pflegen: so lange wiederholen, wie es Fortschritt gibt.
    pending, messages = vhdl, ""
    while pending:
        failed = []
        for f in pending:
            step = subprocess.run([tool["vcom"], "-2008", "-quiet", "-work", lib, f],
                                  cwd=ROOT, capture_output=True, text=True)
            if step.returncode != 0:
                failed.append(f)
                messages = step.stdout + step.stderr
        if len(failed) == len(pending):
            print(messages)
            return False
        pending = failed

    steps = [
        [tool["vlog"], "-sv", "-quiet", "-work", lib, *sysv],
        [tool["vlog"], "-quiet", "-work", lib, f"tb/{name}.v", *helpers, *rtl],
    ]
    for cmd in steps:
        step = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if step.returncode != 0:
            print(step.stdout + step.stderr)
            return False

    source = (ROOT / "tb" / f"{name}.v").read_text(encoding="utf-8")
    options = [ln.split(QUESTA_OPTIONS, 1)[1].strip() for ln in source.splitlines() if QUESTA_OPTIONS in ln]
    voptargs = [f"-voptargs={' '.join(options)}"] if options else []

    sim = subprocess.run(
        [tool["vsim"], "-c", "-quiet", "-lib", lib, "-l", f"{rel}/transcript",
         "-wlf", f"{rel}/vsim.wlf", *voptargs, name, *plusargs, "-do", QUESTA_DO],
        cwd=ROOT, capture_output=True, text=True,
    )
    output = sim.stdout + sim.stderr
    # Questa stellt jeder Ausgabezeile "# " voran; Fehler des Werkzeugs selbst
    # beginnen mit "** Error".
    lines = [ln[2:] for ln in output.splitlines() if ln.startswith("# ") and not ln.startswith("# //")]
    print("\n".join(ln for ln in lines if ln.strip()))
    text = "\n".join(lines)
    return f"PASS: {name}" in text and "FAIL" not in text and "** Error" not in output


def run_tb(name: str, plusargs: tuple[str, ...] = ()) -> bool:
    """Übersetzt und simuliert eine Testbench; plusargs gehen an die Simulation."""
    rtl = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "rtl").rglob("*.v"))]
    # Hilfsmodule für Testbenches: alle tb/*.v, die keine Testbench sind.
    helpers = [f"tb/{p.name}" for p in sorted((ROOT / "tb").glob("*.v")) if not p.name.startswith("tb_")]
    if QUESTA_MARKER in (ROOT / "tb" / f"{name}.v").read_text(encoding="utf-8"):
        return run_tb_questa(name, rtl, helpers, plusargs)

    iverilog = find_tool("iverilog", ICARUS_DIR / "bin" / "iverilog.exe")
    vvp = find_tool("vvp", ICARUS_DIR / "bin" / "vvp.exe")
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
    # Die ROM-Abbilder werden von tb_soc_c64/tb_c64_video (und Quartus) gelesen.
    if subprocess.run([sys.executable, str(ROOT / "sw" / "py" / "build_rom.py")], cwd=ROOT).returncode != 0:
        return 1
    names = args.testbench
    if not names:
        every = sorted((ROOT / "tb").glob("tb_*.v"))
        skipped = [p.stem for p in every if LONG_MARKER in p.read_text(encoding="utf-8")]
        names = [p.stem for p in every if p.stem not in skipped]
        if skipped:
            print(f"Ausgelassen (Laufzeit lang, einzeln starten): {', '.join(skipped)}")

    failed = [n for n in names if not run_tb(n)]

    if args.wave:
        gtkwave = find_tool("gtkwave", ICARUS_DIR / "gtkwave" / "bin" / "gtkwave.exe")
        for n in names:
            subprocess.Popen([gtkwave, str(BUILD / f"{n}.vcd")])

    print(f"\n{len(names) - len(failed)}/{len(names)} Testbenches bestanden")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
