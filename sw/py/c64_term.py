"""Tastatur-Terminal für den C64 auf dem DE25-Nano (Windows).

Aufruf:
    python sw/py/c64_term.py             Port COM12
    python sw/py/c64_term.py COM7        anderer Port

Schickt jeden Tastendruck sofort über den UART ans FPGA (115200 Baud, 8N1),
statt wie viele Terminalprogramme erst die ganze Zeile bei Enter. Das FPGA
tippt die Zeichen auf der C64-Tastatur (rtl/io/ascii_key_typer.v).

    Enter                RETURN
    Rücktaste, Entf      DEL (Zeichen links vom Cursor löschen)
    Esc                  RUN/STOP
    Pfeiltasten          Cursor
    Pos1                 HOME            Einfg    INS
    F1 bis F8            F1 bis F8
    Strg+C               Terminal beenden

Benötigt pyserial:  python -m pip install pyserial
"""
import msvcrt
import sys

try:
    import serial
except ImportError:
    sys.exit("pyserial fehlt. Installieren mit:  python -m pip install pyserial")

BAUD = 115200

# Sondertasten liefert msvcrt als zwei Zeichen: Vorzeichen (\x00 oder \xe0)
# und Tastencode. Rechts steht der Steuercode des C64 (PETSCII), den das
# FPGA versteht.
SPECIAL_KEYS = {
    "H": 0x91,  # Pfeil hoch
    "P": 0x11,  # Pfeil runter
    "K": 0x9D,  # Pfeil links
    "M": 0x1D,  # Pfeil rechts
    "G": 0x13,  # Pos1 -> HOME
    "R": 0x94,  # Einfg -> INS
    "S": 0x14,  # Entf -> DEL
    ";": 0x85,  # F1
    "<": 0x89,  # F2
    "=": 0x86,  # F3
    ">": 0x8A,  # F4
    "?": 0x87,  # F5
    "@": 0x8B,  # F6
    "A": 0x88,  # F7
    "B": 0x8C,  # F8
}


def main() -> int:
    port_name = sys.argv[1] if len(sys.argv) > 1 else "COM12"
    try:
        port = serial.Serial(port_name, BAUD)
    except serial.SerialException as err:
        sys.exit(f"{port_name} lässt sich nicht öffnen (anderes Terminal noch offen?): {err}")

    print(f"Verbunden mit {port_name}. Tippen geht direkt an den C64, Strg+C beendet.")
    with port:
        while True:
            key = msvcrt.getwch()
            if key == "\x03":                   # Strg+C
                return 0
            if key in ("\x00", "\xe0"):         # Sondertaste: zweites Zeichen holen
                code = SPECIAL_KEYS.get(msvcrt.getwch())
            elif ord(key) < 0x80:
                code = ord(key)
            else:
                code = None                     # Umlaute usw. kennt der C64 nicht
            if code is not None:
                port.write(bytes([code]))


if __name__ == "__main__":
    sys.exit(main())
