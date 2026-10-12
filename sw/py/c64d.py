"""Dienst auf dem HPS: USB-Tastatur, Diskettenlaufwerk und Auswahlmenü des C64.

Läuft auf dem Board unter Linux, nicht auf dem PC. Braucht im selben
Verzeichnis c64_keys.py, c64_disk.py und c64_blocks.py.

Aufruf (root nötig: /dev/mem, Tastatur, USB-Stick einhängen):
    sudo python3 c64d.py
    sudo python3 c64d.py -v     jede Anforderung des Laufwerks anzeigen
Beim Booten von selbst starten: siehe c64d.service.

Der Dienst macht drei Dinge zugleich:
  1. Die USB-Tastatur ist die Tastatur des C64 (Belegung siehe c64_keys.py).
  2. Er beliefert das Laufwerk 1541 mit den Spuren der eingelegten Diskette
     (wie c64_disk.py).
  3. F12 öffnet ein Menü, das als Fenster über dem Bild liegt
     (rtl/video/video_osd.v) — der C64 läuft darunter ungestört weiter, auch
     ein Spiel, das nach der nächsten Diskette fragt.

Im Menü:
    Pfeil auf/ab, Bild auf/ab   Eintrag wählen
    Enter                       .D64/.G64 einlegen, .PRG laden
    Esc oder F12                Menü schließen
Solange das Menü offen ist, gehen die Tasten nicht an den C64.

Die Dateien sucht der Dienst auf einem USB-Stick (FAT32, nicht exFAT), der zum Beispiel
über einen Hub neben der Tastatur steckt; ist keiner da, im Verzeichnis
dieses Skripts. Ein .PRG wird direkt ins RAM des C64 geladen; beginnt es an
der BASIC-Startadresse, tippt der Dienst danach RUN.

Register (siehe quartus_hps/README.md): Tasten und Bytes ab 0x2001_0100,
Diskette ab 0x2001_4000, Menüfenster ab 0x2001_5000 (Wort 0: Bit 0 =
sichtbar; ab 0x2001_5800 ein Zeichen pro Wort, 32 x 16, als Bildschirmcode
des C64, ab 128 invers).
"""
from __future__ import annotations

import fcntl
import glob
import mmap
import os
import select
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

import c64_disk as disk
import c64_keys as keys
from c64_blocks import BASIC_START, prg_to_blocks

BYTE_DATA = 0x100 // 4          # Register von hps_byte_port in der Seite 0x2001_0000
OSD_VISIBLE = 0x1000 // 4       # Register von video_osd im Bereich 0x2001_4000
OSD_TEXT = 0x1800 // 4
COLS, ROWS = 32, 16
LIST_ROWS = 10                  # Zeilen für Dateien im Fenster
LIST_TOP = 3

KEY_ESC, KEY_ENTER, KEY_F12 = 1, 28, 88
KEY_HOME, KEY_UP, KEY_PAGEUP, KEY_END, KEY_DOWN, KEY_PAGEDOWN = 102, 103, 104, 107, 108, 109
REPEATING = (KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN)    # im Menü wirkt Gedrückthalten

USB_MOUNT = "/run/c64-usb"      # hier hängt der Dienst den Stick selbst ein
EXTENSIONS = (".d64", ".g64", ".prg")


def screen_codes(text: str, width: int, inverse: bool = False) -> list[int]:
    """ASCII -> Bildschirmcodes des C64, auf width Zeichen gebracht.

    Im Zeichensatz des C64 liegen @ und A-Z bei 0-26, Ziffern und die
    meisten Satzzeichen an ihrer ASCII-Stelle. Was es nicht gibt, wird ein
    Punkt. Invers ist derselbe Code plus 128.
    """
    codes = []
    for ch in text.upper()[:width].ljust(width):
        n = ord(ch)
        if 0x40 <= n <= 0x5D:
            n -= 0x40
        elif not 0x20 <= n <= 0x3F:
            n = 0x2E
        codes.append(n | 0x80 if inverse else n)
    return codes


