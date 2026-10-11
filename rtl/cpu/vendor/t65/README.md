# T65 — 6502-Core (Fremdcode, unverändert)

- Quelle: <https://github.com/MiSTer-devel/C64_MiSTer>, Verzeichnis `rtl/t65`
- Stand: Commit `fe6dfe53c99122e5a088691f2d358d6caba61de1` (2026-09-06)
- Dateien: `T65.vhd` (Einstieg), `T65_MCode.vhd`, `T65_ALU.vhd`,
  `T65_Pack.vhd` — nicht verändern; Anpassungen nur über den Wrapper
  `rtl/cpu/cpu_t65.vhd`.
- Herkunft laut Dateikopf: ursprünglich von opencores.org (Daniel Wallner),
  weiterentwickelt bei fpgaarcade.com (MikeJ, Wolfgang Scherr u. a.). Der
  Core ist taktgenau, kennt die undokumentierten Befehle des 6510 und
  besteht laut Dateikopf die „Lorenz"-Testsammlung.
- Sprache: VHDL. Simulation deshalb mit Questa; die Dateien bauen
  aufeinander auf (`T65_Pack.vhd` zuerst), `tb/run_sim.py` findet die
  Reihenfolge selbst.
- Lizenz: BSD-artig laut Dateikopf — Weitergabe in Quell- und
  synthetisierter Form erlaubt, solange der Copyright-Hinweis erhalten
  bleibt.
