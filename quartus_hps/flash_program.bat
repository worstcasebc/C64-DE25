@echo off
rem Schreibt die .jic ueber JTAG ins QSPI-Flash des Boards (siehe INSTALL.md).
rem Achtung: ueberschreibt, was im Flash steht -- ab Werk Terasics Startdesign.
rem Das laesst sich mit Terasics golden_top_hps.jic wiederherstellen.
rem Voraussetzung: SW5 im AS-Modus (SW5.1 OFF, SW5.2 und SW5.3 ON), Board an,
rem USB-Blaster verbunden. "-c 1" ist das erste Kabel; "quartus_pgm -l" listet sie.
rem Aufruf wie in Terasics flash_program.bat: p = schreiben, v = pruefen,
rem i = der Flash-Lader wird dafuer voruebergehend ins FPGA geladen.
cd /d "%~dp0"
"%QUARTUS_ROOTDIR%\bin64\quartus_pgm" -m jtag -c 1 -o "pvi;output_files\de25_nano_c64_hps.jic"
pause
