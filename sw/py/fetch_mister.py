"""Holt VIC-II, SID, CIA und das Laufwerk 1541 aus dem MiSTer-Repository nach rtl/**/vendor/.

Aufruf (aus dem Projektverzeichnis):
    python sw/py/fetch_mister.py

Lädt die Dateien aus https://github.com/MiSTer-devel/C64_MiSTer in genau dem
Stand COMMIT herunter; das Laufwerk im älteren Stand COMMIT_DRIVE (der neuere
braucht einen großen Speicher, den es hier nicht gibt, siehe
rtl/drive/vendor/mister_c1541/README.md). SID, CIA und Laufwerk werden danach
mit dem jeweiligen quartus_pro.patch in die Form gebracht, die Quartus Pro
und Questa annehmen (siehe README.md im jeweiligen vendor-Ordner). Die
Lizenzlage dieser Dateien ist ungeklärt oder verlangt die Weitergabe unter
gleichen Bedingungen, deshalb stehen sie nicht im Repository.

Benötigt git (für "git apply") und einen Internetzugang.
"""
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
COMMIT = "fe6dfe53c99122e5a088691f2d358d6caba61de1"
COMMIT_DRIVE = "f11608f66bcb2b017680d7c719aa547f537bfd3f"
BASE_URL = "https://raw.githubusercontent.com/MiSTer-devel/C64_MiSTer/"

# Zielordner -> (Stand, Patch im Zielordner oder None, {Pfad in MiSTer: Name hier})
CORES = {
    "rtl/video/vendor/fpga64": (COMMIT, None, {
        "rtl/video_vicII_656x.vhd": "video_vicII_656x.vhd",
    }),
    "rtl/audio/vendor/mister_sid": (COMMIT, "quartus_pro.patch", {
        "rtl/sid/sid_top.sv": "sid_top.sv",
        "rtl/sid/sid_voice.sv": "sid_voice.sv",
        "rtl/sid/sid_envelope.sv": "sid_envelope.sv",
        "rtl/sid/sid_filter.sv": "sid_filter.sv",
        "rtl/sid/sid_dac.sv": "sid_dac.sv",
        "rtl/sid/sid_tables.sv": "sid_tables.sv",
    }),
    # Die CIA heißt hier .sv, weil sie Schreibweisen aus SystemVerilog benutzt.
    "rtl/io/vendor/mister_cia": (COMMIT, "quartus_pro.patch", {
        "rtl/mos6526.v": "mos6526.sv",
    }),
    "rtl/drive/vendor/mister_c1541": (COMMIT_DRIVE, "quartus_pro.patch", {
        "rtl/iec_drive/c1541_multi.sv": "c1541_multi.sv",
        "rtl/iec_drive/c1541_drv.sv": "c1541_drv.sv",
        "rtl/iec_drive/c1541_logic.sv": "c1541_logic.sv",
        "rtl/iec_drive/c1541_track.sv": "c1541_track.sv",
        "rtl/iec_drive/c1541_gcr.sv": "c1541_gcr.sv",
        "rtl/iec_drive/c1541_direct_gcr.sv": "c1541_direct_gcr.sv",
        "rtl/iec_drive/iecdrv_misc.sv": "iecdrv_misc.sv",
        "rtl/iec_drive/iecdrv_via6522.vhd": "iecdrv_via6522.vhd",
        "rtl/iec_drive/lfsr.v": "lfsr.v",
    }),
}


def unix_lines(data: bytes) -> bytes:
    """Einheitliche Zeilenenden, damit der Patch unabhängig vom System passt."""
    return data.replace(b"\r\n", b"\n")


def download(commit: str, path: str) -> bytes:
    try:
        with urllib.request.urlopen(f"{BASE_URL}{commit}/{path}", timeout=30) as response:
            return unix_lines(response.read())
    except (urllib.error.URLError, TimeoutError) as err:
        sys.exit(f"Herunterladen von {path} fehlgeschlagen: {err}")


def fetch_core(target: Path, commit: str, patch: str | None, files: dict[str, str]) -> None:
    git = shutil.which("git")
    if patch and not git:
        sys.exit("git nicht gefunden (wird für 'git apply' gebraucht)")

    # Der Patch nennt die Dateien bei ihrem Namen in MiSTer, deshalb erst in
    # einem Arbeitsordner mit diesen Namen patchen, dann umbenannt ablegen.
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for source in files:
            (work / Path(source).name).write_bytes(download(commit, source))
        if patch:
            (work / patch).write_bytes(unix_lines((target / patch).read_bytes()))
            # -p2 entfernt "a/original/" bzw. "b/angepasst/" aus den Pfaden.
            result = subprocess.run([git, "apply", "-p2", patch], cwd=work,
                                    capture_output=True, text=True)
            if result.returncode != 0:
                sys.exit(f"{target / patch} passt nicht:\n{result.stderr}")
        for source, name in files.items():
            shutil.copyfile(work / Path(source).name, target / name)
            print((target / name).relative_to(ROOT).as_posix())


def main() -> int:
    for folder, (commit, patch, files) in CORES.items():
        fetch_core(ROOT / folder, commit, patch, files)
    print(f"Stand: MiSTer-Commit {COMMIT[:7]}, Laufwerk {COMMIT_DRIVE[:7]}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
