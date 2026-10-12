# Diskettenlaufwerk 1541 aus MiSTer (Fremdcode, in der Form angepasst)

- Quelle: <https://github.com/MiSTer-devel/C64_MiSTer>, Verzeichnis
  `rtl/iec_drive`
- Stand: Commit `f11608f66bcb2b017680d7c719aa547f537bfd3f` (Mai 2026) — ein
  älterer Stand als bei VIC-II, SID und CIA, siehe unten.
- Dateien: `c1541_multi.sv` (Einstieg), `c1541_drv.sv`, `c1541_logic.sv`
  (CPU, RAM, zwei VIA 6522), `c1541_track.sv` (fordert Spuren an),
  `c1541_gcr.sv` (wandelt `.D64`-Sektoren in das Bitmuster der Diskette und
  zurück), `c1541_direct_gcr.sv` (liest Spuren im Format `.G64`),
  `iecdrv_misc.sv` (Speicher, Synchronizer), `iecdrv_via6522.vhd`, `lfsr.v`
- Die CPU des Laufwerks ist derselbe T65 wie im Rechner
  (`rtl/cpu/vendor/t65`).
- Sprache: SystemVerilog und VHDL. Testbenches mit dem Laufwerk laufen über
  Questa (`tb/tb_drive_1541.v`).
- Angeschlossen wird nicht `c1541_multi` direkt, sondern die Hülle
  `rtl/drive/drive_1541.sv`. Dort stehen auch die Anschlüsse erklärt.

## Warum der ältere Stand

Seit dem 11. Mai 2026 (Commit `a1a560e`) lädt MiSTer die ganze Diskette vorab
in den Hauptspeicher des HPS, und das Laufwerk holt jede Spur von dort
(Anschlüsse `DDRAM_*`, 2 MB je Laufwerk). Diesen Speicher gibt es hier nicht,
und im Block-RAM des FPGA ist dafür kein Platz. Der Stand unmittelbar davor
fordert jede Spur blockweise an (`sd_lba`, `sd_rd`, `sd_ack`, `sd_buff_*`);
das lässt sich mit wenigen Registern von Linux aus bedienen. Er enthält die
Verbesserungen von 2025 (Lesen wie im Schaltplan, Drehung der Diskette,
schwache Bits).

Die Hülle `iec_drive.sv` und die 1581 werden nicht benutzt.

## Eigenheiten, die man kennen muss

- **Takt:** `clk` mit einer Freigabe `ce` von 16 MHz. Daraus macht der Core
  den 1-MHz-Takt der Laufwerks-CPU.
- **Anforderung nach dem Reset:** Bei `gcr_mode = 0` (`.D64`) fordert das
  Laufwerk sofort nach dem Reset die Verzeichnisspur an (ab Block 357,
  19 Blöcke), auch ohne Diskette. Solange niemand mit `sd_ack` antwortet,
  bleibt es „beschäftigt": Die Leuchte ist an, und es liest nichts von der
  Diskette. MiSTer hält das Laufwerk deshalb im Reset, bis eine Diskette
  eingelegt ist.
- **Blockgröße:** 256 Bytes. Bei `.D64` ist `sd_lba` die Nummer des ersten
  Sektors der Spur, gezählt über die ganze Diskette; `sd_blk_cnt + 1` ist die
  Zahl der Sektoren der Spur.
- **ROM:** Der Core lädt sein ROM aus einer `.mif`-Datei, deren Pfad im
  Quelltext steht. Er zeigt hier auf `../sw/asm/build/c1541_rom.mif`
  (relativ zum Quartus-Projekt); `sw/py/build_rom.py` erzeugt die Datei aus
  `roms/dos1541-325302-01+901229-05.bin`. In der Simulation wirkt diese
  Angabe nicht; dort lädt die Testbench das ROM selbst.
- **Startwerte:** Einige Register werden nie zurückgesetzt und verlassen sich
  darauf, dass sie im FPGA bei 0 beginnen. In der Simulation braucht es dafür
  die Questa-Schalter `+initreg+0 +initmem+0` (stehen in der Testbench).

## Ausnahme von der Regel „Fremdcode unverändert"

Sechs der neun Dateien sind gegenüber dem Original geändert (`iecdrv_misc.sv`,
`iecdrv_via6522.vhd` und `lfsr.v` nicht). MiSTer baut mit der älteren
Quartus-Standard-Reihe, die über Formfehler hinwegsieht; Quartus Pro und
Questa lehnen das Original ab. Geändert wurde die Form, nicht die Funktion:

- Deklarationen stehen jetzt vor ihrer ersten Verwendung. Dafür sind sie in
  allen sechs Dateien nach oben gerückt; aus `wire x = ...;` weiter unten
  wurde dabei `assign x = ...;`.
- Variablen, die in einem `always`-Block deklariert waren, stehen jetzt im
  Modul. Für die mit Startwert verlangt Questa das; für die übrigen ist es
  nötig, weil `+initreg+0` nur Register des Moduls vorbelegt und das Laufwerk
  in der Simulation sonst nie anläuft.
- `c1541_multi.sv`: Die Konstanten `NDR` und `N` stehen in der
  Parameterliste, weil die Portliste sie braucht. `par_data_o` ist `reg`,
  weil es in einem `always`-Block beschrieben wird.
- `c1541_gcr.sv`: `nibble_out` ist aus demselben Grund `reg` statt `wire`.
- `c1541_direct_gcr.sv`: Zwei Konstanten und eine Tabelle stehen in der
  Reihenfolge, in der sie einander brauchen.

Eine Änderung betrifft nicht die Form: der Pfad der ROM-Datei in
`c1541_multi.sv` (siehe oben).

Alle Änderungen stehen als Unterschied zum Original in `quartus_pro.patch`.

## Lizenz

- `c1541_track.sv`: LGPL, Version 3 oder später (Sorgelig, laut Dateikopf).
- `iecdrv_via6522.vhd`: GPL 3.0 (Gideon Zweijtzer, laut Dateikopf).
- Die übrigen Dateien tragen nur Urhebervermerke (Alexey Melnikov; Dar;
  Mark McDougall; Robin Wünderlich), keinen Lizenzvermerk, und das
  MiSTer-Repository enthält keine Lizenzdatei.

Die Dateien sind deshalb nicht eingecheckt; im Repository steht nur der
Patch mit den Änderungen oben.

Das ROM der 1541 ist urheberrechtlich geschützt und liegt wie die ROMs des
C64 nur lokal in `roms/`.

## Nicht im Repository: mit Skript holen

Aus dem Projektverzeichnis:

```
python sw/py/fetch_mister.py
```

Das Skript lädt die neun Dateien in genau dem Stand oben herunter, wendet
`quartus_pro.patch` an und legt das Ergebnis hier ab (zusammen mit VIC-II,
SID und CIA).