class Osd:
    """Das Menüfenster: schreibt nur die Zeichen, die sich geändert haben."""

    def __init__(self, reg):
        self.reg = reg
        self.shown = [None] * (COLS * ROWS)
        self.hide()

    def show(self, lines: list[tuple[str, bool]]) -> None:
        """lines: je Zeile (Text, invers); fehlende Zeilen bleiben leer."""
        codes = []
        for row in range(ROWS):
            text, inverse = lines[row] if row < len(lines) else ("", False)
            codes += screen_codes(text, COLS, inverse)
        for i, code in enumerate(codes):
            if code != self.shown[i]:
                self.reg[OSD_TEXT + i] = code
                self.shown[i] = code
        self.reg[OSD_VISIBLE] = 1

    def hide(self) -> None:
        self.reg[OSD_VISIBLE] = 0


class Drive:
    """Das Laufwerk: eingelegte Diskette und die Anforderungen des FPGA."""

    def __init__(self, reg, verbose: bool = False):
        self.reg = reg
        self.verbose = verbose
        self.image = b""
        self.supply = disk.blocks_d64
        self.name = ""
        self.eject()

    def insert(self, path: Path) -> str:
        """Legt ein Abbild ein. Liefert eine Fehlermeldung oder ''."""
        try:
            image = path.read_bytes()
        except OSError as err:
            return f"LESEFEHLER: {err.strerror}"
        is_g64 = image.startswith(disk.G64_MAGIC)
        if not is_g64 and len(image) not in disk.D64_SIZES:
            return "KEIN D64/G64 (GROESSE)"
        self.image, self.name = image, path.name
        self.supply = disk.blocks_g64 if is_g64 else disk.blocks_d64
        # Jedes Schreiben von MOUNT gilt dem Laufwerk als Diskettenwechsel.
        self.reg[disk.MOUNT] = (disk.MOUNT_PRESENT | disk.MOUNT_READONLY
                                | (disk.MOUNT_G64 if is_g64 else 0))
        return ""

    def eject(self) -> None:
        self.image, self.name = b"", ""
        self.reg[disk.MOUNT] = 0

    def serve(self) -> bool:
        """Bedient höchstens eine Anforderung des Laufwerks; True, wenn es eine gab."""
        if not self.image:
            return False                    # keine Diskette: das Laufwerk ruht im Reset
        request = self.reg[disk.REQUEST]
        if not request & 3:
            return False
        if request & 1:
            lba = request >> 16
            count = ((request >> 8) & 0x3F) + 1
            data = self.supply(self.image, lba, count)
            for i, word in enumerate(struct.unpack(f"<{len(data) // 4}I", data)):
                self.reg[disk.BUFFER + i] = word
            if self.verbose:
                print(f"geliefert: Block {lba}, {count} Blöcke", flush=True)
        elif self.verbose:
            print(f"Schreibwunsch verworfen: Block {request >> 16}", flush=True)
        self.reg[disk.CONTROL] = 1          # geliefert (Schreibwünsche: verworfen)
        while self.reg[disk.CONTROL] & 1:
            pass
        return True


def find_stick() -> str | None:
    """Verzeichnis eines USB-Sticks, nötigenfalls selbst eingehängt (nur lesen)."""
    try:
        mounts = [ln.split() for ln in open("/proc/mounts", encoding="utf-8", errors="replace")]
    except OSError:
        mounts = []
    for fields in mounts:
        if len(fields) > 1 and fields[0].startswith("/dev/sd"):
            if os.path.exists(fields[0]):
                return fields[1].replace("\\040", " ")
            # Stick wurde abgezogen, ohne ausgehängt zu werden
            subprocess.run(["umount", "-l", fields[1]], capture_output=True)
    for device in sorted(glob.glob("/dev/sd?1")) + sorted(glob.glob("/dev/sd?")):
        # Kartenleser und leere Steckplätze melden ein Gerät ohne Medium
        # (Größe 0); ein Versuch, es einzuhängen, füllt nur das Kernel-Log.
        try:
            size = int(Path(f"/sys/class/block/{os.path.basename(device)}/size").read_text())
        except (OSError, ValueError):
            size = 0
        if size == 0:
            continue
        os.makedirs(USB_MOUNT, exist_ok=True)
        result = subprocess.run(["mount", "-o", "ro", device, USB_MOUNT], capture_output=True, text=True)
        if result.returncode == 0:
            return USB_MOUNT
        # Grund festhalten: erscheint im Protokoll des Dienstes (journalctl -u c64d)
        print(f"USB-Stick {device} lässt sich nicht einhängen: {result.stderr.strip()}", flush=True)
    return None


