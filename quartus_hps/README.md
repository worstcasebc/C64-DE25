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
4. Die Bridge `c64_bridge` von Hand ergänzen, siehe nächster Abschnitt. Ohne
   sie fehlen dem System die Anschlüsse `c64_m0_*`, die das Top-Level
   erwartet.

## Eigene Änderung am System: Bridge `c64_bridge`

Das Register für die Bytes an den C64 (`rtl/io/hps_byte_port.v`) steckt nicht
im Platform-Designer-System, sondern im Top-Level. Dafür wird ein Stück des
Avalon-Busses aus dem System herausgeführt — wie eine Steckdose in der
Hauswand, an die außen ein eigenes Gerät kommt. Die Steckdose ist eine zweite
*Avalon Memory Mapped Pipeline Bridge*.

In Platform Designer (*Tools → Platform Designer*, `qsys_top.qsys` öffnen):

1. In das Untersystem `subsys_periph` (`peripheral_subsys.qsys`) wechseln.
2. Aus dem IP Catalog *Avalon Memory Mapped Pipeline Bridge IP* hinzufügen,
   Name `c64_bridge`. Einstellungen:
   - *Data width* 32, *Symbol width* 8, *Address units* SYMBOLS
   - *Use automatically-determined address width* aus, *Address width* 4
   - *Maximum burst size (words)* 1
   - alles andere wie vorgegeben
3. Verbinden:
   - `c64_bridge.clk` mit `periph_clk.out_clk`
   - `c64_bridge.reset` mit `periph_rst_in.out_reset`
   - `c64_bridge.s0` mit `pb_cpu_0.m0`, Basisadresse `0x0001_0100`
4. `c64_bridge.m0` exportieren, Name `c64_m0`.
5. Zurück in `qsys_top`: Am Untersystem `subsys_periph` gibt es jetzt den
   Anschluss `c64_m0`. Ebenfalls exportieren, Name wieder `c64_m0`.
6. Speichern und *Generate HDL*. In `qsys_top/qsys_top_inst.v` müssen danach
   zehn Anschlüsse `c64_m0_*` stehen (`address` 4 Bit breit).

Platform Designer legt für die Bridge die Datei
`peripheral_subsys/ip/peripheral_subsys/peripheral_subsys_mm_bridge_0.ip` an
(der Dateiname behält den vorgeschlagenen Namen, auch wenn die Bridge im
System `c64_bridge` heißt). Unter diesem Namen steht sie in der `.qsf`.

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
| `0x2001_0104` | `STATUS`     | `hps_byte_port`: Bit 0 = 1, solange das letzte Byte unterwegs ist |
| `0x2001_0108` | `KEYS_LO`    | `hps_byte_port`: Tasten 31..0 im Gitter des C64, 1 = gedrückt (Nummern wie in `rtl/io/key_matrix.v`) |
| `0x2001_010C` | `KEYS_HI`    | `hps_byte_port`: Tasten 63..32 |

`sw/py/c64_keys.py` liest eine USB-Tastatur unter Linux und schreibt den
Zustand nach `KEYS_LO` und `KEYS_HI` (auf dem Board bestätigt: Die Tastatur
am USB-Anschluss des HPS wird erkannt, die Tasten kommen im C64 an). Die
Belegung steht im Kopf des Skripts.

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
