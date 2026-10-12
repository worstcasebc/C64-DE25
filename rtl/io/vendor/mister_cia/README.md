# CIA 6526 aus MiSTer (Fremdcode, in der Form angepasst)

- Quelle: <https://github.com/MiSTer-devel/C64_MiSTer>, Datei `rtl/mos6526.v`
- Stand: Commit `fe6dfe53c99122e5a088691f2d358d6caba61de1` (2026-09-06)
- Autoren laut Dateikopf: Rayne; Timer und Interrupts neu geschrieben von
  slingshot. Besteht laut Dateikopf alle CIA-Timer-Tests der
  „Lorenz"-Sammlung und alle CIA-Tests von VICE außer einem (`dd0dtest`).
- Die Datei heißt hier `mos6526.sv` statt `.v`: Sie benutzt Schreibweisen
  aus SystemVerilog (Variablen, die in einem `always`-Block deklariert
  sind). Icarus läuft hier mit Verilog-2005 und liest sie nicht;
  Testbenches mit CIA laufen über Questa (`tb/tb_cia.v`).

## Ausnahme von der Regel „Fremdcode unverändert"

Eine Änderung, nur in der Form: Der Block „Port B Output" steht jetzt hinter
den beiden Timern, deren Signale er liest. Im Original stand er davor; das
lehnt Questa ab (Name vor seiner Deklaration benutzt). Die Änderung steht als
Unterschied zum Original in `quartus_pro.patch`.

## Anschluss in diesem Projekt (`rtl/soc_c64.v`)

- `phi2_n`: ein Takt lang 1 zu Beginn der CPU-Hälfte. Dann finden die
  Buszugriffe statt (`cs_n`, `rw`, `rs`, `db_in`; gelesene Daten liegen
  danach an `db_out`).
- `phi2_p`: ein Takt lang 1 direkt nach dem Schritt der CPU. Dann zählen die
  Timer und die Port-Ausgänge werden übernommen.
- `pa_in`/`pb_in` erwarten den Pegel an den Pins, also auch das, was die CIA
  selbst ausgibt: Der Aufrufer muss `pa_out`/`pb_out` mit den äußeren
  Signalen verknüpfen.
- `tod`: Netztakt für die Uhr; gezählt werden steigende Flanken.

## Lizenz

Die Datei trägt keinen Lizenzvermerk, und das MiSTer-Repository enthält keine
Lizenzdatei. Sie ist deshalb nicht eingecheckt; im Repository steht nur der
Patch mit der Änderung oben.

## Nicht im Repository: mit Skript holen

Aus dem Projektverzeichnis:

```
python sw/py/fetch_mister.py
```

Das Skript lädt `rtl/mos6526.v` in genau dem Stand oben herunter, wendet
`quartus_pro.patch` an und legt das Ergebnis als `mos6526.sv` hier ab
(zusammen mit VIC-II und SID).