def list_files(folder: str) -> list[Path]:
    try:
        entries = [p for p in Path(folder).iterdir() if p.suffix.lower() in EXTENSIONS and p.is_file()]
    except OSError:
        return []
    return sorted(entries, key=lambda p: p.name.lower())


class Menu:
    """Zustand des Auswahlmenüs."""

    def __init__(self, osd: Osd, drive: Drive, load_prg):
        self.osd, self.drive, self.load_prg = osd, drive, load_prg
        self.open = False
        self.entries: list[tuple[str, Path | None]] = []
        self.selected = 0
        self.top = 0
        self.source = ""
        self.message = ""

    def show(self) -> None:
        stick = find_stick()
        folder = stick or str(Path(__file__).resolve().parent)
        self.source = "USB-STICK" if stick else f"KEIN USB-STICK: {folder}"
        self.entries = [(p.name, p) for p in list_files(folder)]
        if self.drive.name:
            self.entries.insert(0, ("<DISKETTE HERAUSNEHMEN>", None))
        self.selected = min(self.selected, max(len(self.entries) - 1, 0))
        self.message = "" if self.entries else "KEINE .D64 .G64 .PRG GEFUNDEN"
        self.open = True
        self.draw()

    def close(self) -> None:
        self.open = False
        self.osd.hide()

    def draw(self) -> None:
        if self.selected < self.top:
            self.top = self.selected
        if self.selected >= self.top + LIST_ROWS:
            self.top = self.selected - LIST_ROWS + 1
        lines = [(" C64: DISKETTE ODER PROGRAMM", True),
                 (" LAUFWERK 8: " + (self.drive.name or "LEER"), False),
                 ("", False)]
        for row in range(LIST_ROWS):
            index = self.top + row
            if index < len(self.entries):
                lines.append((" " + self.entries[index][0], index == self.selected))
            else:
                lines.append(("", False))
        lines += [(" " + self.message, False),
                  (" " + self.source, False)]
        lines.append((" PFEILE  ENTER  ESC=ZURUECK", True))
        self.osd.show(lines)

    def key(self, code: int) -> None:
        """Eine gedrückte Taste (oder Wiederholung) bei offenem Menü."""
        last = len(self.entries) - 1
        if code in (KEY_ESC, KEY_F12):
            self.close()
            return
        if code == KEY_UP:
            self.selected = max(self.selected - 1, 0)
        elif code == KEY_DOWN:
            self.selected = min(self.selected + 1, max(last, 0))
        elif code == KEY_PAGEUP:
            self.selected = max(self.selected - LIST_ROWS, 0)
        elif code == KEY_PAGEDOWN:
            self.selected = min(self.selected + LIST_ROWS, max(last, 0))
        elif code == KEY_HOME:
            self.selected = 0
        elif code == KEY_END:
            self.selected = max(last, 0)
        elif code == KEY_ENTER and self.entries:
            path = self.entries[self.selected][1]
            if path is None:
                self.drive.eject()
                self.close()
                return
            if path.suffix.lower() == ".prg":
                self.message = self.load_prg(path)
            else:
                self.message = self.drive.insert(path)
            if not self.message:
                self.close()
                return
        self.draw()


def stop(signum, frame):
    """Beenden durch systemd (SIGTERM) wie Strg+C behandeln: aufräumen."""
    raise KeyboardInterrupt


