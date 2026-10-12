# SID aus MiSTer (Fremdcode, in der Form angepasst)

- Quelle: <https://github.com/MiSTer-devel/C64_MiSTer>, Verzeichnis `rtl/sid`
- Stand: Commit `fe6dfe53c99122e5a088691f2d358d6caba61de1` (2026-09-06)
- Dateien: `sid_top.sv` (Einstieg), `sid_voice.sv`, `sid_envelope.sv`,
  `sid_filter.sv`, `sid_dac.sv`, `sid_tables.sv`
- Sprache: SystemVerilog. Icarus läuft hier mit Verilog-2005 und liest diese
  Dateien nicht; Testbenches mit SID laufen über Questa (`tb/tb_sid_tone.v`).
- Der Kern braucht mindestens 16 Systemtakte pro CPU-Takt, um ein
  Audiosample zu berechnen. Auf dem Board sind es 32. In der schnellen
  Simulation (PIX_DIV = 1, 8 Takte) funktionieren nur die Registerzugriffe.

## Ausnahme von der Regel „Fremdcode unverändert"

Fünf der sechs Dateien sind gegenüber dem Original geändert (`sid_envelope.sv`
nicht). MiSTer baut mit der älteren Quartus-Standard-Reihe, die über
Formfehler hinwegsieht; Quartus Pro (für den Agilex 5 nötig) und Questa
lehnen das Original ab. Geändert wurde nur die Form, nicht die Funktion:

- Deklarationen stehen jetzt vor ihrer ersten Verwendung. In `sid_tables.sv`
  sind dafür zwei Blöcke hinter die Tabellen gerückt, die sie lesen; in
  `sid_top.sv` und `sid_voice.sv` einzelne Zeilen nach oben.
- `sid_top.sv`: Die Konstante `N` steht in der Parameterliste, weil die
  Portliste sie braucht. Vier Felder, die in einem `always`-Block beschrieben
  werden, sind `reg` statt `wire`.
- Funktionsparameter heißen `input` statt `wire` (`sid_filter.sv`,
  `sid_tables.sv`).
- `sid_filter.sv`: Zwei Variablen mit Startwert stehen im Modul statt im
  `always`-Block.
- `sid_dac.sv`: Der Eingang hat einen ausdrücklichen Leitungstyp, und die
  Datei stellt am Ende `default_nettype` zurück, damit die Einstellung nicht
  auf später gelesene Dateien durchschlägt.

Alle Änderungen stehen als Unterschied zum Original in `quartus_pro.patch`.
Für einen neueren Stand von MiSTer: `COMMIT` in `sw/py/fetch_mister.py`
ändern; passt der Patch dann nicht mehr, die Punkte oben nachziehen.

## Lizenz

- `sid_filter.sv` und `sid_dac.sv` stehen laut Dateikopf unter der
  CERN-OHL-S v2 (Alexey Melnikov; Dag Lem, <https://github.com/daglem/reDIP-SID>).
  Das ist eine Lizenz mit Weitergabepflicht: Wer das Design verändert oder
  darauf aufbaut und weitergibt, muss die Quellen unter derselben Lizenz
  offenlegen. Die Änderungen oben fallen darunter.
- `sid_top.sv`, `sid_voice.sv`, `sid_envelope.sv` und `sid_tables.sv` tragen
  keinen Lizenzvermerk, und das MiSTer-Repository enthält keine Lizenzdatei.

Wegen der Dateien ohne Lizenzvermerk sind alle sechs nicht eingecheckt; im
Repository steht nur der Patch mit den Änderungen oben. Offen bleibt: Wer
einen fertigen Bitstream weitergibt, gibt die beiden Dateien unter der
CERN-OHL-S mit weiter; sie betrifft dann voraussichtlich das ganze Design.

## Nicht im Repository: mit Skript holen

Aus dem Projektverzeichnis:

```
python sw/py/fetch_mister.py
```

Das Skript lädt die sechs Dateien in genau dem Stand oben herunter, wendet
`quartus_pro.patch` an und legt sie hier ab (zusammen mit VIC-II und CIA).
