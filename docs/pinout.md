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
| FPGA_UART_RX | PIN_BR19 | Eingang (Tastatur-Ersatz) | 3.3-V LVCMOS |

## HDMI-Sender

Quelle: `golden_top.qsf` und das Demo `Demonstration/FPGA/HDMI_TX`. Das FPGA
erzeugt kein HDMI-Signal selbst, sondern liefert einem Sender-Baustein auf dem
Board paralleles Video: 24 Bit RGB, HS, VS, DE und den Pixeltakt. Der Baustein
muss nach dem Einschalten über I2C konfiguriert werden (Schreibadresse `0x72`,
Registerliste im Demo in `V_HDMI/I2C_HDMI_Config.v`). Farbzuordnung im Demo:
`D[23:16]` = Rot, `D[15:8]` = Grün, `D[7:0]` = Blau.

| Signal       | Pin      | Richtung (FPGA) | I/O-Standard |
|--------------|----------|-----------------|--------------|
| HDMI_TX_CLK  | PIN_DJ24 | Ausgang         | 1.1-V        |
| HDMI_TX_DE   | PIN_CJ2  | Ausgang         | 3.3-V LVCMOS |
| HDMI_TX_HS   | PIN_BR11 | Ausgang         | 3.3-V LVCMOS |
| HDMI_TX_VS   | PIN_BR14 | Ausgang         | 3.3-V LVCMOS |
| HDMI_I2C_SCL | PIN_BT1  | bidirektional   | 3.3-V LVCMOS |
| HDMI_I2C_SDA | PIN_BW2  | bidirektional   | 3.3-V LVCMOS |
| HDMI_TX_INT  | PIN_CF2  | Eingang         | 3.3-V LVCMOS |

Datenleitungen, alle 3.3-V LVCMOS:

| Signal        | Pin      | Signal         | Pin      | Signal         | Pin      |
|---------------|----------|----------------|----------|----------------|----------|
| HDMI_TX_D[0]  | PIN_AV19 | HDMI_TX_D[8]   | PIN_BH11 | HDMI_TX_D[16]  | PIN_BH16 |
| HDMI_TX_D[1]  | PIN_AT11 | HDMI_TX_D[9]   | PIN_BE14 | HDMI_TX_D[17]  | PIN_DA1  |
| HDMI_TX_D[2]  | PIN_BE11 | HDMI_TX_D[10]  | PIN_BE19 | HDMI_TX_D[18]  | PIN_BH19 |
| HDMI_TX_D[3]  | PIN_AV14 | HDMI_TX_D[11]  | PIN_BH14 | HDMI_TX_D[19]  | PIN_CP2  |
| HDMI_TX_D[4]  | PIN_AT19 | HDMI_TX_D[12]  | PIN_BV6  | HDMI_TX_D[20]  | PIN_CM1  |
| HDMI_TX_D[5]  | PIN_AT14 | HDMI_TX_D[13]  | PIN_BJ23 | HDMI_TX_D[21]  | PIN_DA2  |
| HDMI_TX_D[6]  | PIN_AV16 | HDMI_TX_D[14]  | PIN_BV4  | HDMI_TX_D[22]  | PIN_CP1  |
| HDMI_TX_D[7]  | PIN_AV11 | HDMI_TX_D[15]  | PIN_BU23 | HDMI_TX_D[23]  | PIN_CU2  |

**Bildformat** (Monitortest am 11.10.2026): Der VIC-II liefert ein PAL-Bild,
das zeilenverdoppelt als Raster mit 1008 Punkten pro Zeile und 624 Zeilen bei
31,5 MHz ausgegeben wird (31,25 kHz, 50,08 Hz). Mit 720 x 576 sichtbaren
Punkten nimmt der Monitor des Entwicklers das als „720x576, 50 Hz" an; mit
768 x 544 sichtbaren Punkten im selben Raster lehnt er es ab („input timing
not supported"). Der Pixeltakt kommt aus `quartus/ip/pll_c64.ip` (50 MHz ->
2 x 31,5 MHz, 0 und 180 Grad; der verschobene Takt geht an `HDMI_TX_CLK`).

Ton als I2S (alle 3.3-V LVCMOS): HDMI_MCLK PIN_CF1, HDMI_SCLK PIN_BW1,
HDMI_LRCLK PIN_BR6, HDMI_I2S PIN_CB2.

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
