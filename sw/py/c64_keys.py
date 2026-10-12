"""USB-Tastatur am HPS als Tastatur des C64.

Läuft auf dem Board unter Linux, nicht auf dem PC.

Aufruf (root nötig, weil /dev/mem und die Tastatur geöffnet werden):
    sudo python3 c64_keys.py                      Tastatur selbst suchen
    sudo python3 c64_keys.py /dev/input/event0    dieses Gerät nehmen
    sudo python3 c64_keys.py --list               gefundene Tastaturen zeigen
Beenden mit Strg+C auf der Konsole, von der aus das Skript gestartet wurde.
Beim Booten von selbst starten: siehe c64-keys.service.

Linux meldet für jede Taste "gedrückt" und "losgelassen". Das Skript führt
Buch, welche Tasten gerade unten sind, und schreibt daraus den Zustand der 64
Tasten im Gitter des C64 in zwei Register von rtl/io/hps_byte_port.v:
    0x2001_0108  KEYS_LO  Tasten 31..0
    0x2001_010C  KEYS_HI  Tasten 63..32
    0x2001_0104  STATUS   Bit 1 = Taste RESTORE (hängt beim C64 nicht im
                          Gitter, sondern am NMI)
Die Nummern sind die aus rtl/io/key_matrix.v. So sieht der C64 gehaltene
Tasten und Kombinationen wie bei einer echten Tastatur.

Belegung nach Lage, nicht nach Aufdruck: Die Taste rechts neben L ist der
Doppelpunkt, wie auf dem C64 — egal, was auf der PC-Tastatur dort steht. Die
Namen unten sind die einer US-Tastatur (so nennt Linux die Tasten).

    Esc           RUN/STOP          Tab            CTRL
    Strg links    C= (Commodore)    `  (links der 1)   Pfeil links (<-)
    -             +                 =              -
    [             @                 ]              *
    ;             :                 '              ;
    \\             =                 Entf           Pfeil hoch (^)
    Ende          Pfund             Pos1           HOME
    Rücktaste     DEL               Einfg          INS (SHIFT + DEL)
    F1 F3 F5 F7   F1 F3 F5 F7       F2 F4 F6 F8    SHIFT + F1 F3 F5 F7
    Pfeil unten/rechts  Cursor      Pfeil oben/links   SHIFT + Cursor
    Bild auf      RESTORE
"""
import argparse
import fcntl
import glob
import mmap
import os
import re
import signal
import struct
import sys

PAGE_BASE = 0x2001_0000     # Anfang der Speicherseite mit den Registern
KEYS_LO = 0x108 // 4        # Register als Index in 32-Bit-Worten
KEYS_HI = 0x10C // 4
STATUS = 0x104 // 4
STATUS_RESTORE = 2          # Bit 1 von STATUS: Taste RESTORE

# Ein Ereignis von /dev/input/event* (struct input_event, 64-Bit-Linux):
# Zeit (2 x long), Art, Code, Wert.
EVENT = struct.Struct("llHHi")
EV_KEY = 1                  # Art: Taste; Wert 0 = los, 1 = gedrückt, 2 = Wiederholung
EVIOCGRAB = 0x40044590      # Tastatur allein beanspruchen (sonst tippt man auch in Linux)

RSHIFT = 52                 # rechte SHIFT-Taste im Gitter des C64
KEY_RESTORE = 104           # Bild auf -> RESTORE (eigenes Register, nicht im Gitter)

# Tastennummer von Linux (linux/input-event-codes.h) -> Tasten im Gitter des
# C64 (Nummern aus key_matrix.v). Zwei Einträge: SHIFT wird mitgedrückt.
KEYMAP = {
    1: (63,),           # Esc -> RUN/STOP
    2: (56,), 3: (59,), 4: (8,), 5: (11,), 6: (16,),        # 1 2 3 4 5
    7: (19,), 8: (24,), 9: (27,), 10: (32,), 11: (35,),     # 6 7 8 9 0
    12: (40,),          # -  -> +
    13: (43,),          # =  -> -
    14: (0,),           # Rücktaste -> DEL
    15: (58,),          # Tab -> CTRL
    16: (62,), 17: (9,), 18: (14,), 19: (17,), 20: (22,),   # Q W E R T
    21: (25,), 22: (30,), 23: (33,), 24: (38,), 25: (41,),  # Y U I O P
    26: (46,),          # [  -> @
    27: (49,),          # ]  -> *
    28: (1,),           # Enter -> RETURN
    29: (61,),          # Strg links -> C=
    30: (10,), 31: (13,), 32: (18,), 33: (21,), 34: (26,),  # A S D F G
    35: (29,), 36: (34,), 37: (37,), 38: (42,),             # H J K L
    39: (45,),          # ;  -> :
    40: (50,),          # '  -> ;
    41: (57,),          # `  -> Pfeil links
    42: (15,),          # SHIFT links
    43: (53,),          # \  -> =
    44: (12,), 45: (23,), 46: (20,), 47: (31,), 48: (28,),  # Z X C V B
    49: (39,), 50: (36,),                                   # N M
    51: (47,), 52: (44,), 53: (55,),                        # , . /
    54: (RSHIFT,),      # SHIFT rechts
    57: (60,),          # Leertaste
    59: (4,), 60: (4, RSHIFT),      # F1, F2
    61: (5,), 62: (5, RSHIFT),      # F3, F4
    63: (6,), 64: (6, RSHIFT),      # F5, F6
    65: (3,), 66: (3, RSHIFT),      # F7, F8
    102: (51,),         # Pos1 -> HOME
    103: (7, RSHIFT),   # Pfeil oben
    105: (2, RSHIFT),   # Pfeil links
    106: (2,),          # Pfeil rechts
    107: (48,),         # Ende -> Pfund
    108: (7,),          # Pfeil unten
    110: (0, RSHIFT),   # Einfg -> INS
    111: (54,),         # Entf -> Pfeil hoch
}


