# CLAUDE.md — C64-Nachbau auf dem Terasic DE25-Nano

## Projektziel

Schrittweiser Nachbau eines Commodore 64 auf dem DE25-Nano, angelehnt an die
MiSTer-Architektur: Der FPGA bildet die C64-Hardware zyklengenau nach, das HPS
(ARM/Linux) übernimmt Service-Aufgaben (Menü, Laden von .PRG/.D64, Konfiguration).
Das Projekt ist bewusst als Lernpfad aufgebaut — jeder Meilenstein liefert ein
lauffähiges, testbares System.

## Nutzerprofil (bitte beachten)

- Antworten auf **Deutsch**, kurz und präzise. Keine Fakten erfinden — bei
  Unsicherheit (z. B. Pin-Namen, Agilex-5-Primitives) nachschlagen oder nachfragen.
- Etwas Verilog-Erfahrung vorhanden, kein Experte. Neue Konzepte gern mit
  **Analogien** erklären. Hauptsprache sonst: Python.
- Klärende Fragen stellen, bevor umfangreiche Änderungen gemacht werden.

## Hardware

- **Board:** Terasic DE25-Nano
- **FPGA:** Intel Agilex 5 E-Series SoC (A5EB013BB23BE4SCS laut Terasic golden_top; das User Manual nennt
  noch …E4SR1; ca. 130k LE)
- **HPS:** Arm Cortex 2× A76 + 2× A55, 1 GB LPDDR4 (mit FPGA geteilt)
- **FPGA-Speicher:** 1 GB LPDDR4 (32 bit) + 128 MB SDRAM (16 bit)
- **Video:** HDMI 2.0 (bis 1080p)
- **Sonstiges:** 2× 40-Pin-GPIO-Header, MIPI-Anschluss (2 Lanes), GbE, USB 2.0
  Host (Type-C), UART-über-USB, microSD am HPS, 2 FPGA-Taster (KEY0/KEY1, weitere Taster sind HPS-Resets),
  4 Schalter, 8 LEDs (low-aktiv),
  ADC-Header, QSPI-Flash, Onboard USB-Blaster III
- **Zubehör:** Terasic D8M-Kameramodul, HDMI-Display, Breadboard, Sensoren

## Toolchain

- **Synthese:** Quartus Prime **Pro** (Agilex 5 wird nur von Pro unterstützt),
  installiert auf dem Windows-Rechner des Nutzers. Claude Code läuft ggf. in
  einer anderen Umgebung — Synthese/Programmierung macht der Nutzer selbst;
  Claude bereitet .qsf/.sdc/RTL vor und erklärt die Schritte.
- **Simulation:** Questa (Quartus-Bundle) oder bevorzugt **Icarus Verilog /
  Verilator + GTKWave** für schnelle, skriptbare Tests. Testbenches sind Pflicht
  für jedes neue Modul.
- **6502-Assembler:** ca65 (cc65-Suite) oder ACME. Build per Makefile/Python-
  Skript: .s → .bin → .hex/.mif für die Block-RAM-Initialisierung.
- **Python** für alle Hilfsskripte (ROM-Konvertierung, Testdaten, Bildvergleich).

## Meilensteine (Reihenfolge einhalten)

1. **Fundament:** LEDs/Taster, PLL, Pin-Constraints, Signal Tap kennenlernen.
2. **CPU läuft:** 6502-Softcore (z. B. Arlet Ottens, Verilog) + Block-RAM mit
   Assembler-Programm + UART-Textausgabe.
3. **C64-Speicherkarte:** Address-Decoder ($0000–$FFFF), Banking über $01,
   ROM-Einbindung (KERNAL/BASIC/Char-ROM als BRAM), I/O-Fenster $D000–$DFFF.
4. **Textmodus-Video:** Screen-RAM + Character-ROM → HDMI. Ziel: BASIC-
   Startbildschirm sichtbar.
5. **Echter VIC-II:** Portierung FPGA64/MiSTer-VIC-II (Sprites, Badlines,
   Rasterinterrupts).
6. **SID + CIAs:** Sound, Timer, Tastatur (PS/2 am GPIO oder USB über HPS), IRQ/NMI.
7. **HPS-Integration:** Linux auf ARM, Dateibrowser/Menü, .PRG/.D64-Loader,
   Register-Schnittstelle FPGA↔HPS (Lightweight Bridge, memory-mapped).

Paralleler Nebenstrang (unabhängig): D8M-Kamera → Bildverarbeitung → HDMI.
Der HDMI-Ausgabepfad wird zwischen beiden Projekten wiederverwendet.

## Repository-Struktur

```
rtl/            Verilog-Module (eine Datei pro Modul, Modulname = Dateiname)
  cpu/          6502-Core (Fremdcode unverändert in rtl/cpu/vendor/)
  video/        Video-Timing, Textmodus, später VIC-II
  mem/          Address-Decoder, BRAM-Wrapper, ROM-Interfaces
  io/           UART, PS/2, Debug
tb/             Testbenches (tb_<modul>.v) + Simulations-Skripte
sw/asm/         6502-Assembler-Quellen + Makefile
sw/py/          Python-Hilfsskripte (ROM→.mif, Tests)
quartus/        Projektdateien (.qpf/.qsf/.sdc), platform designer
roms/           NICHT einchecken (Urheberrecht) — nur .gitignore + README
docs/           Notizen, Entscheidungen, Pinbelegungen
```

## Konventionen

- **Verilog-2001/SystemVerilog**, synchrone Designs, ein Takt pro Domäne,
  Taktdomänen-Übergänge nur über dokumentierte Synchronizer/FIFOs.
- Signalnamen: `snake_case`; Suffixe `_n` (aktiv low), `_q` (Register),
  Taktnamen `clk_<mhz>` o. ä. Reset: synchron, aktiv high (`rst`).
- Jedes Modul: kurzer Header-Kommentar (Zweck, Takt, Schnittstelle) und eine
  Testbench, bevor es ins Top-Level integriert wird.
- Kleine, nachvollziehbare Schritte: lieber ein Modul pro Commit als Big Bang.
- Fremd-Cores (6502, später FPGA64) unverändert unter `vendor/` ablegen,
  Anpassungen nur über Wrapper — erleichtert Updates und macht Lernen sichtbar.

## Rechtliches / ROMs

Original-KERNAL/BASIC/Char-ROMs sind urheberrechtlich geschützt und werden
nicht ins Repo aufgenommen. Alternativen: eigene Test-ROMs in Assembler oder
freie Ersatz-ROMs (OpenROMs). Der Nutzer legt eigene ROM-Dateien lokal in
`roms/` ab; Skripte erwarten sie dort.

## Arbeitsweise für Claude Code

- Vor größeren Design-Entscheidungen (Busbreiten, Taktkonzept, Framebuffer vs.
  Streaming) kurz Optionen mit Trade-offs nennen und nachfragen.
- Bei jedem neuen Modul: erst Testbench-Plan, dann RTL, dann Simulation
  (Icarus/Verilator), erst danach Quartus-Integration vorschlagen.
- Timing-/Syntheseprobleme: konkrete .sdc-Vorschläge machen, aber erklären, warum.
- Keine erfundenen Pin-Namen oder Agilex-Primitives — wenn das Pin-Dokument
  (DE25-Nano User Manual / System Builder) nicht vorliegt, danach fragen.
- Lernziel vor Tempo: Erklärungen zum „Warum" gehören zu jeder Lösung dazu.
