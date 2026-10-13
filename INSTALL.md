# Installation and build

Everything needed to get from a fresh clone to a running C64 on the DE25-Nano,
in the order in which it has to be done. What the project is and how to use
it once it runs is in [README.md](README.md).

There are two Quartus projects for the same top level `rtl/de25_nano_top.v`:

| Project | Contains | Needs |
|---------|----------|-------|
| `quartus/de25_nano_c64.qpf` | the C64 alone | parts A and B |
| `quartus_hps/de25_nano_c64_hps.qpf` | the C64 and the HPS with Linux: USB keyboard, loading programs and disks from Linux | parts A, C and D |

Parts A to C run on the PC, part D on the board.

Things that are not confirmed on the board yet are marked *(not confirmed)*.

## A. Common preparation (PC)

### A1. Tools

| Tool | Needed for | Notes |
|------|------------|-------|
| Quartus Prime Pro 26.1 | building | The Agilex 5 is not supported by the Standard or Lite editions. `sof_with_hps.bat` expects the environment variable `QUARTUS_ROOTDIR`, which the Quartus installer sets. |
| Python 3.10 or newer | all helper scripts | `python -m pip install pyserial` for the terminal `c64_term.py` |
| git | `fetch_mister.py` (applies patches with `git apply`) | |
| cc65 (`ca65`, `ld65`) | the project's own test ROMs | in the `PATH` or under `tools/cc65/bin` |
| Icarus Verilog | simulation of the project's own modules | in the `PATH` or under `C:\iverilog` |
| Questa (comes with Quartus) | simulation of everything with VHDL or SystemVerilog | in the `PATH` or under `C:\altera_pro\26.1\questa_fse\win64` |

The helper scripts were written and used on Windows. `c64_term.py` is
Windows-only.

All commands below are run from the repository root unless stated otherwise.

### A2. Third-party cores

