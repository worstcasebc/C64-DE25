"""USB-Gamepads am HPS als Joysticks des C64 — benutzt von c64d.py.

Läuft auf dem Board unter Linux. Ein Pad meldet sich bei Linux als
Eingabegerät mit zwei Achsen (X, Y) und Knöpfen. Ausprobiert mit dem Modell
081f:e401 ("USB gamepad", SNES-Form): Das Steuerkreuz sind die Achsen
X und Y mit 0 (links/hoch), 127 (Mitte) und 255 (rechts/runter); die vier
Aktionsknöpfe sind 0x120..0x123, Select und Start 0x128/0x129.

Ein Joystick des C64 kennt nur fünf Schalter: hoch, runter, links, rechts,
Feuer. Das Pad wird darauf abgebildet wie ein Steuerkreuz auf einen
Schalter-Joystick: Steht eine Achse im unteren Viertel ihres Bereichs, ist
"links" bzw. "hoch" gedrückt, im oberen Viertel "rechts" bzw. "runter".
Das passt auch für Analog-Sticks. Jeder Joystick- oder Gamepad-Knopf außer
Select und Start ist Feuer. Start ist die Taste RUN/STOP, Select die
Commodore-Taste (C=) — sie zählen wie Esc und Strg links auf der
USB-Tastatur (siehe c64_keys.py), gleich an welchem Port das Pad steckt.

Welches Pad an welchem Port des C64 steckt, entscheidet c64d.py: Die Pads
werden nach ihrem USB-Anschluss sortiert (Phys in /proc/bus/input/devices),
damit die Reihenfolge nach jedem Neustart dieselbe ist.

Viele billige Pads melden sich mit 500 mA an, obwohl sie fast nichts
brauchen; an einem Hub ohne eigenes Netzteil (100 mA je Anschluss) lehnt
Linux sie dann ab. Dagegen hilft die udev-Regel 99-c64-gamepad.rules.
"""
from __future__ import annotations

import os
import re
import struct

# Bits eines Joysticks im Register STATUS von hps_byte_port (wie JOY_KEYS
# in c64d.py): 1 hoch, 2 runter, 4 links, 8 rechts, 16 Feuer.
UP, DOWN, LEFT, RIGHT, FIRE = 1, 2, 4, 8, 16

EV_KEY, EV_ABS = 1, 3
ABS_X, ABS_Y = 0, 1
BTN_FIRST, BTN_LAST = 0x120, 0x13F      # BTN_JOYSTICK .. Ende von BTN_GAMEPAD
# Knöpfe, die eine Taste der USB-Tastatur nachbilden (Linux-Tastennummern
# wie in c64_keys.KEYMAP): 1 = Esc -> RUN/STOP, 29 = Strg links -> C=.
AS_KEY = {0x129: 1, 0x128: 29,          # Start, Select beim Modell 081f:e401
          0x13B: 1, 0x13A: 29}          # BTN_START, BTN_SELECT anderer Pads
NO_FIRE = set(AS_KEY) | {0x13C}         # dazu BTN_MODE: weder Feuer noch Taste
EVIOCGABS = 0x80184540                  # + Achse: Bereich lesen (struct input_absinfo)


def _has_bit(mask: str, bit: int) -> bool:
    """Prüft ein Bit in einer Bitmaske aus /proc/bus/input/devices.

    Linux schreibt sie als Hex-Wörter mit Leerzeichen, das höchste zuerst;
    jedes Wort ist so breit wie ein long, auf dem Board (64-Bit-ARM) also
    64 Bit, führende Nullen weggelassen.
    """
    value = 0
    for word in mask.split():
        value = (value << 64) | int(word, 16)
    return bool(value >> bit & 1)


