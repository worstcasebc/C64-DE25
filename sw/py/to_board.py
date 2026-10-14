"""Installiert die Skripte des Dienstes c64d vom PC aus auf dem Board, übers Netz.

Läuft auf dem PC (Windows, Linux). Braucht ssh und scp (bei Windows 10/11
dabei) und das Board im Netz, z. B. über WLAN (siehe INSTALL.md, D7).

Aufruf (aus dem Projektverzeichnis):
    python sw/py/to_board.py 192.168.178.124          installieren, Dienst neu starten
Statt der Adresse als Argument geht auch die Umgebungsvariable C64_BOARD.

Was passiert:
  1. Die Dateien gehen per scp nach /tmp/c64-install auf dem Board, und der
     Ordner ~/c64 für Spiele ohne USB-Stick wird angelegt (falls er fehlt).
  2. Mit einem einzigen sudo (fragt nach dem Passwort des Boards):
     - Skripte nach /opt/c64, Besitzer root, für andere nur lesbar. Ein
       Dienst, der als root läuft, darf nichts ausführen, was ein normaler
       Benutzer ändern kann — sonst wäre jeder Benutzer root.
     - c64d.service nach /etc/systemd/system, die udev-Regel für Gamepads
       nach /etc/udev/rules.d, beides neu einlesen.
     - Dienst c64d neu starten und seinen Zustand zeigen.
Für ssh/scp fragt es nur nach dem Passwort, solange kein Schlüssel
eingetragen ist. Einen Schlüssel trägt man einmalig so ein (PowerShell,
fragt einmal nach dem Passwort des Boards):
    type $env:USERPROFILE\\.ssh\\id_ed25519.pub | ssh terasic@<Adresse> "mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
USER = "terasic"
STAGING = "/tmp/c64-install"
SCRIPTS = ["c64d.py", "c64_keys.py", "c64_disk.py", "c64_blocks.py", "c64_pads.py", "c64_hps.py"]
SERVICE = "c64d.service"
RULES = "99-c64-gamepad.rules"

# Läuft auf dem Board als root. install -o root -m 644 legt jede Datei als
# root an, ganz gleich, wem die Kopie in /tmp gehört.
INSTALL = f"""set -e
cd {STAGING}
install -d -o root -g root -m 755 /opt/c64
install -o root -g root -m 644 {' '.join(SCRIPTS)} /opt/c64/
install -o root -g root -m 644 {SERVICE} /etc/systemd/system/
install -o root -g root -m 644 {RULES} /etc/udev/rules.d/
udevadm control --reload
systemctl daemon-reload
systemctl restart c64d
rm -rf {STAGING}
sleep 2
systemctl is-active c64d
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("host", nargs="?", default=os.environ.get("C64_BOARD"),
                        help="Adresse des Boards (sonst Umgebungsvariable C64_BOARD)")
    args = parser.parse_args()
    if not args.host:
        parser.error("Adresse des Boards fehlt (Argument oder C64_BOARD)")
    remote = f"{USER}@{args.host}"

    # Frischer, eigener Zwischenordner (mkdir ohne -p scheitert, falls ihn
    # jemand anderes schon angelegt hat), dazu der Ordner für die Spiele.
    prepare = f"rm -rf {STAGING} && mkdir -m 700 {STAGING} && mkdir -p ~/c64"
    if subprocess.run(["ssh", remote, prepare]).returncode != 0:
        return "ssh fehlgeschlagen (Adresse richtig? Board im Netz?)"
    files = [str(HERE / name) for name in SCRIPTS + [SERVICE, RULES]]
    print(f"Kopiere {len(files)} Dateien nach {remote}:{STAGING} ...", flush=True)
    if subprocess.run(["scp", "-q", *files, f"{remote}:{STAGING}/"]).returncode != 0:
        return "scp fehlgeschlagen"

    # -t: ein Terminal auf dem Board, damit sudo nach dem Passwort fragen kann
    print("Installiere nach /opt/c64 und starte c64d neu (sudo fragt nach dem Passwort) ...",
          flush=True)
    result = subprocess.run(["ssh", "-t", remote, f"sudo sh -c '{INSTALL}'"])
    return 0 if result.returncode == 0 else "Installation fehlgeschlagen (siehe oben)"


if __name__ == "__main__":
    sys.exit(main())
