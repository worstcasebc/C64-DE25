# Commodore 64 on the Terasic DE25-Nano

A step-by-step rebuild of the Commodore 64 on the Terasic DE25-Nano
(Intel Agilex 5 SoC), modelled on the MiSTer architecture: the FPGA reproduces
the C64 hardware cycle-accurately, and the HPS (ARM cores running Linux)
takes over the service tasks — USB keyboard, on-screen menu, supplying
`.PRG` and `.D64` files.

This is a learning project. It is built milestone by milestone, each one
leaving a system that runs and can be tested, and every own module comes with
a testbench.

> Code comments, commit messages and the documents under `docs/` are written
> in German.

## Status

The C64 runs on the board as a stand-alone machine: switch it on, and the
design starts from the board's QSPI flash while Linux boots from the microSD
card. Picture and SID sound come out over HDMI. A USB keyboard is the C64
keyboard, its numeric keypad is a joystick, and F12 opens a menu on top of
the picture that inserts disk images into a 1541 drive or loads programs
from a USB stick. Timing-critical software works, including an FLI picture,
test programs with SID sound and games with their own fast loaders.

| # | Milestone | State |
|---|-----------|-------|
| 1 | Foundation: LEDs, keys, PLL, pin constraints | done |
| 2 | CPU running, block RAM, UART text output | done |
| 3 | C64 memory map, banking via `$01`, ROMs | done |
| 4 | Text mode video over HDMI | done |
| 5 | Real VIC-II (sprites, bad lines, raster interrupts) | done |
| 6 | SID and both CIAs, sound over HDMI | done |
| 7 | HPS integration: keyboard, 1541 disk drive, menu, start from flash | done |

What milestone 7 added. A second Quartus project builds the same C64 together
with the HPS. Linux reaches the FPGA over the Lightweight HPS-to-FPGA bridge
through registers of this project, and one service on Linux (`sw/py/c64d.py`)
does the rest:

- **Keyboard:** a USB keyboard at the board's USB host connector, mapped by
  key position; Page Up is RESTORE.
