# Honux Music Player

Apple II Mockingboard music player that plays VGZ (compressed VGM) files from MSX games.

## Features

- Plays AY-3-8910 PSG music from VGZ/VGM files
- Supports Mockingboard slots 4, 5, or 7
- Stereo output (both PSG chips)
- Loop support for continuous playback
- Simple 3-channel audio visualizer
- HGR title screen display

## Requirements

### Build Tools
- Python 3.x
- cc65 toolchain (ca65, ld65)
- Java 8+ (for AppleCommander)
- Pillow (Python image library)

### Hardware/Emulator
- Apple II with Mockingboard
- Or emulator with Mockingboard support (AppleWin, MAME, etc.)

## Building

```bash
# Build player binary only
make

# Build complete disk image with all tracks
make disk

# Convert specific VGZ file
make play VGZ="vgz/01 Title.vgz"

# Clean build artifacts
make clean
```

## Usage

1. Boot the disk image in an Apple II emulator or real hardware
2. Select Mockingboard slot (4, 5, or 7)
3. Choose a song from the menu
4. Press ESC to stop and return to menu
5. Select 0 to quit

## File Structure

```
apple2-music/
├── src/
│   ├── player.s        # Main player (6502 assembly)
│   ├── mockingboard.s  # Mockingboard driver
│   ├── startup.s       # Entry point
│   └── apple2.cfg      # Linker configuration
├── tools/
│   ├── vgz2a2m.py      # VGZ to A2M converter
│   ├── genmenu.py      # BASIC menu generator
│   ├── png2hgr.py      # PNG to HGR converter
│   └── ac.jar          # AppleCommander
├── vgz/                # Source VGZ files
├── data/               # Converted A2M files
├── build/              # Build output
│   ├── player.bin      # Player binary
│   └── music.dsk       # Disk image
└── Makefile
```

## A2M Format

Custom compact format for Apple II:

```
Header (16 bytes):
  0-3:  Magic "A2M\x00"
  4-5:  Data length (little-endian)
  6-7:  Loop offset (0 = no loop)
  8-15: Reserved

Data Stream:
  $00-$0D vv  : Write value vv to PSG register
  $80-$FD     : Wait 1-126 frames (60Hz)
  $FD         : Loop marker
  $FE         : End of song
  $FF nn nn   : Extended wait (16-bit frame count)
```

## Memory Map

| Address | Size | Content |
|---------|------|---------|
| $0300   | 1    | Slot number |
| $0800   | -    | BASIC program |
| $2000   | 8KB  | HGR title image |
| $4000   | 20KB | Music data (A2M) |
| $9000   | 1.5KB| Player binary |

## Credits

- Player by Honux
- Built with cc65 toolchain
- Disk images created with AppleCommander
