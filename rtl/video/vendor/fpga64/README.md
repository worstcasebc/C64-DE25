# VIC-II aus FPGA64 / MiSTer (Fremdcode, unverändert)

- Quelle: <https://github.com/MiSTer-devel/C64_MiSTer>, Datei
  `rtl/video_vicII_656x.vhd`
- Stand: Commit `fe6dfe53c99122e5a088691f2d358d6caba61de1` (2026-09-06)
- Autor laut Dateikopf: Peter Wendrich (FPGA64,
  <http://www.syntiac.com/fpga64.html>), mit späteren Änderungen aus dem
  MiSTer-Projekt.
- Datei nicht verändern; Anpassungen nur über Wrapper in `rtl/video/`.
- Sprache: VHDL. Simulation deshalb mit Questa statt Icarus.

## Nicht im Repository: mit Skript holen

Die Datei nennt nur den Autor, aber keine Lizenz, und das MiSTer-Repository
enthält keine Lizenzdatei. Sie ist deshalb nicht eingecheckt. Aus dem
Projektverzeichnis holt

```
python sw/py/fetch_mister.py
```

sie in genau dem Stand oben hierher (zusammen mit SID und CIA).
