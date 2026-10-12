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
   von 25.1.1 auf 26.1).
4. Die Bridges `c64_bridge` und `disk_bridge` von Hand ergänzen, siehe
   nächster Abschnitt. Ohne sie fehlen dem System die Anschlüsse `c64_m0_*`
   und `disk_m0_*`, die das Top-Level erwartet.

## Eigene Änderung am System: Bridges `c64_bridge` und `disk_bridge`

Die Register für den C64 (`rtl/io/hps_byte_port.v`) und für die Diskette
(`rtl/drive/hps_disk_port.v`) stecken nicht im Platform-Designer-System,
sondern im Top-Level. Dafür werden zwei Stücke des Avalon-Busses aus dem
System herausgeführt — wie Steckdosen in der Hauswand, an die außen eigene
Geräte kommen. Jede Steckdose ist eine *Avalon Memory Mapped Pipeline Bridge*.

| Bridge        | bedient         | Adressbreite | Basis an `pb_cpu_0.m0` | Export    |
|---------------|-----------------|--------------|------------------------|-----------|
| `c64_bridge`  | `hps_byte_port` | 4            | `0x0001_0100`          | `c64_m0`  |
| `disk_bridge` | `hps_disk_port` | 14           | `0x0001_4000`          | `disk_m0` |

Die Schritte im Platform Designer stehen Klick für Klick in
[INSTALL.md](../INSTALL.md), Abschnitt C4, zusammen mit der Reihenfolge aller
übrigen Bau- und Einrichtungsschritte.

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
| `0x2001_0100` | `DATA`       | `hps_byte_port`: Schreiben schickt Bit 7..0 als Byte an den C64; wird ignoriert, solange belegt |
| `0x2001_0104` | `STATUS`     | `hps_byte_port`: Bit 0 = 1, solange das letzte Byte unterwegs ist (nur lesen); Bit 1 = 1: Taste RESTORE gedrückt (lesen und schreiben) |
| `0x2001_0108` | `KEYS_LO`    | `hps_byte_port`: Tasten 31..0 im Gitter des C64, 1 = gedrückt (Nummern wie in `rtl/io/key_matrix.v`) |
| `0x2001_010C` | `KEYS_HI`    | `hps_byte_port`: Tasten 63..32 |
| `0x2001_4000` | `REQUEST`    | `hps_disk_port`: Anforderung des Laufwerks — Bit 0 lesen, Bit 1 schreiben, Bit 13..8 Anzahl Blöcke − 1, Bit 31..16 erster Block |
| `0x2001_4004` | `CONTROL`    | `hps_disk_port`: schreiben 1 = geliefert; lesen Bit 0 = beschäftigt |
| `0x2001_4008` | `MOUNT`      | `hps_disk_port`: Bit 0 Diskette vorhanden, Bit 1 Schreibschutz, Bit 2 Format (0 = `.D64`, 1 = `.G64`) |
| `0x2001_5000` | OSD sichtbar | `video_osd`: Bit 0 = 1 zeigt das Menüfenster, nur schreiben |
| `0x2001_5800` | OSD Text     | `video_osd`: 512 Worte, je ein Zeichen (Bit 7..0, Bildschirmcode des C64, ab 128 invers), 32 Spalten × 16 Zeilen, nur schreiben |
| `0x2001_6000` | Puffer       | `hps_disk_port`: 8192 Bytes für die gelieferten Blöcke, nur schreiben |

`sw/py/c64_disk.py <Abbild>` legt eine `.D64` oder `.G64` in das Laufwerk
1541 ein und bedient dessen Anforderungen. Auf dem Board bestätigt mit einer
`.D64`: Verzeichnis (`LOAD "$",8`), und ein Spiel lädt und läuft. Noch nicht
ausprobiert ist `.G64`; Schreiben auf die Diskette ist nicht umgesetzt, die
Diskette wird mit Schreibschutz eingelegt. Ohne eingelegte Diskette bleibt
das Laufwerk im Reset.

`sw/py/c64d.py` fasst Tastatur, Laufwerk und ein Menü zusammen: F12 blendet
ein Fenster über das Bild (`rtl/video/video_osd.v`), in dem man eine Diskette
oder ein Programm vom USB-Stick (FAT32) wählt. Auf dem Board bestätigt: Menü,
Einlegen einer `.D64` vom Stick, Laden eines Spiels über mehrere Spuren,
Laden eines `.PRG`. Er ersetzt die beiden einzelnen Skripte unten, die weiter
für sich benutzbar bleiben — aber nie gleichzeitig mit dem Dienst; die
Skripte prüfen das selbst und brechen sonst ab.

`sw/py/c64_keys.py` liest eine USB-Tastatur unter Linux und schreibt den
Zustand nach `KEYS_LO` und `KEYS_HI` (auf dem Board bestätigt: Die Tastatur
am USB-Anschluss des HPS wird erkannt, die Tasten kommen im C64 an). Die
Belegung steht im Kopf des Skripts.

Der Dienst `sw/py/c64-keys.service` startet das Skript beim Booten
(Einrichtung steht in der Datei). Auf dem Board bestätigt: Nach einem
Neustart geht die Tastatur ohne Anmeldung, und RESTORE (Bild auf, `STATUS`
Bit 1) wirkt zusammen mit RUN/STOP (Esc).

Die Bytes an `DATA` haben dieselbe Bedeutung wie am UART vom PC: Tastendrücke
und Ladeblöcke. `sw/py/c64_hps.py` schickt sie von Linux aus. Auf dem Board
bestätigt: Tippen (`--type "PRINT 1+1"`) und Laden eines kleinen
BASIC-Programms (`--load demo.prg --run`, 47 Bytes). Ein großes Programm ist
über diesen Weg noch nicht geladen worden.

`c64_hps.py` und `c64_blocks.py` müssen dazu auf dem Board im selben
Verzeichnis liegen. Ohne Netzwerk geht das über die Konsole: Textdateien mit
`cat > datei` einfügen (Strg+D beendet), Binärdateien als Base64 mit
`base64 -d > datei`; danach mit `md5sum` vergleichen.

Register von Linux aus schreiben (auf dem Board bestätigt, `LEDR[3:1]` an).
`devmem2` fehlt auf Terasics Image, deshalb über Python und `/dev/mem`:

```
sudo python3 -c "import mmap,os,struct; f=os.open('/dev/mem',os.O_RDWR|os.O_SYNC); m=mmap.mmap(f,4096,offset=0x20010000); m[0x80:0x84]=struct.pack('<I',7)"
```

Linux-Anmeldung auf Terasics SD-Karte: `terasic` / `123`, Konsole am HPS-UART
(115200 Baud 8N1).
