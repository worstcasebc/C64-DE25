# Commodore 64 on the Terasic DE25-Nano

A step-by-step rebuild of the Commodore 64 on the Terasic DE25-Nano
(Intel Agilex 5 SoC), modelled on the MiSTer architecture: the FPGA reproduces
the C64 hardware cycle-accurately, and the HPS (ARM cores running Linux) is
meant to take over the service tasks — menu, loading `.PRG`/`.D64` files,
configuration.

This is a learning project. It is built milestone by milestone, each one
leaving a system that runs and can be tested, and every own module comes with
a testbench.

> Code comments, commit messages and the documents under `docs/` are written
> in German.

## Status

The C64 runs on the board: BASIC start screen, picture and SID sound over
HDMI, programs loaded from the PC or from a disk image. Timing-critical software works, including
an FLI picture and test programs with SID sound. Linux runs next to it on the
HPS and can type on the C64 keyboard and load programs into its memory.

| # | Milestone | State |
|---|-----------|-------|
| 1 | Foundation: LEDs, keys, PLL, pin constraints | done |
| 2 | CPU running, block RAM, UART text output | done |
| 3 | C64 memory map, banking via `$01`, ROMs | done |
| 4 | Text mode video over HDMI | done |
| 5 | Real VIC-II (sprites, bad lines, raster interrupts) | done |
| 6 | SID and both CIAs, sound over HDMI | done |
| 7 | HPS integration | in progress |

Milestone 7 so far: a second Quartus project builds the same C64 together
with the HPS. Linux boots and reaches the FPGA over the Lightweight
HPS-to-FPGA bridge: it switches three LEDs, and it sends bytes to the C64
through a register of this project (`rtl/io/hps_byte_port.v`) — the same
keystrokes and load blocks that the PC sends over the UART.

Not there yet:

