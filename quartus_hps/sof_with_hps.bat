@echo off
rem Fuegt den Bootloader des HPS in die .sof ein (siehe README.md).
cd /d "%~dp0"
"%QUARTUS_ROOTDIR%\bin64\quartus_pfg" -c output_files\de25_nano_c64_hps.sof output_files\de25_nano_c64_hps_boot.sof -o hps_path=software\u-boot\spl\u-boot-spl-dtb.hex
pause
