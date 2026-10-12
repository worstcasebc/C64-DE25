# quartus_hps — der C64 zusammen mit dem HPS

Zweites Quartus-Projekt neben `quartus/`. Beide bauen dasselbe Top-Level
`rtl/de25_nano_top.v`; dieses hier setzt zusätzlich das Makro `ENABLE_HPS`.
Dann steckt neben dem C64 das HPS im Design, auf dem Linux läuft.

| Projekt        | Inhalt        | Wozu                                        |
|----------------|---------------|---------------------------------------------|
| `quartus/`     | nur der C64   | schneller Bau, kein Linux nötig              |
| `quartus_hps/` | C64 und HPS   | alles, was Linux braucht (USB-Tastatur usw.) |

## Terasic-Dateien: nicht im Repository, vor dem ersten Bau holen

Das Platform-Designer-System `qsys_top` mit seinen Untersystemen
(`hps_subsys`, `jtag_subsys`, `peripheral_subsys`), die Bausteine unter `ip/`
und `custom_ip/` sowie der Bootloader `software/u-boot/spl/u-boot-spl-dtb.hex`
stammen aus Terasics Beispiel GHRD für das DE25-Nano (erstellt mit Quartus
25.1.1). Terasic erlaubt laut Dateikopf von `golden_top.v` die Nutzung und
Änderung für Terasic-Boards; Weitergabe darüber hinaus ist untersagt. Deshalb
stehen diese Dateien nicht im Repository. Eingecheckt sind hier nur
`de25_nano_c64_hps.qpf`, `de25_nano_c64_hps.qsf`, `sof_with_hps.bat` und diese
README.

So kommen sie her:

1. Terasics Ressourcen-Paket zum DE25-Nano herunterladen (Seite des Boards
   bei terasic.com) und entpacken. Das GHRD liegt darin unter
   `Demonstration/SoC_FPGA/GHRD`.
2. Aus dem Projektverzeichnis kopieren lassen:

   ```
   python sw/py/fetch_ghrd.py <Pfad zum Paket>\Demonstration\SoC_FPGA\GHRD
   ```

   Das Skript kopiert 30 Dateien: `qsys_top.qsys`, die drei
   `*_subsys/*.qsys`, alle `.ip`-Dateien, `custom_ip/` und den Bootloader.
3. Projekt in Quartus öffnen. Meldet Quartus veraltete Bausteine, einmal
   *Project → Upgrade IP Components* ausführen (für dieses Projekt geschehen
   von 25.1.1 auf 26.1). Sonst ist an den Dateien nichts geändert.

## Bauen: nur über einen kurzen Pfad

Das Repository liegt tief im Dateisystem. Am ursprünglichen Ort bricht
Quartus beim HPS-Design nach etwa 40 Sekunden ab
(`Failed dni::save_checkpoint … manifest.txt was not found on disk`). Über
einen Laufwerksbuchstaben läuft derselbe Bau durch:

```
subst Q: C:\Users\worst\Documents\VSCode-Workspace\Quartus-FPGA\DE25-Nano\MiSTer
```

Danach in Quartus `Q:\quartus_hps\de25_nano_c64_hps.qpf` öffnen. `subst` gilt
bis zum nächsten Neustart und muss dann neu gesetzt werden.

## Laden

Die `.sof` aus dem Bau enthält den Bootloader des HPS noch nicht.
`sof_with_hps.bat` fügt ihn ein und erzeugt
`output_files\de25_nano_c64_hps_boot.sof`. Diese Datei per JTAG laden (SW5 im
JTAG-Modus); das QSPI-Flash bleibt unberührt.

## Register an der Brücke (Lightweight HPS-to-FPGA)

Basis aus Sicht von Linux: `0x2000_0000` (auf dem Board bestätigt).

| Adresse       | Register     | Anschluss im Top-Level            |
|---------------|--------------|-----------------------------------|
| `0x2001_0000` | `sysid`      | Kennung des Systems               |
| `0x2001_0060` | `button_pio` | nicht angeschlossen (liest `0xF`) |
| `0x2001_0070` | `dipsw_pio`  | nicht angeschlossen (liest `0`)   |
| `0x2001_0080` | `led_pio`    | 3 Bit, `LEDR[3:1]`, 1 = an        |

Register von Linux aus schreiben (auf dem Board bestätigt, `LEDR[3:1]` an).
`devmem2` fehlt auf Terasics Image, deshalb über Python und `/dev/mem`:

```
sudo python3 -c "import mmap,os,struct; f=os.open('/dev/mem',os.O_RDWR|os.O_SYNC); m=mmap.mmap(f,4096,offset=0x20010000); m[0x80:0x84]=struct.pack('<I',7)"
```

Linux-Anmeldung auf Terasics SD-Karte: `terasic` / `123`, Konsole am HPS-UART
(115200 Baud 8N1).