def parse_pads(text: str) -> list[tuple[str, str, str]]:
    """Pads aus dem Inhalt von /proc/bus/input/devices: (Phys, Gerätedatei,
    Name), sortiert nach Phys. Ein Pad hat die Achsen X und Y und mindestens
    einen Joystick- oder Gamepad-Knopf."""
    found = []
    for block in text.split("\n\n"):
        handlers = re.search(r"^H: Handlers=(.*)$", block, re.M)
        event = re.search(r"\bevent\d+\b", handlers.group(1)) if handlers else None
        abs_mask = re.search(r"^B: ABS=(.*)$", block, re.M)
        key_mask = re.search(r"^B: KEY=(.*)$", block, re.M)
        if not (event and abs_mask and key_mask):
            continue
        if not (_has_bit(abs_mask.group(1), ABS_X) and _has_bit(abs_mask.group(1), ABS_Y)):
            continue
        if not any(_has_bit(key_mask.group(1), b) for b in range(BTN_FIRST, BTN_LAST + 1)):
            continue
        phys = re.search(r"^P: Phys=(.*)$", block, re.M)
        name = re.search(r'^N: Name="(.*)"', block, re.M)
        found.append((phys.group(1) if phys else "", f"/dev/input/{event.group(0)}",
                      name.group(1).strip() if name else "?"))
    return sorted(found)


def find_pads() -> list[tuple[str, str, str]]:
    """Die angesteckten Pads, siehe parse_pads."""
    try:
        with open("/proc/bus/input/devices", encoding="utf-8", errors="replace") as f:
            return parse_pads(f.read())
    except OSError:
        return []


class Pad:
    """Ein Pad: hält den Zustand von Achsen und Knöpfen und rechnet daraus
    die fünf Bits des Joysticks."""

    def __init__(self, ranges: dict[int, tuple[int, int, int]]):
        # ranges: Achse -> (jetziger Wert, min, max). Grenzen bei einem bzw.
        # drei Vierteln des Bereichs.
        self.limits = {axis: (lo + (hi - lo) // 4, hi - (hi - lo) // 4)
                       for axis, (_, lo, hi) in ranges.items()}
        self.axes = {axis: value for axis, (value, _, _) in ranges.items()}
        self.fire: set[int] = set()
        self.held: set[int] = set()         # Knöpfe aus AS_KEY, die unten sind

    def event(self, kind: int, code: int, value: int) -> bool:
        """Ein Ereignis von Linux; True, wenn sich die Bits ändern könnten."""
        if kind == EV_ABS and code in self.axes:
            self.axes[code] = value
            return True
        if kind != EV_KEY or not BTN_FIRST <= code <= BTN_LAST:
            return False
        target = self.held if code in AS_KEY else None if code in NO_FIRE else self.fire
        if target is None:
            return False
        if value:
            target.add(code)
        else:
            target.discard(code)
        return True

    def keys(self) -> set[int]:
        """Die Tasten der USB-Tastatur, die das Pad gerade "drückt"."""
        return {AS_KEY[code] for code in self.held}

    def bits(self) -> int:
        result = FIRE if self.fire else 0
        for axis, minus, plus in ((ABS_X, LEFT, RIGHT), (ABS_Y, UP, DOWN)):
            low, high = self.limits[axis]
            if self.axes[axis] <= low:
                result |= minus
            elif self.axes[axis] >= high:
                result |= plus
        return result


class OpenPad(Pad):
    """Ein geöffnetes Pad auf dem Board (Gerätedatei, Bereiche von Linux)."""

    def __init__(self, phys: str, path: str, name: str):
        import fcntl    # erst hier: gibt es nur unter Linux, der Test läuft auch am PC
        self.phys, self.path, self.name = phys, path, name
        self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        ranges = {}
        for axis in (ABS_X, ABS_Y):
            buf = bytearray(24)
            fcntl.ioctl(self.fd, EVIOCGABS + axis, buf)
            value, lo, hi, _, _, _ = struct.unpack("6i", buf)
            ranges[axis] = (value, lo, hi)
        super().__init__(ranges)

    def close(self) -> None:
        os.close(self.fd)
