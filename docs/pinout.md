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

## FPGA-UART über den Onboard-FTDI

Quelle: `golden_top.qsf` und das Demo `Demonstration/FPGA/UART` aus Terasics
Ressourcen-Paket (das User Manual listet nur die HPS-UART-Pins). Der UART
läuft über den FTDI-Chip am selben Type-C-Kabel wie der USB-Blaster und
erscheint am PC als „USB Serial Port (COMx)“; das Board meldet zwei solche
Ports. Am Entwicklungsrechner ist der FPGA-UART COM12 (per Empfangstest
bestätigt), COM11 demnach der HPS-UART. 115200 Baud, 8N1.

Für JTAG-Programmierung muss SW5 im JTAG-Modus stehen (SW5.1–5.3 OFF, nur
stromlos umstellen). In der Werksstellung „AS Fast“ scheiterte das Laden
wiederholt mit „Synchronization failed“.

| Signal       | Pin      | Richtung (FPGA) | I/O-Standard |
|--------------|----------|-----------------|--------------|
| FPGA_UART_TX | PIN_CJ1  | Ausgang         | 3.3-V LVCMOS |
| FPGA_UART_RX | PIN_BR19 | Eingang (noch unbenutzt) | 3.3-V LVCMOS |

## Hinweis zum I/O-Standard

Das Handbuch nennt nur „1.1V“. Terasics `golden_top.qsf` schreibt `"1.1-V"`;
unsere .qsf nutzt die gleichwertige Schreibweise `"1.1 V"` (Quartus meldet
sie im Report als „1.1-V“). `"1.1-V LVCMOS"` lehnt der Fitter ab (Error 11989).

Abgleich mit `golden_top.qsf` (liegt lokal unter
`..\Material\ResPack\Demonstration\FPGA\Golden_top`): Pins und I/O-Standards
für Takt, Taster, Schalter und LEDs stimmen überein. Terasic setzt dort
ebenfalls keine Treiberstärke/Slew-Rate/Terminierung — die Quartus-Warnung
25315 ist also auch im Referenzprojekt vorhanden. Die LEDs heißen dort `LED`
statt `LEDR` (Handbuch).

**Device-Bezeichnung:** Das Handbuch (auch revB) nennt `A5EB013BB23BE4SR1`,
12 von 13 Terasic-Demos dagegen `A5EB013BB23BE4SCS`. Das Projekt nutzt seit
Meilenstein 2 `…E4SCS`: Der Bitstream läuft auf dem Board (UART-Empfangstest),
und Quartus 26.1 hat dafür endgültige statt vorläufiger Timing-Daten. Mit
`…E4SR1` lief das Design ebenfalls.
