"""Dienst auf dem HPS: USB-Tastatur, Diskettenlaufwerk und Auswahlmenü des C64.

Läuft auf dem Board unter Linux, nicht auf dem PC. Braucht im selben
Verzeichnis c64_keys.py, c64_disk.py, c64_blocks.py und c64_pads.py.

Aufruf (root nötig: /dev/mem, Tastatur, USB-Stick einhängen):
    sudo python3 /opt/c64/c64d.py
    sudo python3 /opt/c64/c64d.py -v     jede Anforderung des Laufwerks anzeigen
Beim Booten von selbst starten: siehe c64d.service. Die Skripte liegen in
/opt/c64 und gehören root: Ein Dienst, der als root läuft, darf keine
Dateien ausführen, die ein normaler Benutzer ändern kann. sw/py/to_board.py
installiert sie dorthin.

Der Dienst macht drei Dinge zugleich:
  1. Die USB-Tastatur ist die Tastatur des C64 (Belegung siehe c64_keys.py),
     USB-Gamepads sind seine Joysticks (c64_pads.py).
  2. Er beliefert das Laufwerk 1541 mit den Spuren der eingelegten Diskette
     (wie c64_disk.py).
  3. F12 öffnet ein Menü, das als Fenster über dem Bild liegt
     (rtl/video/video_osd.v) — der C64 läuft darunter ungestört weiter, auch
     ein Spiel, das nach der nächsten Diskette fragt. Das Menü hat drei
     Reiter: DISK (Diskette einlegen oder herausnehmen, Programm laden),
     SETTINGS (Joystick-Port) und RESET (C64 zurücksetzen).

Die LEDs des Boards: LED 0 blinkt schnell, solange dieser Dienst nicht läuft
(Linux bootet noch), leuchtet, wenn er läuft, und blinkt langsam, wenn etwas
nicht stimmt (keine Tastatur gefunden, Speichern fehlgeschlagen). LED 1 ist
die Leuchte des Laufwerks. LED 2 leuchtet, solange die Diskette Änderungen
hat, die noch nicht in der Datei stehen — dann nicht ausschalten.

Der Ziffernblock ist ein Joystick: 8/2/4/6 sind die Richtungen, 7/9/1/3 die
Diagonalen, 0 und Strg rechts sind Feuer. An welchem Port des C64 er steckt
(die meisten Spiele erwarten Port 2), stellt man im Menü unter SETTINGS um.

USB-Gamepads (c64_pads.py) sind ebenfalls Joysticks: das erste an Port 2,
das zweite an Port 1. "Erstes" ist das am USB-Anschluss mit der kleineren
Nummer, damit die Zuordnung nach jedem Neustart gleich bleibt. Steuerkreuz =
Richtungen, die Aktionsknöpfe = Feuer, Start = RUN/STOP, Select = C=
(Commodore-Taste); beim Pad 081f:e401 ist nur A Feuer, X hoch (Springen),
B runter, Y die Leertaste. Pads lassen sich im Betrieb
anstecken und abziehen. Hängen Pad und Ziffernblock am selben Port, gilt,
was einer von beiden drückt. Unter SETTINGS steht, welches Pad wo steckt.

Im Menü:
    Pfeil links/rechts          Reiter wechseln (DISK, SETTINGS, RESET)
    Pfeil auf/ab, Bild auf/ab   Eintrag wählen
    Enter                       .D64/.G64 einlegen, .PRG laden, Joystick-Port
                                wechseln, C64 zurücksetzen
    Esc oder F12                Menü schließen
F12 öffnet immer den Reiter DISK, damit ein Enter nie aus Versehen den C64
zurücksetzt.
Solange das Menü offen ist, gehen die Tasten nicht an den C64.

Eine .D64 ist beschreibbar (SAVE, Spielstände): Was der C64 schreibt, steht
eine Sekunde später in der Datei. Vor der ersten Änderung legt der Dienst
einmalig eine Sicherung <name>.bak daneben. Der USB-Stick ist dabei nur für
den Augenblick des Schreibens beschreibbar eingehängt. Eine .G64 bleibt
schreibgeschützt.

Die Dateien sucht der Dienst auf einem USB-Stick (FAT32, nicht exFAT), der zum Beispiel
über einen Hub neben der Tastatur steckt; ist keiner da, im Ordner
/home/terasic/c64 (LOCAL_FOLDER). Ein .PRG wird direkt ins RAM des C64
geladen; beginnt es an der BASIC-Startadresse, tippt der Dienst danach RUN.

Vorsicht als root: Der Dienst liest und schreibt Dateien, die ein anderer
abgelegt hat. Er folgt deshalb keinen symbolischen Verknüpfungen (sie
erscheinen nicht in der Liste, geöffnet wird mit O_NOFOLLOW), nimmt nur
gewöhnliche Dateien bis zu einer Höchstgröße und legt die Sicherung .bak
nur neu an, ohne eine vorhandene Datei zu überschreiben (O_EXCL). Den Stick
hängt er als FAT ein, ohne Gerätedateien und Programme darauf zuzulassen
(nodev, nosuid, noexec).

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
import stat
import struct
import subprocess
import sys
import time
from pathlib import Path

import c64_disk as disk
import c64_keys as keys
import c64_pads as gamepads
from c64_blocks import BASIC_START, prg_to_blocks

BYTE_DATA = 0x100 // 4          # Register von hps_byte_port in der Seite 0x2001_0000
OSD_VISIBLE = 0x1000 // 4       # Register von video_osd im Bereich 0x2001_4000
OSD_TEXT = 0x1800 // 4
STATUS_RESET = 4                # Bit 2 von STATUS in hps_byte_port: Reset des C64
LEDS = 0x00C // 4               # Lebenszeichen an hps_status_led (Bereich 0x2001_4000)
LED_PROBLEM = 1                 # Bit 0: Zustands-LED blinkt langsam
LED_UNSAVED = 2                 # Bit 1: LED "Diskette hat ungespeicherte Änderungen"
LED_INTERVAL = 0.5              # so oft meldet sich der Dienst; das FPGA wartet 3 s
COLS, ROWS = 32, 16
LIST_ROWS = 10                  # Zeilen für Dateien im Fenster
LIST_TOP = 3
TABS = ("DISK", "SETTINGS", "RESET")
TAB_DISK, TAB_SETTINGS, TAB_RESET = range(len(TABS))

KEY_ESC, KEY_ENTER, KEY_F12 = 1, 28, 88
KEY_HOME, KEY_UP, KEY_PAGEUP, KEY_END, KEY_DOWN, KEY_PAGEDOWN = 102, 103, 104, 107, 108, 109
KEY_LEFT, KEY_RIGHT = 105, 106
REPEATING = (KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN)    # im Menü wirkt Gedrückthalten

# Joystick auf dem Ziffernblock: Tastennummer von Linux -> Bits des Joysticks
# (1 hoch, 2 runter, 4 links, 8 rechts, 16 Feuer). Die Ecken sind Diagonalen.
JOY_KEYS = {
    72: 1, 80: 2, 75: 4, 77: 8,         # 8, 2, 4, 6
    71: 1 | 4, 73: 1 | 8,               # 7, 9
    79: 2 | 4, 81: 2 | 8,               # 1, 3
    82: 16, 97: 16,                     # 0 und Strg rechts: Feuer
}

USB_MOUNT = "/run/c64-usb"      # hier hängt der Dienst den Stick selbst ein
LOCAL_FOLDER = "/home/terasic/c64"  # Dateien, wenn kein Stick steckt
MOUNT, UMOUNT = "/usr/bin/mount", "/usr/bin/umount"     # feste Pfade, nicht über PATH
MOUNT_OPTIONS = "nosuid,nodev,noexec"
EXTENSIONS = (".d64", ".g64", ".prg")
MAX_IMAGE = 1 << 20             # größte .d64/.g64 (eine .g64 hat meist ~330 KB)
MAX_PRG = 2 + 0x10000           # Ladeadresse und höchstens 64 KB


def read_file(path: Path, limit: int) -> bytes:
    """Liest eine gewöhnliche Datei bis zur Größe limit, ohne einer
    symbolischen Verknüpfung zu folgen. OSError mit lesbarer Meldung sonst."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(0, "KEINE NORMALE DATEI")
        if info.st_size > limit:
            raise OSError(0, "DATEI ZU GROSS")
        with os.fdopen(fd, "rb", closefd=False) as f:
            data = f.read(limit + 1)        # wächst sie beim Lesen, fällt es hier auf
        if len(data) > limit:
            raise OSError(0, "DATEI ZU GROSS")
        return data
    finally:
        os.close(fd)


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

    def show(self, lines: list) -> None:
        """lines: je Zeile (Text, invers) oder eine Liste solcher Stücke,
        die nebeneinander stehen (die Reiter); fehlende Zeilen und der Rest
        einer Zeile bleiben leer."""
        codes = []
        for row in range(ROWS):
            line = lines[row] if row < len(lines) else ("", False)
            row_codes = []
            for text, inverse in (line if isinstance(line, list) else [line]):
                row_codes += screen_codes(text, len(text), inverse)
            codes += (row_codes + screen_codes("", COLS))[:COLS]
        for i, code in enumerate(codes):
            if code != self.shown[i]:
                self.reg[OSD_TEXT + i] = code
                self.shown[i] = code
        self.reg[OSD_VISIBLE] = 1

    def hide(self) -> None:
        self.reg[OSD_VISIBLE] = 0


