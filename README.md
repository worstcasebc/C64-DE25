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
HDMI, programs loaded from the PC. Timing-critical software works, including
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
  only and without the RESTORE key. Otherwise keystrokes come from a PC over
  the UART (see [Controlling the C64](#controlling-the-c64)).
- No disk drive, so no `.D64` support, and no tape or cartridges.
- No joysticks.
- PAL only.
- A menu or file browser on the HPS.

### What is inside

| Part | Source |
|------|--------|
| CPU 6510 | T65 core (from MiSTer), wrapped in `rtl/cpu/cpu_t65.vhd` |
| VIC-II | FPGA64 / MiSTer, `rtl/video/vendor/fpga64` |
| SID | MiSTer, `rtl/audio/vendor/mister_sid` |
| CIA 6526 (two) | MiSTer, `rtl/io/vendor/mister_cia` |
| Memory map, banking, HDMI output, I2S audio, UART, loader, top level | written for this project |

The whole C64 runs in a single clock domain at 31.5 MHz. The VIC-II produces a
PAL picture, which is line-doubled and sent to the board's HDMI transmitter as
720 x 576 at 50 Hz.

## Repository layout

```
rtl/            Verilog/VHDL modules, one file per module
  cpu/ video/ audio/ mem/ io/
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

### Requirements

- **Quartus Prime Pro** — the Agilex 5 is not supported by the Standard or
  Lite editions. The project was last built with version 26.1.
- **Python 3**, plus `pyserial` for the terminal:
  `python -m pip install pyserial`
- **cc65** (`ca65`, `ld65`), in the `PATH` or under `tools/cc65/bin` — only
  needed for the test ROMs.
- For simulation: **Icarus Verilog**, and **Questa** (part of the Quartus
  package) for everything that involves the VHDL or SystemVerilog cores.

The helper scripts were written and used on Windows; `c64_term.py` is
Windows-only.

### 1. Third-party cores

The VIC-II, SID and CIA cores from MiSTer are not in this repository, because
their licence situation is unclear. Fetch them once, from the repository root:

```
python sw/py/fetch_mister.py
```

The script downloads the files from the
[MiSTer C64 core](https://github.com/MiSTer-devel/C64_MiSTer) at a fixed
commit and applies the patches for SID and CIA that make them acceptable to
Quartus Pro and Questa. It needs `git` and an internet connection. Simulation
needs these files as well.

### 2. ROMs

The original KERNAL, BASIC and character ROMs are copyrighted and are not in
this repository. Put your own copies into `roms/` under these names:

| File | Size |
|------|------|
| `basic-901226-01.bin` | 8192 bytes |
| `chargen-901225-01.bin` | 4096 bytes |
| `kernal-901227-03.bin` | 8192 bytes |

Then convert them, from the repository root:

```
python sw/py/build_rom.py
```

This writes `c64_basic.hex`, `c64_chargen.hex` and `c64_kernal.hex` to
`sw/asm/build/`, where the Quartus projects expect them. The same call also
assembles the project's own test ROMs (`banktest_*.hex`). Without the original
ROMs you can enter those three files as the parameters `BASIC_FILE`,
`CHAR_FILE` and `KERNAL_FILE` of `rtl/de25_nano_top.v`; that gives a
memory-map test, not a working C64.

### 3. Compile

There are two projects for the same top level `rtl/de25_nano_top.v`:

| Project | Contains | Use it for |
|---------|----------|------------|
| `quartus/de25_nano_c64.qpf` | the C64 alone | quick builds, no Linux needed |
| `quartus_hps/de25_nano_c64_hps.qpf` | C64 and HPS | everything that needs Linux |

Open the project in Quartus and run *Processing → Start Compilation*. The
result is `output_files/de25_nano_c64.sof` or
`output_files/de25_nano_c64_hps.sof`.

Three things to know about the HPS project
(details in [quartus_hps/README.md](quartus_hps/README.md)):

- **Terasic files.** The Platform Designer system with the HPS, its IP files
  and the HPS bootloader come from Terasic's GHRD example and may not be
  redistributed, so they are not in this repository. Download Terasic's
  resource package for the DE25-Nano from the board's page at terasic.com,
  unpack it, and copy the files in before the first build:

  ```
  python sw/py/fetch_ghrd.py <resource package>\Demonstration\SoC_FPGA\GHRD
  ```

  If Quartus then reports outdated IP, run *Project → Upgrade IP Components*
  once.
- **One manual change.** Terasic's system needs one addition in Platform
  Designer before the build: a bridge that leads a piece of the Avalon bus out
  to the top level. The steps are in
  [quartus_hps/README.md](quartus_hps/README.md).
- **Short path.** In a deeply nested directory Quartus aborts the HPS build
  after about 40 seconds. Map the repository to a drive letter first
  (`subst Q: <path to the repository>`) and open the project from there.
- **Bootloader.** The `.sof` from the build does not contain the HPS
  bootloader. Run `quartus_hps\sof_with_hps.bat` afterwards; it creates
  `output_files\de25_nano_c64_hps_boot.sof`, which is the file to load.

### 4. Load onto the board

Load the `.sof` over JTAG with the Quartus Programmer, using the on-board
USB-Blaster III. Switch SW5 must be in JTAG mode (SW5.1–5.3 OFF; change it
only with the board powered off). The QSPI flash is not touched, so the design
is gone after a power cycle.

For the HPS variant, Linux boots from the microSD card; the project uses the
card image that Terasic supplies for the board.

### Simulation

```
python tb/run_sim.py              all testbenches
python tb/run_sim.py tb_blink     a single one
python tb/run_sim.py tb_blink -w  and open the waveform in GTKWave
```

Every testbench ends with `PASS: <name>`. The script picks Icarus or Questa
per testbench.

## Controlling the C64

### On the board

| Element | Function |
|---------|----------|
| `KEY0` | reset |
| `SW0` | up: colour-bar test picture instead of the C64 picture |
| `LEDR0` | 1 Hz heartbeat — blinks only while the PLL is running |
| `LEDR1`–`LEDR3` | HPS build only: switched from Linux |

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

A USB keyboard at the board's USB host connector becomes the C64 keyboard
with a third script, `sw/py/c64_keys.py`:

```
sudo python3 c64_keys.py
```

It passes on which keys are held down, so key combinations and games work.
Keys are mapped by position, not by what is printed on them: the key right of
`L` is the colon, as on a C64. Esc is RUN/STOP, Tab is CTRL, left Ctrl is the
Commodore key; the full table is at the top of the script. RESTORE is missing.

A second register, 3 bits at `0x2001_0080`, switches `LEDR1`–`LEDR3`:

```
sudo python3 -c "import mmap,os,struct; f=os.open('/dev/mem',os.O_RDWR|os.O_SYNC); m=mmap.mmap(f,4096,offset=0x20010000); m[0x80:0x84]=struct.pack('<I',7)"
```

The register map is in [quartus_hps/README.md](quartus_hps/README.md).

## Third-party code and licences

This repository has no licence file of its own yet. The third-party parts come
with different terms, described in the README next to each of them:

- **T65** (`rtl/cpu/vendor/t65`): BSD-style licence according to the file
  headers. Included.
- **SID** (`rtl/audio/vendor/mister_sid`): two files are under CERN-OHL-S v2,
  the others carry no licence notice. Not included; only the patch with this
  project's changes is.
- **CIA** (`rtl/io/vendor/mister_cia`) and **VIC-II**
  (`rtl/video/vendor/fpga64`): no licence notice in the files. Not included;
  for the CIA only the patch is.
- **HPS system** (`quartus_hps/`): the Platform Designer system and the
  bootloader come from Terasic's GHRD example for the DE25-Nano. According to
  the header of Terasic's `golden_top.v`, use and modification are permitted
  for Terasic boards, redistribution beyond that is not. These files are
  therefore not included; see [Building](#building) for where to get them.
- **C64 ROMs**: copyrighted, not included.

## Acknowledgements

- [MiSTer C64 core](https://github.com/MiSTer-devel/C64_MiSTer) — source of
  the CPU, VIC-II, SID and CIA cores and the model for the architecture
- Peter Wendrich's [FPGA64](http://www.syntiac.com/fpga64.html)
- Terasic, for the DE25-Nano reference designs
