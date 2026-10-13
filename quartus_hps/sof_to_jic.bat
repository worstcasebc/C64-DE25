@echo off
rem Macht aus der .sof mit Bootloader eine .jic fuer das QSPI-Flash (siehe INSTALL.md).
rem Vorher sof_with_hps.bat ausfuehren. Flash-Baustein und Modus wie in Terasics
rem Beispiel GHRD (sof_to_jic.bat): MT25QU128, Active Serial x4.
cd /d "%~dp0"
"%QUARTUS_ROOTDIR%\bin64\quartus_pfg" -c output_files\de25_nano_c64_hps_boot.sof output_files\de25_nano_c64_hps.jic -o device=MT25QU128 -o flash_loader=A5EB013BB23B -o mode=ASX4
pause
