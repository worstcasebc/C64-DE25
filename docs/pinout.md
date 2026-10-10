# Pinbelegung DE25-Nano

Quelle: *DE25-Nano User Manual*, Terasic, Stand 05.09.2025
(<https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/7704/P0804.pdf>),
Tabellen 3-6, 3-8, 3-9, 3-10. Nur Pins, die im Projekt schon benutzt werden —
weitere (GPIO, HDMI, SDRAM …) kommen mit dem jeweiligen Meilenstein dazu.

## Takte (Tabelle 3-6)

| Signal    | Pin      | Frequenz | I/O-Standard | Verwendung        |
|-----------|----------|----------|--------------|-------------------|
| CLOCK0_50 | PIN_DJ35 | 50 MHz   | 1.1 V        | Systemtakt clk_50 |
| CLOCK1_50 | PIN_V16  | 50 MHz   | 3.3-V LVCMOS | frei              |
| CLOCK2_50 | PIN_BF23 | 50 MHz   | 3.3-V LVCMOS | frei              |

## Taster (Tabelle 3-9)

Low-aktiv (gedrückt = 0), per Schmitt-Trigger auf dem Board entprellt.

| Signal | Pin     | I/O-Standard | Verwendung |
|--------|---------|--------------|------------|
| KEY[0] | PIN_C8  | 3.3-V LVCMOS | Reset      |
| KEY[1] | PIN_C11 | 3.3-V LVCMOS | frei       |

Das Board hat nur **zwei** FPGA-Taster. Die weiteren Taster sind Reset-Taster
des HPS (z. B. KEY3 = `KEY_COLD_RESET_N`) und für FPGA-Logik nicht nutzbar.

## Schiebeschalter (Tabelle 3-8)

Oben = 1, unten (zur Platinenkante) = 0, **nicht** entprellt.

| Signal | Pin      | I/O-Standard |
|--------|----------|--------------|
| SW[0]  | PIN_DK24 | 1.1 V        |
| SW[1]  | PIN_DD24 | 1.1 V        |
| SW[2]  | PIN_DD27 | 1.1 V        |
| SW[3]  | PIN_DF27 | 1.1 V        |

## LEDs (Tabelle 3-10)

Low-aktiv (Pin = 0 → LED leuchtet).

| Signal  | Pin      | I/O-Standard |
|---------|----------|--------------|
| LEDR[0] | PIN_DF35 | 1.1 V        |
| LEDR[1] | PIN_DJ32 | 1.1 V        |
| LEDR[2] | PIN_DN22 | 1.1 V        |
| LEDR[3] | PIN_DP23 | 1.1 V        |
| LEDR[4] | PIN_DN25 | 1.1 V        |
| LEDR[5] | PIN_DP25 | 1.1 V        |
| LEDR[6] | PIN_DJ27 | 1.1 V        |
| LEDR[7] | PIN_DP30 | 1.1 V        |

## Hinweis zum I/O-Standard

Das Handbuch nennt nur „1.1V“. In der .qsf heißt der Standard `"1.1 V"`
(mit Leerzeichen) — `"1.1-V LVCMOS"` lehnt der Fitter von Quartus Pro 26.1 ab
(Error 11989). Der Name ist per Komplettlauf geprüft, stammt aber nicht
wörtlich aus dem Handbuch. Maßgeblich bleibt das `golden_top`-Projekt der
Terasic-System-CD (`Demonstration/FPGA/golden_top`) — bei Gelegenheit damit
abgleichen, auch wegen Treiberstärke/Slew-Rate (Quartus-Warnung 25315).
