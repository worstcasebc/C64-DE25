"""Ladeblöcke für rtl/io/prg_loader.v — gemeinsam für PC und HPS.

Eine .PRG-Datei beginnt mit zwei Bytes Ladeadresse, dann folgt das Programm.
Der Lader im FPGA erwartet Blöcke der Form
    $FF, Adresse low, Adresse high, Länge low, Länge high, Daten...
und schreibt die Daten am Rechner vorbei direkt ins RAM. Bei BASIC-Programmen
(Ladeadresse $0801) kommt ein zweiter Block dazu, der den Zeiger auf das
Programmende setzt, so wie es der LOAD-Befehl täte; danach genügt RUN.

Benutzt von c64_term.py (PC, über den UART) und c64_hps.py (Linux auf dem
Board, über die Brücke).
"""
BASIC_START = 0x0801    # hier beginnen BASIC-Programme
BASIC_END_PTR = 0x002D  # Zeiger des BASIC auf das Programmende (2 Bytes)


def load_block(address: int, data: bytes) -> bytes:
    """Ein Ladeblock für prg_loader: $FF, Adresse, Länge, Daten."""
    if not 0 < len(data) <= 0xFFFF:
        raise ValueError(f"Blocklänge {len(data)} nicht im Bereich 1..65535")
    return bytes([0xFF, address & 0xFF, address >> 8, len(data) & 0xFF, len(data) >> 8]) + data


def prg_to_blocks(prg: bytes) -> bytes:
    """Macht aus dem Inhalt einer .PRG-Datei die Bytes, die ans FPGA gehen."""
    if len(prg) < 3:
        raise ValueError("Datei zu kurz für eine .PRG-Datei")
    address = prg[0] | (prg[1] << 8)
    data = prg[2:]
    end = address + len(data)
    if end > 0x10000:
        raise ValueError(f"Programm reicht über $FFFF hinaus (Ende ${end:X})")
    blocks = load_block(address, data)
    if address == BASIC_START:
        blocks += load_block(BASIC_END_PTR, bytes([end & 0xFF, end >> 8]))
    return blocks