The VIC-II, SID, CIA and 1541 disk drive come from the
[MiSTer C64 core](https://github.com/MiSTer-devel/C64_MiSTer) and are not in
this repository. Fetch them once (needs an internet connection):

```
python sw/py/fetch_mister.py
```

The script downloads the files at fixed commits and applies the patches that
make SID, CIA and the disk drive acceptable to Quartus Pro and Questa. The
files end up in `rtl/video/vendor/fpga64`, `rtl/audio/vendor/mister_sid`,
`rtl/io/vendor/mister_cia` and `rtl/drive/vendor/mister_c1541`; each folder
has a README on origin, licence and changes.

### A3. ROMs

The original ROMs are copyrighted and not in this repository. Put your own
copies into `roms/` under exactly these names (they are the names used by the
VICE emulator, which ships them in its folders `C64` and `DRIVES`):

| File | Size | What |
|------|------|------|
| `basic-901226-01.bin` | 8192 bytes | BASIC |
| `chargen-901225-01.bin` | 4096 bytes | character set |
| `kernal-901227-03.bin` | 8192 bytes | KERNAL |
| `dos1541-325302-01+901229-05.bin` | 16384 bytes | ROM of the 1541 disk drive |

Then convert them:

```
python sw/py/build_rom.py
```

This writes `c64_basic.hex`, `c64_chargen.hex`, `c64_kernal.hex` and
`c1541_rom.hex` to `sw/asm/build/`, where the Quartus projects expect them,
and assembles the project's own test ROMs (`banktest_*.hex`). A missing ROM is
skipped with a note; the build in Quartus then fails at the missing file.

Run the script again whenever a ROM file changes.

### A4. Check (optional)

```
python tb/run_sim.py
```

All testbenches must end with `PASS`. See [README.md](README.md#simulation).

## B. The C64 alone (`quartus/`)

1. Open `quartus/de25_nano_c64.qpf` in Quartus.
2. *Processing → Start Compilation*.
3. Load `quartus/output_files/de25_nano_c64.sof` as described in
   [D1](#d1-load-the-design).

This variant has no Linux, so no USB keyboard and no disk: the keyboard is the
PC terminal `c64_term.py`, and the disk drive stays switched off.

## C. The C64 with the HPS (`quartus_hps/`)

### C1. Terasic files

The Platform Designer system with the HPS, its IP files and the HPS
bootloader come from Terasic's GHRD example. Terasic permits use and
modification for its boards but not redistribution, so they are not in this
repository.

1. Download Terasic's resource package for the DE25-Nano from the board's
   page at terasic.com and unpack it. The GHRD is in
   `Demonstration/SoC_FPGA/GHRD`.
2. Copy the files in:

   ```
   python sw/py/fetch_ghrd.py <resource package>\Demonstration\SoC_FPGA\GHRD
   ```

   The script copies `qsys_top.qsys`, the three `*_subsys/*.qsys`, all `.ip`
   files, `custom_ip/` and the bootloader into `quartus_hps/`.

Running the script again overwrites the `.qsys` files and with them the
changes from step C4.

### C2. Short path

In a deeply nested directory Quartus aborts the HPS build after about
40 seconds (`Failed dni::save_checkpoint … manifest.txt was not found on
disk`). Map the repository to a drive letter and work from there:

```
subst Q: <path to the repository>
```

`subst` lasts until the next restart of Windows and has to be set again then.
All further steps of part C use `Q:\quartus_hps\de25_nano_c64_hps.qpf`.

### C3. Open the project and upgrade the IP

1. Open `Q:\quartus_hps\de25_nano_c64_hps.qpf` in Quartus.
2. If Quartus reports outdated IP (Terasic's files were made with 25.1.1), run
   *Project → Upgrade IP Components* once.

### C4. Add two bridges in Platform Designer

The registers through which Linux reaches the C64 are not inside Terasic's
system but in the top level. For that, two pieces of the Avalon bus have to
be led out of the system — like sockets in the wall of a house, to which
devices are connected from outside. Each socket is an
*Avalon Memory Mapped Pipeline Bridge*:

| | `c64_bridge` | `disk_bridge` |
|---|---|---|
| Serves | `rtl/io/hps_byte_port.v`: bytes to the C64, keyboard | `rtl/drive/hps_disk_port.v`: disk for the 1541 |
| *Data width* | 32 | 32 |
| *Symbol width* | 8 | 8 |
| *Address units* | SYMBOLS | SYMBOLS |
| *Use automatically-determined address width* | off | off |
| *Address width* | **4** | **14** |
| *Maximum burst size (words)* | 1 | 1 |
| all other parameters | as preset | as preset |
| Base address of `s0` at `pb_cpu_0.m0` | `0x0001_0100` | `0x0001_4000` |
| Export name of `m0` | `c64_m0` | `disk_m0` |
| Address as seen from Linux | `0x2001_0100` | `0x2001_4000` |

Do the following once for each column:

1. *Tools → Platform Designer*, open `qsys_top.qsys`.
2. In the **Filter** tab on the left, click `subsys_periph
   [peripheral_subsys.qsys]`. The System View now shows `periph_clk`,
   `sysid`, the PIOs and `pb_cpu_0`.
3. Switch to the **IP Catalog** tab on the left, type `pipeline` into the
   search field and double-click **Avalon Memory Mapped Pipeline Bridge IP**.
4. Set the parameters from the table and confirm with **Finish**.
5. The new row is called something like `mm_bridge_0`. Right-click →
   **Rename** and enter the name from the table.
6. In the **Connections** column, click the hollow dots so that they are
   filled:

   | Row of the bridge | Dot on the line of |
   |---|---|
   | `clk` | `periph_clk.out_clk` |
   | `reset` | `periph_rst_in.out_reset` |
   | `s0` | `pb_cpu_0.m0` |

   `m0` stays unconnected.

   Take care with `s0`: its row offers one dot for every bus master in the
   subsystem, and from the second bridge on that includes the `m0` of the
   bridges themselves. Only the dot of `pb_cpu_0.m0` may be filled.
7. Switch to the **Address Map** tab. It has one column per bus master. In
   the row `<bridge>.s0`, column `pb_cpu_0.m0`, double-click the address and
   enter the base address from the table. The columns `c64_bridge.m0` and
   `disk_bridge.m0` must stay empty in every row; an entry there means a
   wrong connection from step 6, which shows up as the errors "cannot be both
   connected and exported" and "is outside the master's address range".
   Remove it by clicking the filled dot in the System View again.
8. Back in the **System View** tab: in the row `<bridge>` → `m0`, double-click
   the **Export** column and enter the export name from the table.
9. In the **Filter** tab, click the top row `qsys_top [qsys_top.qsys]`. At
   `subsys_periph` there is now a new row with the export name. Double-click
   its **Export** column and enter the same name again.

After both bridges:

10. *File → Save*.
11. Make sure the top row `qsys_top [qsys_top.qsys]` is selected in the
    **Filter** tab, then **Generate HDL…** (bottom right) → *Generate*.
    Generating while `subsys_periph` is selected only renews the subsystem;
    `qsys_top/synth/qsys_top.v` then keeps its old ports.

Checks:

- The status line still shows "0 Errors". The warnings ("Project Setting
  information doesn't match IP Variant file", "… which is missing in file …",
  "Quartus project not specified") concern Terasic's older files and can be
  ignored; none of them should name `c64_bridge` or `disk_bridge`.
- `quartus_hps/qsys_top/qsys_top_inst.v` contains ten ports `c64_m0_*`
  (`address` 4 bits wide) and ten ports `disk_m0_*` (`address` 14 bits wide).
- Platform Designer creates one `.ip` file per bridge under
  `quartus_hps/peripheral_subsys/ip/peripheral_subsys/` and names it itself
  (`peripheral_subsys_mm_bridge_0.ip` for the first one — the file keeps the
  suggested name even after the bridge is renamed). Every such file needs a
  line `set_global_assignment -name IP_FILE …` in `de25_nano_c64_hps.qsf`.
  Compare the names there with the files that were created.

### C5. Compile

1. Close the project and open it again if the `.qsf` was edited outside
   Quartus; otherwise Quartus keeps working with the old one and overwrites
   the file when it exits.
2. *Processing → Start Compilation*.

Known messages that are no problem:

- Critical Warning 19434 about `ALU_Op_r` (from the T65 CPU core).
- Warning 24541 about `drive_num` in `c1541_multi.sv`.
- "Node HPS_… is assigned to location or region, but does not exist in
  design" — the HPS pins are hard-wired.
- The Design Assistant reports no violations of high severity. Four kinds of
  findings are waived, each with its reason, in `quartus/de25_nano_c64.dawf`
  (69 entries: the crossings between the HPS and the C64, and placeholder
  output delays). What remains is of medium or low severity and not waived:
  RDC-50003 (Terasic's system), TMC-20025 (the JTAG clock group in the
  `.sdc` covers no path) and LNT-30010 (a style hint).

### C6. Add the bootloader

The `.sof` from the build does not contain the HPS bootloader. Run

```
quartus_hps\sof_with_hps.bat
```

It creates `quartus_hps\output_files\de25_nano_c64_hps_boot.sof`. That is the
file to load — after every build.

## D. On the board

### D1. Load the design

1. Switch SW5 must be in JTAG mode (SW5.1–5.3 OFF). Change it only with the
   board powered off.
2. For the HPS variant, insert the microSD card with the card image that
   Terasic supplies for the board.
3. Connect the USB Type-C connector with the USB-Blaster to the PC and power
   the board.
4. Load the `.sof` with the Quartus Programmer over the on-board
   USB-Blaster III (`de25_nano_c64.sof`, or `de25_nano_c64_hps_boot.sof` for
   the HPS variant).

The QSPI flash is not touched, so the design is gone after a power cycle and
has to be loaded again.

Picture and sound come out of the HDMI connector. `LEDR0` blinks at 1 Hz when
the design runs.

### D2. Serial ports

The USB Type-C connector provides two serial ports, both 115200 baud, 8N1.
Look up their numbers in the Windows Device Manager.

- One leads to the FPGA: keyboard replacement and program loader from the PC
  (`python sw/py/c64_term.py COM12`, see [README.md](README.md)).
- The other is the Linux console of the HPS. Login on Terasic's card image:
  `terasic`, password `123`.

The remaining steps are for the HPS variant only.

### D3. Copy the scripts to the board

These files go into `/home/terasic` on the board:

| File | For |
|------|-----|
| `sw/py/c64_hps.py`, `sw/py/c64_blocks.py` | typing and loading `.PRG` files from Linux |
| `sw/py/c64_keys.py` | USB keyboard |
| `sw/py/c64-keys.service` | starting the keyboard at boot |
| `sw/py/c64_disk.py` | inserting a disk |
| `sw/py/c64d.py`, `sw/py/c64d.service` | keyboard, disk drive and menu in one service; needs `c64_keys.py`, `c64_disk.py` and `c64_blocks.py` next to it |
| your `.prg`, `.d64` and `.g64` files | |

Over the network, if the board is connected and the card image runs an SSH
server *(not confirmed)*:

```
scp sw/py/c64_hps.py sw/py/c64_blocks.py sw/py/c64_keys.py sw/py/c64-keys.service sw/py/c64_disk.py terasic@<address of the board>:~
```

Without a network, through the Linux console:

- Text files: type `cat > <file>` on the board, paste the content, press
  Enter and then Ctrl+D. Check scripts afterwards with
  `python3 -m py_compile <file> && echo ok`.
- Binary files: on the PC, print the file as Base64 together with its
  checksum:

  ```
  python -c "import base64,hashlib,sys; d=open(sys.argv[1],'rb').read(); print(base64.encodebytes(d).decode()); print('md5', hashlib.md5(d).hexdigest())" <file>
  ```

  On the board, type `base64 -d > <file>`, paste the text, press Enter and
  Ctrl+D, then compare with `md5sum <file>`. The console can lose characters
  when many lines are pasted, so always compare the checksum; beyond a few
  kilobytes the network or the SD card is the better way.

### D4. USB keyboard

1. Plug the keyboard into the USB host connector of the HPS.
2. Try it by hand:

   ```
   sudo python3 c64_keys.py --list
   sudo python3 c64_keys.py
   ```

   Typing now goes to the C64; Ctrl+C on the console ends it.
3. Start it at every boot:

   ```
   sudo cp c64-keys.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now c64-keys
   systemctl status c64-keys
   ```

   To switch it off again: `sudo systemctl disable --now c64-keys`.

The service expects the script at `/home/terasic/c64_keys.py`. It also starts
when a design without these registers is loaded; how the bridge reacts then
has not been examined.

### D5. Programs and disks

```
sudo python3 c64_hps.py --load game.prg --run     load a program and type RUN
sudo python3 c64_disk.py game.d64                 insert a disk
```

The disk stays inserted as long as `c64_disk.py` runs; Ctrl+C removes it.
After inserting, the drive needs a good two seconds until it is ready. Then,
on the C64: `LOAD "$",8` and `LIST`, or `LOAD "*",8,1` and `RUN`. Confirmed
with a `.D64` image; `.G64` images are prepared but untried, and the disk is
write-protected.

### D6. Keyboard, disk drive and menu in one service

`c64d.py` does what `c64_keys.py` and `c64_disk.py` do, and adds a menu: F12
on the USB keyboard opens a window on top of the picture, in which a disk
image or a program is chosen. The C64 keeps running underneath, so this also
works when a game asks for the next disk.

1. Put the `.d64`, `.g64` and `.prg` files into the top folder of a USB stick
   formatted as **FAT32** and plug it into a USB hub together with the
   keyboard. Terasic's Linux cannot read exFAT, the format in which many
   sticks are sold; reformat such a stick on the PC. Without a stick the
   service lists the files in its own folder (`/home/terasic`); the line
   above the bottom of the menu says which source is in use. The stick can
   be unplugged and plugged in again while the service runs; the next time
   the menu is opened it uses whatever is there.
2. Stop the keyboard service from D4, if it is installed — two programs
   cannot own the keyboard at the same time:

   ```
   sudo systemctl disable --now c64-keys
   ```
3. Try it by hand (Ctrl+C on the console ends it):

   ```
   sudo python3 c64d.py
   ```

   | Key | In the menu |
   |-----|-------------|
   | F12 | open and close the menu |
   | arrow up/down, Page Up/Down | choose an entry |
   | Enter | insert the `.d64`/`.g64`, or load the `.prg` (a BASIC program is started with RUN); on the entry `<JOYSTICK: PORT n>` switch the joystick to the other port; on `<C64 ZURUECKSETZEN>` reset the C64 |
   | Esc | close the menu |

   Outside the menu the numeric keypad is a joystick:
   8/2/4/6 are the directions, 7/9/1/3 the diagonals, 0 and right Ctrl are
   fire. Most games expect it at port 2, which is the preset.

4. Start it at every boot:

   ```
   sudo cp c64d.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now c64d
   systemctl status c64d
   ```

Only one program at a time may serve the keyboard and the disk drive. The
scripts check this themselves: a second `c64d.py`, or `c64_keys.py` or
`c64_disk.py` next to it, ends at once with a message. To run `c64d.py` by
hand while the service is installed, stop the service first:

```
sudo systemctl stop c64d
sudo python3 c64d.py -v
```

With `-v` it prints every request of the disk drive and, every two seconds,
the state of the registers — the first thing to look at when loading fails.
`systemctl is-active c64d c64-keys` shows what is running in the background.

After inserting a disk, give the drive about three seconds before the first
`LOAD`.

A `.d64` inserted through the menu can be written to (`SAVE`, saved games):
what the C64 writes is in the file one second later. Before the first change
to a file the service puts a copy `<name>.bak` next to it, once. The USB
stick is mounted read-only and made writable only for the moment of writing.
`.g64` images are write-protected.

## E. Starting without the PC

Loaded over JTAG, the design is gone after a power cycle. Written into the
board's QSPI flash, it is loaded at every power-on; together with the service
from D6 the board then works as a C64 without a PC. This is for the HPS
project. The procedure is Terasic's (Demonstration Manual, chapter 4), with
the file names of this project.

Writing the flash replaces what is in it — from the factory, Terasic's
start-up design. That is not a risk for the board: loading over JTAG keeps
working whatever the flash contains, and the factory content can be written
back (see below).

1. Build the design and add the bootloader (C5, C6).
2. Convert it into a flash file:

   ```
   quartus_hps\sof_to_jic.bat
   ```

   This creates `quartus_hps\output_files\de25_nano_c64_hps.jic`.
3. Power the board off and set SW5 to AS mode: SW5.1 OFF, SW5.2 ON,
   SW5.3 ON (MSEL[2:0] = 001; this is the setting the board is shipped
   with). Power it on, with the USB cable of the USB-Blaster connected.
4. Write the flash:

   ```
   quartus_hps\flash_program.bat
   ```

   It writes and verifies; this takes a few minutes.
5. Power the board off and on. The design starts from the flash, and Linux
   boots from the microSD card as before.

SW5 stays in AS mode from now on. To go back to the factory content, run
Terasic's `flash_program.bat` from the resource package
(`Demonstration\SoC_FPGA\GHRD\output_files\program_qspi_flash`), again in AS
mode.

After a new build, repeat steps 1, 2 and 4.

## After changes

| What changed | Do again |
|--------------|----------|
| a ROM file in `roms/` | A3, then compile (B or C5, C6) and load |
| own RTL | compile (B or C5, C6) and load |
| `COMMIT` in `fetch_mister.py` or a patch | A2, then compile and load |
| Windows was restarted | C2 |
| `fetch_ghrd.py` was run again | C3 and C4 |
| a script under `sw/py` that runs on the board | D3, then restart the service that uses it (`sudo systemctl restart c64d` or `c64-keys`) |
| the board was powered off | D1 — unless the design is in the flash (part E) |
