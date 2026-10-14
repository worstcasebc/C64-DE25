"""Test für c64_pads.py — läuft am PC, ohne Board:
    python sw/py/test_c64_pads.py

Die Daten stammen vom Board: Auszug aus /proc/bus/input/devices mit
Tastatur und zwei Pads (Modell 081f:e401), und Ereignisse, die beim Drücken
mitgeschrieben wurden.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import c64_pads as pads  # noqa: E402

PROC = """\
I: Bus=0003 Vendor=413c Product=2110 Version=0110
N: Name="Dell Dell Wired Multimedia Keyboard"
P: Phys=usb-10b00000.usb-1.3.4/input0
H: Handlers=sysrq kbd leds event0
B: EV=120013
B: KEY=1000000000007 ff9f207ac14057ff febeffdfffefffff fffffffffffffffe

I: Bus=0003 Vendor=413c Product=2110 Version=0110
N: Name="Dell Dell Wired Multimedia Keyboard Mouse"
P: Phys=usb-10b00000.usb-1.3.4/input1
H: Handlers=event1
B: EV=17
B: KEY=70000 0 0 0 0
B: REL=903

I: Bus=0003 Vendor=081f Product=e401 Version=0110
N: Name="USB gamepad           "
P: Phys=usb-10b00000.usb-1.3.2/input0
H: Handlers=event5
B: EV=1b
B: KEY=3ff00000000 0 0 0 0
B: ABS=3

I: Bus=0003 Vendor=081f Product=e401 Version=0110
N: Name="USB gamepad           "
P: Phys=usb-10b00000.usb-1.3.1/input0
H: Handlers=event4
B: EV=1b
B: KEY=3ff00000000 0 0 0 0
B: ABS=3
"""

errors = 0


def check(what, got, expected):
    global errors
    if got != expected:
        print(f"FAIL: {what}: {got!r}, erwartet {expected!r}")
        errors += 1


# 1. Nur die Pads werden gefunden (nicht die Maus der Tastatur mit
#    Maustasten 0x110..0x112), sortiert nach USB-Anschluss.
found = pads.parse_pads(PROC)
check("gefundene Pads", [(p, d) for p, d, _ in found],
      [("usb-10b00000.usb-1.3.1/input0", "/dev/input/event4"),
       ("usb-10b00000.usb-1.3.2/input0", "/dev/input/event5")])
check("Name ohne Leerzeichen am Ende", found[0][2], "USB gamepad")

# 2. Steuerkreuz und Knöpfe wie mitgeschrieben (Bereich 0..255, Mitte 127).
pad = pads.Pad({pads.ABS_X: (127, 0, 255), pads.ABS_Y: (127, 0, 255)})
check("Ruhe", pad.bits(), 0)
steps = [  # (Art, Code, Wert, erwartete Bits danach)
    (3, 1, 0, pads.UP), (3, 1, 127, 0),
    (3, 0, 0, pads.LEFT), (3, 0, 127, 0),
    (3, 0, 255, pads.RIGHT), (3, 0, 127, 0),
    (3, 1, 255, pads.DOWN), (3, 1, 127, 0),
    (3, 1, 0, pads.UP), (3, 0, 255, pads.UP | pads.RIGHT),          # Diagonale
    (1, 0x120, 1, pads.UP | pads.RIGHT | pads.FIRE),
    (1, 0x123, 1, pads.UP | pads.RIGHT | pads.FIRE),                # zwei Feuerknöpfe
    (1, 0x120, 0, pads.UP | pads.RIGHT | pads.FIRE),                # einer noch unten
    (1, 0x123, 0, pads.UP | pads.RIGHT),
    (3, 0, 127, pads.UP), (3, 1, 127, 0),
    (1, 0x128, 1, 0), (1, 0x129, 1, 0),                             # Select/Start: kein Feuer
    (3, 0, 70, 0), (3, 0, 63, pads.LEFT),                           # Grenze: ein Viertel
]
for kind, code, value, expected in steps:
    pad.event(kind, code, value)
    check(f"nach Ereignis {kind}/{code:#x}={value}", pad.bits(), expected)
    if (kind, code) == (1, 0x129) and value:
        # 3. Select und Start sind gerade beide unten: C= und RUN/STOP
        check("Select+Start als Tasten", pad.keys(), {29, 1})
        pad.event(1, 0x128, 0)
        check("nur Start", pad.keys(), {1})
        pad.event(1, 0x129, 0)
        check("losgelassen", pad.keys(), set())

# 4. Startwert kommt von Linux: ein Pad, dessen Kreuz beim Öffnen schon
#    gedrückt ist, meldet das sofort.
check("Startwert", pads.Pad({pads.ABS_X: (0, 0, 255), pads.ABS_Y: (127, 0, 255)}).bits(), pads.LEFT)

if errors:
    print(f"FAIL: test_c64_pads ({errors} Fehler)")
    sys.exit(1)
print("PASS: test_c64_pads")
