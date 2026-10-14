"""Bringt die Skripte des Dienstes c64d vom PC aufs Board, übers Netz.

Läuft auf dem PC (Windows, Linux). Braucht ssh und scp (bei Windows 10/11
dabei) und das Board im Netz, z. B. über WLAN (siehe README).

Aufruf (aus dem Projektverzeichnis):
    python sw/py/to_board.py 192.168.178.124          kopieren, Dienst neu starten
    python sw/py/to_board.py 192.168.178.124 --no-restart   nur kopieren
Statt der Adresse als Argument geht auch die Umgebungsvariable C64_BOARD.

Kopiert wird nach /home/terasic (dort sucht c64d.service die Skripte).
Danach startet das Skript den Dienst neu; sudo fragt dafür auf dem Board
nach dem Passwort. Für ssh/scp selbst fragt es nur, solange kein Schlüssel
eingetragen ist — mit Schlüssel geht das Kopieren ohne Passwort.

Einen Schlüssel trägt man einmalig so ein (PowerShell, fragt einmal nach
dem Passwort des Boards):
    type $env:USERPROFILE\\.ssh\\id_ed25519.pub | ssh terasic@<Adresse> "mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
USER = "terasic"
TARGET = "/home/terasic/"
FILES = [   # alles, was der Dienst und die Einzelskripte auf dem Board brauchen
    "c64d.py", "c64_keys.py", "c64_disk.py", "c64_blocks.py", "c64_pads.py",
    "c64_hps.py", "c64d.service", "99-c64-gamepad.rules",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("host", nargs="?", default=os.environ.get("C64_BOARD"),
                        help="Adresse des Boards (sonst Umgebungsvariable C64_BOARD)")
    parser.add_argument("--no-restart", action="store_true", help="Dienst c64d nicht neu starten")
    args = parser.parse_args()
    if not args.host:
        parser.error("Adresse des Boards fehlt (Argument oder C64_BOARD)")
    remote = f"{USER}@{args.host}"

    files = [str(HERE / name) for name in FILES]
    print(f"Kopiere {len(files)} Dateien nach {remote}:{TARGET} ...", flush=True)
    if subprocess.run(["scp", "-q", *files, f"{remote}:{TARGET}"]).returncode != 0:
        return "scp fehlgeschlagen (Adresse richtig? Board im Netz?)"

    if args.no_restart:
        print("Fertig (Dienst nicht neu gestartet).")
        return 0
    # -t: ein Terminal auf dem Board, damit sudo nach dem Passwort fragen kann
    print("Starte den Dienst c64d neu (sudo fragt nach dem Passwort) ...", flush=True)
    result = subprocess.run(["ssh", "-t", remote,
                             "sudo systemctl restart c64d && sleep 2 && systemctl is-active c64d"])
    return 0 if result.returncode == 0 else "Neustart fehlgeschlagen (siehe oben)"


if __name__ == "__main__":
    sys.exit(main())