def find_keyboards() -> list[tuple[str, str]]:
    """Sucht Tastaturen in /proc/bus/input/devices: (Gerätedatei, Name)."""
    found = []
    try:
        text = open("/proc/bus/input/devices", encoding="utf-8", errors="replace").read()
    except OSError:
        return found
    for block in text.split("\n\n"):
        handlers = re.search(r"^H: Handlers=(.*)$", block, re.M)
        ev = re.search(r"^B: EV=([0-9a-fA-F]+)", block, re.M)
        name = re.search(r'^N: Name="(.*)"', block, re.M)
        if not handlers or not ev:
            continue
        event = re.search(r"\bevent\d+\b", handlers.group(1))
        # Eine Tastatur meldet Tasten (Bit 1) und Tastenwiederholung (Bit 20).
        if event and "kbd" in handlers.group(1) and int(ev.group(1), 16) & 0x100002 == 0x100002:
            found.append((f"/dev/input/{event.group(0)}", name.group(1) if name else "?"))
    return found


def matrix_state(pressed: set[int]) -> int:
    """Macht aus den gedrückten Linux-Tasten die 64 Bit für das Gitter."""
    state = 0
    for code in pressed:
        for key in KEYMAP.get(code, ()):
            state |= 1 << key
    return state


def write_state(reg, old: int, new: int) -> None:
    """Schreibt nur das Wort, das sich geändert hat.

    Ändern sich beide (Taste mit SHIFT, etwa Pfeil oben), kommt beim Drücken
    erst SHIFT und dann die Taste, beim Loslassen umgekehrt — sonst sähe der
    C64 für einen Augenblick die Taste ohne SHIFT. SHIFT rechts liegt im
    oberen Wort, alle Tasten, die es mitdrücken, im unteren.
    """
    lo, hi = new & 0xFFFFFFFF, new >> 32
    lo_changed = lo != old & 0xFFFFFFFF
    hi_changed = hi != old >> 32
    hi_first = hi & ~(old >> 32)
    if hi_changed and hi_first:
        reg[KEYS_HI] = hi
    if lo_changed:
        reg[KEYS_LO] = lo
    if hi_changed and not hi_first:
        reg[KEYS_HI] = hi


def stop(signum, frame):
    """Beenden durch systemd (SIGTERM) wie Strg+C behandeln: Tasten loslassen."""
    raise KeyboardInterrupt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("device", nargs="?", help="Gerätedatei der Tastatur (Default: selbst suchen)")
    parser.add_argument("--list", action="store_true", help="gefundene Tastaturen zeigen und beenden")
    args = parser.parse_args()

    keyboards = find_keyboards()
    if args.list:
        for path, name in keyboards:
            print(f"{path}  {name}")
        if not keyboards:
            print("Keine Tastatur gefunden.")
        return 0
    device = args.device or (keyboards[0][0] if keyboards else None)
    if device is None:
        by_id = sorted(glob.glob("/dev/input/by-id/*-event-kbd"))
        if not by_id:
            sys.exit("Keine Tastatur gefunden. Angesteckt? Sonst Gerätedatei angeben.")
        device = by_id[0]

    try:
        kbd = open(device, "rb", buffering=0)
        mem = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    except OSError as err:
        sys.exit(f"Öffnen fehlgeschlagen (mit sudo gestartet?): {err}")
    fcntl.ioctl(kbd, EVIOCGRAB, 1)
    signal.signal(signal.SIGTERM, stop)

    print(f"Tastatur {device} geht an den C64. Strg+C auf dieser Konsole beendet.", flush=True)
    with mmap.mmap(mem, mmap.PAGESIZE, offset=PAGE_BASE) as page:
        reg = memoryview(page).cast("I")
        pressed: set[int] = set()
        state = 0
        reg[KEYS_LO] = 0
        reg[KEYS_HI] = 0
        reg[STATUS] = 0
        try:
            while True:
                data = kbd.read(EVENT.size)
                if len(data) < EVENT.size:
                    print("Tastatur abgezogen.")
                    break
                _, _, kind, code, value = EVENT.unpack(data)
                if kind != EV_KEY or value == 2:
                    continue
                if code == KEY_RESTORE:
                    reg[STATUS] = STATUS_RESTORE if value else 0
                    continue
                if value:
                    pressed.add(code)
                else:
                    pressed.discard(code)
                new = matrix_state(pressed)
                write_state(reg, state, new)
                state = new
        except KeyboardInterrupt:
            pass
        except OSError:
            print("Tastatur abgezogen.")
        finally:
            # Alle Tasten loslassen, sonst bleiben sie im C64 gedrückt.
            reg[KEYS_LO] = 0
            reg[KEYS_HI] = 0
            reg[STATUS] = 0
            reg.release()
    return 0


if __name__ == "__main__":
    sys.exit(main())