- Keyboard: a USB keyboard works through Linux on the HPS, in the HPS build
  only. Otherwise keystrokes come from a PC over
  the UART (see [Controlling the C64](#controlling-the-c64)).
- Disks: a 1541 disk drive reads `.D64` images that Linux on the HPS supplies
  (HPS build only), chosen from a menu on the screen, and writes to them.
  `.G64` images are prepared but untried and stay write-protected. No tape
  or cartridges.
- Joysticks: the numeric keypad of the USB keyboard acts as one (HPS build
  only); a real USB joystick is not supported yet.
- PAL only.

### What is inside

| Part | Source |
|------|--------|
| CPU 6510 | T65 core (from MiSTer), wrapped in `rtl/cpu/cpu_t65.vhd` |
| VIC-II | FPGA64 / MiSTer, `rtl/video/vendor/fpga64` |
| SID | MiSTer, `rtl/audio/vendor/mister_sid` |
| CIA 6526 (two) | MiSTer, `rtl/io/vendor/mister_cia` |
| Disk drive 1541 | MiSTer (an older revision), `rtl/drive/vendor/mister_c1541`, wrapped in `rtl/drive/drive_1541.sv` |
| Memory map, banking, HDMI output, I2S audio, UART, loader, top level | written for this project |

The whole C64 runs in a single clock domain at 31.5 MHz. The VIC-II produces a
PAL picture, which is line-doubled and sent to the board's HDMI transmitter as
720 x 576 at 50 Hz.

## Repository layout

```
rtl/            Verilog/VHDL modules, one file per module
  cpu/ video/ audio/ mem/ io/ drive/
  */vendor/     third-party cores, each with a README on origin and licence
                (only the CPU is checked in, the others are fetched by script)
tb/             testbenches (tb_<module>.v) and the simulation script
sw/asm/         6502 assembler sources (test ROMs)
sw/py/          Python helpers: ROM conversion, terminal and loader
quartus/        Quartus project: the C64 alone
quartus_hps/    Quartus project: the C64 together with the HPS
roms/           your own ROM files — not part of the repository
docs/           notes, pin assignments
```

## Building

The complete procedure, from a fresh clone to the running board, is in
[INSTALL.md](INSTALL.md): tools, fetching the third-party cores, converting
the ROMs, the two bridges that have to be added in Platform Designer for the
HPS project, building, loading, and setting up the scripts on the board.

In short:

- **Quartus Prime Pro** is required; the Agilex 5 is not supported by the
  Standard or Lite editions. The project was last built with version 26.1.
- Three kinds of files are not in this repository and have to be supplied
  first: the cores from MiSTer (`python sw/py/fetch_mister.py`), your own ROM
  files in `roms/` (`python sw/py/build_rom.py` converts them), and for the
  HPS project Terasic's GHRD files (`python sw/py/fetch_ghrd.py <path>`).
- There are two projects for the same top level `rtl/de25_nano_top.v`:

  | Project | Contains | Use it for |
  |---------|----------|------------|
  | `quartus/de25_nano_c64.qpf` | the C64 alone | quick builds, no Linux needed |
  | `quartus_hps/de25_nano_c64_hps.qpf` | C64 and HPS | everything that needs Linux |

- Loaded over JTAG, the design is gone after a power cycle; written into the
  board's QSPI flash, it starts at power-on (HPS project). Linux boots from
  the microSD card with Terasic's card image.

### Simulation

```
python tb/run_sim.py              all testbenches
python tb/run_sim.py tb_blink     a single one
python tb/run_sim.py tb_blink -w  and open the waveform in GTKWave
```

Every testbench ends with `PASS: <name>`. The script picks Icarus or Questa
per testbench. The testbench of the disk drive (`tb_drive_1541`) takes about
ten minutes and only runs when it is named.

## Controlling the C64

### On the board

| Element | Function |
|---------|----------|
| `KEY0` | reset |
| `SW0` | up: colour-bar test picture instead of the C64 picture |
| `LEDR0` | state. HPS build: blinks fast while the service on Linux is not running (Linux is still booting), lit when it runs, blinks slowly when it reports a problem (no keyboard found, saving failed). Without HPS: 1 Hz heartbeat |
| `LEDR1` | 1541 disk drive: blinks fast while it reads or writes |
| `LEDR2` | HPS build only: the disk has changes that are not in the file yet — do not power off |

Picture and sound come out of the HDMI connector.

### Keyboard and loading programs from the PC

The board's USB Type-C connector (the one with the USB-Blaster) also provides
serial ports. One of them leads to the FPGA and replaces the C64 keyboard:
115200 baud, 8N1. The script `sw/py/c64_term.py` sends each keystroke
immediately, and the FPGA "types" it on the C64's key matrix.

```
python sw/py/c64_term.py COM12                       terminal only
python sw/py/c64_term.py COM12 --load game.prg       load a program first
python sw/py/c64_term.py COM12 --load game.prg --run load it and type RUN
```

`COM12` is the port on the developer's machine; look up yours in the Windows
Device Manager. The board registers two serial ports — the other one is the
Linux console of the HPS.

| PC key | C64 |
|--------|-----|
| Enter | RETURN |
| Backspace, Del | DEL |
| Esc | RUN/STOP |
| Arrow keys | cursor |
| Home / Ins | HOME / INS |
| F1–F8 | F1–F8 |
| Ctrl+L | load a `.PRG` file (asks for the file name) |
| Ctrl+C | quit the terminal |

A `.PRG` file is written straight into the C64's RAM, bypassing the CPU. For
BASIC programs (load address `$0801`) the loader also sets the end-of-program
pointer, so `RUN` is all that is needed afterwards. Machine-code programs are
started the usual way, for example with `SYS 49152`.

`python sw/py/make_demo_prg.py` creates a small BASIC program
(`sw/asm/build/demo.prg`) for trying out the loader.

Text that a 6502 program writes to the debug UART at `$DE00` arrives on the
same serial port.

### From Linux on the HPS

With the HPS build, log in on the HPS serial console (115200 baud, 8N1).
Copy `sw/py/c64_hps.py` and `sw/py/c64_blocks.py` into one directory on the
board; then Linux can type and load programs:

```
sudo python3 c64_hps.py --type "PRINT 1+1"        type a line, then RETURN
sudo python3 c64_hps.py --load game.prg --run     load a program and type RUN
```

The bytes go through a register at `0x2001_0100` into the same path as the
bytes from the PC, so do not load from both sides at the same time.

The comfortable way is the service `sw/py/c64d.py`, which combines USB
keyboard, disk drive and a menu: F12 opens a window on top of the picture
that lists the `.d64`, `.g64` and `.prg` files on a USB stick (FAT32); Enter
inserts the disk or loads the program. The C64 keeps running underneath, so a
disk can be changed in the middle of a game. Setting it up is described in
[INSTALL.md](INSTALL.md), section D6.

The single steps also exist as scripts of their own. A disk image is inserted
into the 1541 drive with `sw/py/c64_disk.py`:

```
sudo python3 c64_disk.py game.d64
```

The disk stays inserted as long as the script runs; Ctrl+C removes it, and
the drive is then switched off. After inserting, give the drive a good two
seconds, then use it as on a real C64: `LOAD "$",8`, `LOAD "*",8,1`. The disk
is write-protected.

A USB keyboard at the board's USB host connector becomes the C64 keyboard
with a third script, `sw/py/c64_keys.py`:

```
sudo python3 c64_keys.py
```

To start it at boot, install `sw/py/c64-keys.service` as a systemd unit; the
steps are at the top of that file.

It passes on which keys are held down, so key combinations and games work.
Keys are mapped by position, not by what is printed on them: the key right of
`L` is the colon, as on a C64. Esc is RUN/STOP, Tab is CTRL, left Ctrl is the
Commodore key; Page Up is RESTORE; the full table is at the top of the script.


The register map is in [quartus_hps/README.md](quartus_hps/README.md).

## Third-party code and licences

This repository has no licence file of its own yet. The third-party parts come
with different terms, described in the README next to each of them:

- **T65** (`rtl/cpu/vendor/t65`): BSD-style licence according to the file
  headers. Included.
- **SID** (`rtl/audio/vendor/mister_sid`): two files are under CERN-OHL-S v2,
  the others carry no licence notice. Not included; only the patch with this
  project's changes is.
- **Disk drive 1541** (`rtl/drive/vendor/mister_c1541`): one file is under
  LGPL 3, one under GPL 3, the others carry no licence notice. Not included;
  only the patch is.
- **CIA** (`rtl/io/vendor/mister_cia`) and **VIC-II**
  (`rtl/video/vendor/fpga64`): no licence notice in the files. Not included;
  for the CIA only the patch is.
- **HPS system** (`quartus_hps/`): the Platform Designer system and the
  bootloader come from Terasic's GHRD example for the DE25-Nano. According to
  the header of Terasic's `golden_top.v`, use and modification are permitted
  for Terasic boards, redistribution beyond that is not. These files are
  therefore not included; see [Building](#building) for where to get them.
- **C64 and 1541 ROMs**: copyrighted, not included.

## Acknowledgements

- [MiSTer C64 core](https://github.com/MiSTer-devel/C64_MiSTer) — source of
  the CPU, VIC-II, SID and CIA cores and the model for the architecture
- Peter Wendrich's [FPGA64](http://www.syntiac.com/fpga64.html)
- Terasic, for the DE25-Nano reference designs