def main() -> int:
    try:
        mem = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    except OSError as err:
        sys.exit(f"/dev/mem lässt sich nicht öffnen (mit sudo gestartet?): {err}")
    # Nur ein Programm zugleich darf Tastatur und Laufwerk bedienen — auch
    # nicht dieser Dienst zweimal (einmal von systemd, einmal von Hand).
    locks = [keys.claim("tastatur"), disk.claim("laufwerk")]
    signal.signal(signal.SIGTERM, stop)

    with mmap.mmap(mem, mmap.PAGESIZE, offset=keys.PAGE_BASE) as page_a, \
         mmap.mmap(mem, disk.SPAN, offset=disk.PAGE_BASE) as page_b:
        # Als 32-Bit-Worte ansprechen: je Zugriff genau ein Vorgang auf dem Bus.
        reg_a = memoryview(page_a).cast("I")    # Tasten, Bytes
        reg_b = memoryview(page_b).cast("I")    # Diskette, Menüfenster

        def send_bytes(data: bytes) -> bool:
            for value in data:
                deadline = time.monotonic() + 2.0
                while reg_a[keys.STATUS] & 1:
                    drive.serve()
                    if time.monotonic() > deadline:
                        return False
                reg_a[BYTE_DATA] = value
            return True

        def load_prg(path: Path) -> str:
            try:
                prg = path.read_bytes()
                blocks = prg_to_blocks(prg)
            except OSError as err:
                return f"LESEFEHLER: {err.strerror}"
            except ValueError as err:
                return str(err)
            if prg[0] | (prg[1] << 8) == BASIC_START:
                blocks += b"RUN\r"
            return "" if send_bytes(blocks) else "DER C64 NIMMT NICHTS AN"

        def release_all() -> None:
            reg_a[keys.KEYS_LO] = 0
            reg_a[keys.KEYS_HI] = 0
            reg_a[keys.STATUS] = 0

        drive = Drive(reg_b, verbose="-v" in sys.argv[1:])
        busy_until = 0.0        # solange wird das Laufwerk ohne Pause abgefragt
        next_report = 0.0
        menu = Menu(Osd(reg_b), drive, load_prg)
        kbd = None
        next_try = 0.0
        pressed: set[int] = set()
        state = 0
        release_all()
        print("c64d läuft: Tastatur, Laufwerk 8, Menü mit F12.", flush=True)

        try:
            while True:
                # Tastatur suchen, falls keine da ist (auch nach dem Abziehen)
                if kbd is None and time.monotonic() >= next_try:
                    next_try = time.monotonic() + 1.0
                    found = keys.find_keyboards()
                    if found:
                        try:
                            kbd = os.open(found[0][0], os.O_RDONLY | os.O_NONBLOCK)
                            fcntl.ioctl(kbd, keys.EVIOCGRAB, 1)
                            print(f"Tastatur: {found[0][1]}", flush=True)
                        except OSError:
                            kbd = None

                # Arbeitet das Laufwerk gerade, wird nicht geschlafen: Es
                # wartet bei jedem Spurwechsel auf seine Lieferung.
                pause = 0.0 if time.monotonic() < busy_until else 0.0005
                ready = select.select([kbd] if kbd is not None else [], [], [], pause)[0]
                if ready:
                    try:
                        data = os.read(kbd, keys.EVENT.size * 32)
                    except BlockingIOError:
                        data = b""
                    except OSError:
                        os.close(kbd)       # abgezogen
                        kbd, data, pressed, state = None, b"", set(), 0
                        release_all()
                    for offset in range(0, len(data) - keys.EVENT.size + 1, keys.EVENT.size):
                        _, _, kind, code, value = keys.EVENT.unpack_from(data, offset)
                        if kind != keys.EV_KEY:
                            continue
                        if menu.open:
                            if value == 1 or (value == 2 and code in REPEATING):
                                menu.key(code)
                            continue
                        if value == 2:
                            continue
                        if code == KEY_F12:
                            if value:
                                pressed, state = set(), 0
                                release_all()
                                menu.show()
                            continue
                        if code == keys.KEY_RESTORE:
                            reg_a[keys.STATUS] = keys.STATUS_RESTORE if value else 0
                            continue
                        if value:
                            pressed.add(code)
                        else:
                            pressed.discard(code)
                        new = keys.matrix_state(pressed)
                        keys.write_state(reg_a, state, new)
                        state = new

                if drive.serve():
                    busy_until = time.monotonic() + 0.5

                # Mit -v alle zwei Sekunden ein Lebenszeichen mit dem Stand
                # der Register, zur Fehlersuche.
                if drive.verbose and time.monotonic() >= next_report:
                    next_report = time.monotonic() + 2.0
                    print(f"Stand: REQUEST={reg_b[disk.REQUEST]:08x} CONTROL={reg_b[disk.CONTROL]:x} "
                          f"MOUNT={reg_b[disk.MOUNT]:x} Tasten={state:016x} Menü={'offen' if menu.open else 'zu'} "
                          f"Tastatur={'da' if kbd is not None else 'fehlt'}", flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            release_all()
            menu.osd.hide()
            drive.eject()
            reg_a.release()
            reg_b.release()
            if kbd is not None:
                os.close(kbd)
    print("c64d beendet.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