class Drive:
    """Das Laufwerk: eingelegte Diskette und die Anforderungen des FPGA.

    Eine .D64 ist beschreibbar. Was der C64 schreibt, landet zuerst im Abbild
    im Speicher und eine Sekunde nach dem letzten Schreiben in der Datei.
    Vor der ersten Änderung an einer Datei entsteht daneben einmalig eine
    Sicherung <name>.bak. Eine .G64 wird mit Schreibschutz eingelegt.

    Das Laufwerk ist eingeschaltet, solange dieser Dienst läuft — mit oder
    ohne Diskette. Beim Wechsel bleibt es an; ein Neustart löschte das
    Programm, das viele Spiele in das Laufwerk laden (Schnelllader).
    """

    FLUSH_AFTER = 1.0       # Sekunden Ruhe, bevor die Datei geschrieben wird

    def __init__(self, reg, verbose: bool = False):
        self.reg = reg
        self.verbose = verbose
        self.image = bytearray()
        self.original = b""         # Inhalt beim Einlegen, für die Sicherung
        self.path: Path | None = None
        self.supply = disk.blocks_d64
        self.name = ""
        self.writable = False
        self.dirty_since = 0.0      # 0 = nichts zu schreiben
        self.save_failed = False
        self.reg[disk.MOUNT] = disk.MOUNT_DRIVE_ON      # einschalten, noch ohne Diskette

    def insert(self, path: Path) -> str:
        """Legt ein Abbild ein. Liefert eine Fehlermeldung oder ''."""
        try:
            image = read_file(path, MAX_IMAGE)
        except OSError as err:
            return f"LESEFEHLER: {err.strerror}"
        is_g64 = image.startswith(disk.G64_MAGIC)
        if not is_g64 and len(image) not in disk.D64_SIZES:
            return "KEIN D64/G64 (GROESSE)"
        self.flush()
        self.save_failed = False
        self.image, self.original = bytearray(image), image
        self.path, self.name = path, path.name
        self.supply = disk.blocks_g64 if is_g64 else disk.blocks_d64
        self.writable = not is_g64
        # Jedes Schreiben von MOUNT gilt dem Laufwerk als Diskettenwechsel.
        self.reg[disk.MOUNT] = (disk.MOUNT_DRIVE_ON | disk.MOUNT_PRESENT
                                | (0 if self.writable else disk.MOUNT_READONLY)
                                | (disk.MOUNT_G64 if is_g64 else 0))
        return ""

    def eject(self) -> None:
        """Nimmt die Diskette heraus; das Laufwerk bleibt an."""
        self.flush()
        self.image, self.original, self.name, self.path = bytearray(), b"", "", None
        self.writable = False
        self.reg[disk.MOUNT] = disk.MOUNT_DRIVE_ON

    def power_off(self) -> None:
        """Schaltet das Laufwerk aus: Ohne Lieferanten darf es nicht laufen."""
        self.flush()
        self.reg[disk.MOUNT] = 0

    def serve(self) -> bool:
        """Bedient höchstens eine Anforderung des Laufwerks; True, wenn es eine gab."""
        # Auch ohne Diskette wird geliefert (lauter Nullen): Das Laufwerk
        # fragt nach dem Einschalten eine Spur an und wartet sonst ewig.
        request = self.reg[disk.REQUEST]
        if not request & 3:
            return False
        lba = request >> 16
        count = ((request >> 8) & 0x3F) + 1
        if request & 1:
            data = self.supply(self.image, lba, count)
            for i, word in enumerate(struct.unpack(f"<{len(data) // 4}I", data)):
                self.reg[disk.BUFFER + i] = word
            if self.verbose:
                print(f"geliefert: Block {lba}, {count} Blöcke", flush=True)
        else:
            # Eine geschriebene Spur liegt im Puffer: abholen und eintragen.
            words = [self.reg[disk.BUFFER + i] for i in range(count * disk.BLOCK // 4)]
            data = struct.pack(f"<{len(words)}I", *words)
            start = lba * disk.BLOCK
            if self.writable and start + len(data) <= len(self.image):
                if self.image[start:start + len(data)] != data:
                    self.image[start:start + len(data)] = data
                    self.dirty_since = time.monotonic()
                if self.verbose:
                    print(f"geschrieben: Block {lba}, {count} Blöcke", flush=True)
            elif self.verbose:
                print(f"Schreiben verworfen: Block {lba}, {count} Blöcke", flush=True)
        self.reg[disk.CONTROL] = 1          # geliefert bzw. abgeholt
        while self.reg[disk.CONTROL] & 1:
            pass
        return True

    def flush(self, only_if_idle: bool = False) -> None:
        """Schreibt das geänderte Abbild in seine Datei."""
        if not self.dirty_since or self.path is None:
            return
        if only_if_idle and time.monotonic() - self.dirty_since < self.FLUSH_AFTER:
            return
        self.dirty_since = 0.0
        mount = mount_point(self.path)
        remount = mount is not None and subprocess.run(
            [MOUNT, "-o", f"remount,rw,{MOUNT_OPTIONS}", mount], capture_output=True).returncode == 0
        try:
            # Sicherung nur neu anlegen: O_EXCL scheitert, wenn es sie schon
            # gibt — auch als Verknüpfung, die woandershin zeigt.
            backup = self.path.with_name(self.path.name + ".bak")
            try:
                fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
            except FileExistsError:
                pass
            else:
                with os.fdopen(fd, "wb") as handle:
                    handle.write(self.original)
            # Das Abbild selbst: dieselbe gewöhnliche Datei wie beim Einlegen
            # (keine Verknüpfung, gleiche Größe, nur ein Name).
            fd = os.open(self.path, os.O_WRONLY | os.O_NOFOLLOW)
            with os.fdopen(fd, "wb") as handle:
                info = os.fstat(handle.fileno())
                if (not stat.S_ISREG(info.st_mode) or info.st_size != len(self.image)
                        or info.st_nlink != 1):
                    raise OSError(0, "Datei hat sich seit dem Einlegen verändert")
                handle.write(self.image)
                handle.flush()
                os.fsync(handle.fileno())
            self.save_failed = False
            print(f"{self.name} gespeichert.", flush=True)
        except OSError as err:
            self.save_failed = True
            print(f"{self.name} lässt sich nicht speichern: {err}", flush=True)
        finally:
            if remount:
                subprocess.run([MOUNT, "-o", f"remount,ro,{MOUNT_OPTIONS}", mount], capture_output=True)


def mount_point(path: Path) -> str | None:
    """Einhängepunkt eines USB-Sticks, auf dem path liegt (sonst None)."""
    try:
        mounts = [ln.split() for ln in open("/proc/mounts", encoding="utf-8", errors="replace")]
    except OSError:
        return None
    resolved = str(path.resolve())
    for fields in mounts:
        if len(fields) > 1 and fields[0].startswith("/dev/sd"):
            point = fields[1].replace("\\040", " ")
            if resolved.startswith(point.rstrip("/") + "/"):
                return point
    return None

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
            subprocess.run([UMOUNT, "-l", fields[1]], capture_output=True)
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
        result = subprocess.run([MOUNT, "-t", "vfat", "-o", f"ro,{MOUNT_OPTIONS}", device, USB_MOUNT],
                                capture_output=True, text=True)
        if result.returncode == 0:
            return USB_MOUNT
        # Grund festhalten: erscheint im Protokoll des Dienstes (journalctl -u c64d)
        print(f"USB-Stick {device} lässt sich nicht einhängen: {result.stderr.strip()}", flush=True)
    return None


def list_files(folder: str) -> list[Path]:
    """Die Abbilder und Programme im Ordner; ohne Verknüpfungen, und nichts,
    wenn der Ordner selbst eine Verknüpfung ist."""
    try:
        if os.path.islink(folder):
            return []
        entries = [p for p in Path(folder).iterdir()
                   if p.suffix.lower() in EXTENSIONS and not p.is_symlink() and p.is_file()]
    except OSError:
        return []
    return sorted(entries, key=lambda p: p.name.lower())


class Menu:
    """Zustand des Auswahlmenüs mit drei Reitern (TABS)."""

    def __init__(self, osd: Osd, drive: Drive, load_prg, reset_c64):
        self.osd, self.drive, self.load_prg, self.reset_c64 = osd, drive, load_prg, reset_c64
        self.open = False
        self.joy_port = 2
        self.pad_names: list[str] = []      # Pads an Port 2 und 1, von main()
        self.tab = TAB_DISK
        # Je Reiter: Einträge (Text, Datei) oder (Text, "eject" / "joy" /
        # "reset"), gewählter Eintrag und oberste sichtbare Zeile.
        self.entries: list[list[tuple[str, Path | str]]] = [[] for _ in TABS]
        self.selected = [0] * len(TABS)
        self.top = [0] * len(TABS)
        self.source = ""
        self.message = ""

    def show(self) -> None:
        stick = find_stick()
        folder = stick or LOCAL_FOLDER
        self.source = "USB-STICK" if stick else f"KEIN USB-STICK: {folder}"
        files = list_files(folder)
        disk_entries = [(p.name, p) for p in files]
        if self.drive.name:
            disk_entries.insert(0, ("<DISKETTE HERAUSNEHMEN>", "eject"))
        self.entries[TAB_DISK] = disk_entries
        self.entries[TAB_SETTINGS] = [(f"ZIFFERNBLOCK: PORT {self.joy_port}", "joy")]
        self.entries[TAB_RESET] = [("C64 ZURUECKSETZEN", "reset")]
        self.tab = TAB_DISK
        self.selected[TAB_DISK] = min(self.selected[TAB_DISK], max(len(disk_entries) - 1, 0))
        self.message = "" if files else "KEINE .D64 .G64 .PRG GEFUNDEN"
        self.open = True
        self.draw()

    def close(self) -> None:
        self.open = False
        self.osd.hide()

    def draw(self) -> None:
        tab = self.tab
        if self.selected[tab] < self.top[tab]:
            self.top[tab] = self.selected[tab]
        if self.selected[tab] >= self.top[tab] + LIST_ROWS:
            self.top[tab] = self.selected[tab] - LIST_ROWS + 1
        tabs = [(" ", False)]
        for i, name in enumerate(TABS):
            tabs += [(f" {name} ", i == tab), (" ", False)]
        info = {TAB_DISK: "LAUFWERK 8: " + (self.drive.name or "LEER"),
                TAB_SETTINGS: "ENTER AENDERT DEN WERT",
                TAB_RESET: "PROGRAMM IM RAM GEHT VERLOREN"}[tab]
        lines = [tabs, (" " + info, False), ("", False)]
        entries = self.entries[tab]
        for row in range(LIST_ROWS):
            index = self.top[tab] + row
            if index < len(entries):
                lines.append((" " + entries[index][0], index == self.selected[tab]))
            else:
                lines.append(("", False))
        if tab == TAB_SETTINGS:
            names = self.pad_names + ["-", "-"]
            bottom = [" PAD AN PORT 2: " + names[0], " PAD AN PORT 1: " + names[1]]
        else:
            bottom = [" " + self.message, " " + self.source if tab == TAB_DISK else ""]
        lines += [(bottom[0], False),
                  (bottom[1], False),
                  (" <-> REITER  ENTER  ESC=ZURUECK", True)]
        self.osd.show(lines)

    def key(self, code: int) -> None:
        """Eine gedrückte Taste (oder Wiederholung) bei offenem Menü."""
        tab = self.tab
        entries = self.entries[tab]
        last = max(len(entries) - 1, 0)
        if code in (KEY_ESC, KEY_F12):
            self.close()
            return
        if code in (KEY_LEFT, KEY_RIGHT):
            self.tab = (tab + (1 if code == KEY_RIGHT else -1)) % len(TABS)
            self.message = ""
        elif code == KEY_UP:
            self.selected[tab] = max(self.selected[tab] - 1, 0)
        elif code == KEY_DOWN:
            self.selected[tab] = min(self.selected[tab] + 1, last)
        elif code == KEY_PAGEUP:
            self.selected[tab] = max(self.selected[tab] - LIST_ROWS, 0)
        elif code == KEY_PAGEDOWN:
            self.selected[tab] = min(self.selected[tab] + LIST_ROWS, last)
        elif code == KEY_HOME:
            self.selected[tab] = 0
        elif code == KEY_END:
            self.selected[tab] = last
        elif code == KEY_ENTER and entries:
            path = entries[self.selected[tab]][1]
            if path == "eject":
                self.drive.eject()
                self.close()
                return
            if path == "reset":
                self.reset_c64()
                self.close()
                return
            if path == "joy":
                self.joy_port = 1 if self.joy_port == 2 else 2
                entries[self.selected[tab]] = (f"ZIFFERNBLOCK: PORT {self.joy_port}", "joy")
                self.draw()
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
                prg = read_file(path, MAX_PRG)
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
            reg_a[keys.STATUS] = 0          # RESTORE und beide Joysticks

        def reset_c64() -> None:
            """Hält den C64 kurz im Reset, wie der Taster am Board."""
            reg_a[keys.STATUS] = STATUS_RESET
            time.sleep(0.05)
            write_status()

        def write_status() -> None:
            """RESTORE (Bit 1) und die Joysticks an Port 1 (ab Bit 8) und
            Port 2 (ab Bit 16): Ziffernblock am gewählten Port, erstes Pad
            an Port 2, zweites an Port 1."""
            port = {1: 0, 2: 0}
            for code in joy_pressed:
                port[menu.joy_port] |= JOY_KEYS[code]
            for pad, number in zip(pads, (2, 1)):
                port[number] |= pad.bits()
            reg_a[keys.STATUS] = ((keys.STATUS_RESTORE if restore else 0)
                                  | port[1] << 8 | port[2] << 16)

        def write_keys() -> None:
            """Tastengitter aus der USB-Tastatur und den Knöpfen Start/Select
            der Pads (RUN/STOP, C=); bei offenem Menü nur die Tastatur."""
            nonlocal state
            held = set(pressed)
            if not menu.open:
                for pad in pads:
                    held |= pad.keys()
            new = keys.matrix_state(held)
            keys.write_state(reg_a, state, new)
            state = new

        def drop_pad(pad) -> None:
            """Ein Pad, das nicht mehr antwortet (abgezogen), sofort entfernen."""
            pad.close()
            pads.remove(pad)
            print(f"Gamepad abgezogen: {pad.name}", flush=True)
            menu.pad_names = [p.name for p in pads]
            if menu.open:
                menu.draw()
            write_status()
            write_keys()

        def scan_pads() -> None:
            """Pads anstecken und abziehen: höchstens zwei, nach USB-Anschluss."""
            nonlocal pads
            wanted = gamepads.find_pads()[:2]
            if [p.path for p in pads] == [path for _, path, _ in wanted]:
                return
            kept = {p.path: p for p in pads}
            new = []
            for phys, path, name in wanted:
                if path in kept:
                    new.append(kept.pop(path))
                    continue
                try:
                    new.append(gamepads.OpenPad(phys, path, name))
                    print(f"Gamepad: {name} ({phys})", flush=True)
                except OSError:
                    pass
            for gone in kept.values():
                gone.close()
                print(f"Gamepad abgezogen: {gone.name}", flush=True)
            pads = new
            menu.pad_names = [p.name for p in pads]
            if menu.open:
                menu.draw()
            write_status()
            write_keys()

        drive = Drive(reg_b, verbose="-v" in sys.argv[1:])
        busy_until = 0.0        # solange wird das Laufwerk ohne Pause abgefragt
        next_led = 0.0
        started = time.monotonic()
        next_report = 0.0
        menu = Menu(Osd(reg_b), drive, load_prg, reset_c64)
        kbd = None
        next_try = 0.0
        pads: list[gamepads.OpenPad] = []
        next_pad_scan = 0.0
        pressed: set[int] = set()
        joy_pressed: set[int] = set()
        restore = False
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

                # Pads suchen: angesteckte öffnen, abgezogene schließen
                if time.monotonic() >= next_pad_scan:
                    next_pad_scan = time.monotonic() + 1.0
                    scan_pads()

                # Arbeitet das Laufwerk gerade, wird nicht geschlafen: Es
                # wartet bei jedem Spurwechsel auf seine Lieferung.
                pause = 0.0 if time.monotonic() < busy_until else 0.0005
                fds = ([kbd] if kbd is not None else []) + [p.fd for p in pads]
                ready = select.select(fds, [], [], pause)[0]
                for pad in list(pads):
                    if pad.fd not in ready:
                        continue
                    try:
                        data = os.read(pad.fd, keys.EVENT.size * 32)
                    except BlockingIOError:
                        continue
                    except OSError:         # abgezogen
                        drop_pad(pad)
                        continue
                    changed = False
                    for offset in range(0, len(data) - keys.EVENT.size + 1, keys.EVENT.size):
                        _, _, kind, code, value = keys.EVENT.unpack_from(data, offset)
                        changed |= pad.event(kind, code, value)
                    if changed:
                        write_status()
                        write_keys()
                if kbd is not None and kbd in ready:
                    try:
                        data = os.read(kbd, keys.EVENT.size * 32)
                    except BlockingIOError:
                        data = b""
                    except OSError:
                        os.close(kbd)       # abgezogen
                        kbd, data, pressed, state = None, b"", set(), 0
                        joy_pressed, restore = set(), False
                        release_all()
                        write_status()      # Pads gelten weiter
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
                                joy_pressed, restore = set(), False
                                release_all()
                                write_status()      # Pads gelten weiter
                                menu.show()
                            continue
                        if code == keys.KEY_RESTORE:
                            restore = bool(value)
                            write_status()
                            continue
                        if code in JOY_KEYS:
                            if value:
                                joy_pressed.add(code)
                            else:
                                joy_pressed.discard(code)
                            write_status()
                            continue
                        if value:
                            pressed.add(code)
                        else:
                            pressed.discard(code)
                        write_keys()

                if drive.serve():
                    busy_until = time.monotonic() + 0.5
                drive.flush(only_if_idle=True)

                # Lebenszeichen für die Zustands-LED. Ein Problem ist: keine
                # Tastatur (in den ersten Sekunden noch kein Grund zur Sorge)
                # oder ein gescheitertes Speichern.
                now = time.monotonic()
                if now >= next_led:
                    next_led = now + LED_INTERVAL
                    problem = drive.save_failed or (kbd is None and now - started > 5.0)
                    reg_b[LEDS] = ((LED_PROBLEM if problem else 0)
                                   | (LED_UNSAVED if drive.dirty_since else 0))

                # Mit -v alle zwei Sekunden ein Lebenszeichen mit dem Stand
                # der Register, zur Fehlersuche.
                if drive.verbose and time.monotonic() >= next_report:
                    next_report = time.monotonic() + 2.0
                    print(f"Stand: REQUEST={reg_b[disk.REQUEST]:08x} CONTROL={reg_b[disk.CONTROL]:x} "
                          f"MOUNT={reg_b[disk.MOUNT]:x} Tasten={state:016x} STATUS={reg_a[keys.STATUS]:06x} Menü={'offen' if menu.open else 'zu'} "
                          f"Tastatur={'da' if kbd is not None else 'fehlt'}", flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            release_all()
            menu.osd.hide()
            drive.power_off()
            reg_a.release()
            reg_b.release()
            if kbd is not None:
                os.close(kbd)
            for pad in pads:
                pad.close()
    print("c64d beendet.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
