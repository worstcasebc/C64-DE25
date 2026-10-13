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
subst Q: <Pfad zum Repository>
```

Danach in Quartus `Q:\quartus_hps\de25_nano_c64_hps.qpf` öffnen. `subst` gilt
bis zum nächsten Neustart und muss dann neu gesetzt werden.

## Laden

Die `.sof` aus dem Bau enthält den Bootloader des HPS noch nicht.
`sof_with_hps.bat` fügt ihn ein und erzeugt
`output_files\de25_nano_c64_hps_boot.sof`. Diese Datei per JTAG laden (SW5 im
JTAG-Modus); das QSPI-Flash bleibt unberührt.

Soll das Design nach dem Einschalten von selbst starten, kommt es ins
QSPI-Flash: `sof_to_jic.bat` macht aus der `_boot.sof` eine `.jic`,
`flash_program.bat` schreibt sie (SW5 im AS-Modus). Die Schritte stehen in
[INSTALL.md](../INSTALL.md), Abschnitt E. Auf dem Board bestätigt: Es startet
nach dem Einschalten von selbst.

## Register an der Brücke (Lightweight HPS-to-FPGA)

Basis aus Sicht von Linux: `0x2000_0000` (auf dem Board bestätigt).

| Adresse       | Register     | Anschluss im Top-Level            |
|---------------|--------------|-----------------------------------|
| `0x2001_0000` | `sysid`      | Kennung des Systems               |
| `0x2001_0060` | `button_pio` | nicht angeschlossen (liest `0xF`) |
| `0x2001_0070` | `dipsw_pio`  | nicht angeschlossen (liest `0`)   |
| `0x2001_0080` | `led_pio`    | 3 Bit, nicht mehr an den LEDs angeschlossen |
| `0x2001_0100` | `DATA`       | `hps_byte_port`: Schreiben schickt Bit 7..0 als Byte an den C64; wird ignoriert, solange belegt |
| `0x2001_0104` | `STATUS`     | `hps_byte_port`: Bit 0 = 1, solange das letzte Byte unterwegs ist (nur lesen); Bit 1 = 1: Taste RESTORE gedrückt; Bit 2 = 1: Reset des C64, solange gesetzt; Bit 12..8 = Joystick an Port 1, Bit 20..16 = Joystick an Port 2, je hoch, runter, links, rechts, Feuer (alle lesen und schreiben, jedes Byte einzeln schreibbar) |
| `0x2001_0108` | `KEYS_LO`    | `hps_byte_port`: Tasten 31..0 im Gitter des C64, 1 = gedrückt (Nummern wie in `rtl/io/key_matrix.v`) |
| `0x2001_010C` | `KEYS_HI`    | `hps_byte_port`: Tasten 63..32 |
| `0x2001_4000` | `REQUEST`    | `hps_disk_port`: Bit 0 = Laufwerk will lesen, Bit 1 = eine geschriebene Spur liegt zum Abholen im Puffer, Bit 13..8 Anzahl Blöcke − 1, Bit 31..16 erster Block |
| `0x2001_4004` | `CONTROL`    | `hps_disk_port`: schreiben 1 = geliefert bzw. abgeholt; lesen Bit 0 = beschäftigt |
| `0x2001_400C` | `LEDS`       | `hps_status_led`: jedes Schreiben ist ein Lebenszeichen des Dienstes (bleibt es 3 s aus, blinkt `LEDR[0]` schnell); Bit 0 = Problem (`LEDR[0]` blinkt langsam statt zu leuchten), Bit 1 = `LEDR[2]` (ungespeicherte Änderungen); nur schreiben |
| `0x2001_4008` | `MOUNT`      | `hps_disk_port`: Bit 0 Diskette vorhanden, Bit 1 Schreibschutz, Bit 2 Format (0 = `.D64`, 1 = `.G64`), Bit 3 Laufwerk eingeschaltet (sonst im Reset) |
| `0x2001_5000` | OSD sichtbar | `video_osd`: Bit 0 = 1 zeigt das Menüfenster, nur schreiben |
| `0x2001_5800` | OSD Text     | `video_osd`: 512 Worte, je ein Zeichen (Bit 7..0, Bildschirmcode des C64, ab 128 invers), 32 Spalten × 16 Zeilen, nur schreiben |
| `0x2001_6000` | Puffer       | `hps_disk_port`: 8192 Bytes; schreiben füllt die Lieferung ans Laufwerk, lesen liefert die geschriebene Spur (zwei getrennte Speicher) |

`sw/py/c64_disk.py <Abbild>` legt eine `.D64` oder `.G64` in das Laufwerk
1541 ein und bedient dessen Anforderungen. Auf dem Board bestätigt mit einer
`.D64`: Verzeichnis (`LOAD "$",8`), und ein Spiel lädt und läuft. Noch nicht
ausprobiert ist `.G64`; Schreiben auf die Diskette ist nicht umgesetzt, die
Diskette wird mit Schreibschutz eingelegt. Das Laufwerk ist eingeschaltet,
solange ein Lieferant läuft (`MOUNT` Bit 3), auch ohne Diskette; beim
Wechsel der Diskette bleibt es an, damit ein Schnelllader, den ein Spiel in
das Laufwerk geladen hat, erhalten bleibt (auf dem Board bestätigt mit einem
Spiel auf zwei Disketten, Herausnehmen und Einlegen).

`sw/py/c64d.py` fasst Tastatur, Laufwerk und ein Menü zusammen: F12 blendet
ein Fenster über das Bild (`rtl/video/video_osd.v`), in dem man eine Diskette
oder ein Programm vom USB-Stick (FAT32) wählt. Auf dem Board bestätigt: Menü,
Einlegen einer `.D64` vom Stick, Laden eines Spiels über mehrere Spuren,
Laden eines `.PRG`. Er ersetzt die beiden einzelnen Skripte unten, die weiter
für sich benutzbar bleiben — aber nie gleichzeitig mit dem Dienst; die
Skripte prüfen das selbst und brechen sonst ab.

Im Dienst ist eine `.D64` beschreibbar: Was der C64 schreibt, steht eine
Sekunde später in der Datei; vor der ersten Änderung entsteht einmalig eine
Sicherung `<name>.bak`. Das Menü hat außerdem einen Eintrag, der den C64
zurücksetzt. Auf dem Board bestätigt: `SAVE` eines BASIC-Programms, Laden
desselben Programms nach einem Reset, die Sicherung auf dem Stick und der
Reset aus dem Menü.

Der Ziffernblock der Tastatur ist im Dienst ein Joystick (8/2/4/6, Ecken
diagonal, 0 und Strg rechts Feuer); der Port wird im Menü gewählt. Auf dem
Board bestätigt: ein Spiel lässt sich damit steuern.

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

Ein Register von Linux aus von Hand schreiben: `devmem2` fehlt auf Terasics
Image, deshalb über Python und `/dev/mem`. Das Beispiel schreibt 0 in das
Register `LEDS` und ist damit ein einzelnes Lebenszeichen — `LEDR[0]`
leuchtet danach drei Sekunden lang, wenn der Dienst nicht läuft:

```
sudo python3 -c "import mmap,os,struct; f=os.open('/dev/mem',os.O_RDWR|os.O_SYNC); m=memoryview(mmap.mmap(f,4096,offset=0x20014000)).cast('I'); m[3]=0"
```

Die LEDs des Boards (alle mit HPS, auf dem Board bestätigt): `LEDR[0]`
Zustand des Dienstes, `LEDR[1]` Leuchte des Laufwerks, `LEDR[2]`
ungespeicherte Änderungen an der Diskette.

Linux-Anmeldung auf Terasics SD-Karte: `terasic` / `123`, Konsole am HPS-UART
(115200 Baud 8N1).