- **Disk drive:** a 1541 (the real drive's CPU and ROM, so fast loaders work)
  whose tracks Linux supplies from a `.D64` file. Writing works too: what the
  C64 saves is in the file a second later, and a one-time backup
  `<name>.bak` is kept next to it.
- **Menu:** F12 opens a window on top of the picture, while the C64 keeps
  running underneath — insert or change a disk, load a `.PRG`, choose the
  joystick port, reset the C64.
- **Joystick:** the numeric keypad of the USB keyboard, on port 1 or 2.
- **LEDs:** state of the service, drive activity, unsaved changes.

The build without the HPS still exists for quick tests; there the keyboard
and the programs come from a PC over the UART.

Not there yet:

- USB gamepads or joysticks (only the numeric keypad).
- `.G64` images are prepared but untried and stay write-protected.
- No tape, no cartridges, a single drive (device 8).
- PAL only.
- Files get onto the board by USB stick or over the serial console; there is
  no network transfer.
- Formatting a `.D64` with a new ID (`N:NAME,ID`) does not work; the short
  format `N:NAME` does.

Planned work is tracked in the
[GitHub issues](https://github.com/worstcasebc/C64-DE25/issues).

### What is inside

| Part | Source |
|------|--------|
| CPU 6510 | T65 core (from MiSTer), wrapped in `rtl/cpu/cpu_t65.vhd` |
| VIC-II | FPGA64 / MiSTer, `rtl/video/vendor/fpga64` |
| SID | MiSTer, `rtl/audio/vendor/mister_sid` |
| CIA 6526 (two) | MiSTer, `rtl/io/vendor/mister_cia` |
| Disk drive 1541 | MiSTer (an older revision), `rtl/drive/vendor/mister_c1541`, wrapped in `rtl/drive/drive_1541.sv` |
| Memory map, banking, HDMI output, I2S audio, UART, loader, top level | written for this project |
| Registers towards Linux, menu window, status LEDs (`rtl/io/hps_byte_port.v`, `rtl/drive/hps_disk_port.v`, `rtl/video/video_osd.v`, `rtl/io/hps_status_led.v`) | written for this project |

The whole C64 runs in a single clock domain at 31.5 MHz. The VIC-II produces a
PAL picture with a raster no television accepts, so it is written into a
frame buffer and read out again as standard 720p50 (1280 x 720 at 50 Hz,
74.25 MHz pixel clock), every C64 pixel 3 x 3 screen pixels large
(`rtl/video/video_upscaler.v`). The C64 delivers 50.08 pictures per second,
the standard asks for 50.00; about every twelve seconds one picture is left
out. The HPS side of the registers runs on its own 100 MHz clock. Every
signal that crosses between clock domains goes through a synchronizer, a
handshake or a dual-clock memory.

## Repository layout

```
rtl/            Verilog/VHDL modules, one file per module
  cpu/ video/ audio/ mem/ io/ drive/
  */vendor/     third-party cores, each with a README on origin and licence
                (only the CPU is checked in, the others are fetched by script)
tb/             testbenches (tb_<module>.v) and the simulation script
sw/asm/         6502 assembler sources (test ROMs)
sw/py/          Python: on the PC ROM conversion, fetching the cores, terminal
                and loader; on the board the service c64d and its helpers
quartus/        Quartus project: the C64 alone
quartus_hps/    Quartus project: the C64 together with the HPS, and the
                scripts that write it into the flash
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

`COM12` is an example; look up yours in the Windows
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
`python sw/py/make_big_prg.py` creates a self-checking program that fills
all of BASIC memory (`$0801`–`$9FFF`); after `RUN` the border turns green
("OK") or red, with the address of the first wrong byte. Loaded from Linux
with `c64_hps.py`, its 38913 bytes take about 0.1 s.

Text that a 6502 program writes to the debug UART at `$DE00` arrives on the
same serial port.

### From Linux on the HPS

With the HPS build, everything runs through one service on Linux,
`sw/py/c64d.py`. Installed as a systemd unit (`sw/py/c64d.service`), it
starts at boot, so the board needs no PC and no login. Setting it up is
described in [INSTALL.md](INSTALL.md), section D6.

**Keyboard.** A USB keyboard at the board's USB host connector is the C64
keyboard. The service passes on which keys are held down, so key combinations
and games work. Keys are mapped by position, not by what is printed on them:
the key right of `L` is the colon, as on a C64. Esc is RUN/STOP, Tab is CTRL,
left Ctrl is the Commodore key, Page Up is RESTORE; the full table is at the
top of `sw/py/c64_keys.py`.

**Joystick.** The numeric keypad: 8/2/4/6 are the directions, 7/9/1/3 the
diagonals, 0 and right Ctrl are fire. The menu sets the port under SETTINGS
(most games expect port 2).

**Menu.** F12 opens a window on top of the picture with three tabs:
DISK lists the `.d64`, `.g64` and `.prg` files on a USB stick (FAT32, not
exFAT), which can sit in a hub next to the keyboard (without a stick, the
files in the folder of the script); SETTINGS holds the joystick port; RESET
resets the C64. F12 always opens on DISK, so that Enter never resets the C64
by accident.

| Key | Function |
|-----|----------|
| Arrow left/right | switch tab |
| Arrow up/down, Page Up/Down, Home, End | choose an entry |
| Enter | insert the disk, load the program, switch the joystick port, reset the C64 |
| Esc or F12 | close the menu |

The C64 keeps running underneath, so a disk can be changed in the middle of a
game. A `.PRG` is written straight into the C64's RAM; if it starts at the
BASIC start address, the service types `RUN`.

**Disk drive.** An inserted disk is used as on a real C64: `LOAD "$",8`,
`LOAD "*",8,1`, `SAVE "NAME",8`. A `.D64` is writable: what the C64 writes is
in the file about a second later. Before the first change the service puts a
backup `<name>.bak` next to the file, once. While `LEDR2` is lit, the file is
not up to date — do not power off or pull the stick. The drive stays switched
on when the disk is changed or removed, so a fast loader that a game has put
into the drive survives.

For experiments, the single steps also exist as scripts of their own; they
are used instead of the service, not next to it (a lock makes a second one
end with a message):

```
sudo python3 c64_keys.py                          USB keyboard only
sudo python3 c64_disk.py game.d64                 insert one disk, read-only, until Ctrl+C
sudo python3 c64_hps.py --type "PRINT 1+1"        type a line, then RETURN
sudo python3 c64_hps.py --load game.prg --run     load a program and type RUN
```

The bytes of `c64_hps.py` go through a register at `0x2001_0100` into the
same path as the bytes from the PC, so do not load from both sides at the
same time.

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
  the CPU, VIC-II, SID, CIA and 1541 cores and the model for the architecture
- Peter Wendrich's [FPGA64](http://www.syntiac.com/fpga64.html)
- Terasic, for the DE25-Nano reference designs
