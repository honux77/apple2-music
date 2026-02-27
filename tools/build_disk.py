#!/usr/bin/env python3
"""Build an Apple II DOS 3.3 disk image for a music album.

Usage:
    build_disk.py album_dir data_dir output_dsk player_bin ac_jar dos33_master tools_dir
"""

import sys
import subprocess
import shutil
from pathlib import Path

# DOS filename mapping for known track names (same as genmenu.py)
DOS_NAMES = {
    "01 Title": "TITLE",
    "02 Game Start": "GSTART",
    "03 Main BGM 1": "BGM1",
    "04 Boss": "BOSS",
    "05 Stage Select": "STAGE",
    "06 Main BGM 2": "BGM2",
    "07 Last Boss": "LASTBOSS",
    "08 Ending": "ENDING",
    "09 Staff": "STAFF",
    "10 Death": "DEATH",
    "11 Game Over": "GAMEOVER",
}

DOS_SYSTEM_FILES = [
    "HELLO", "APPLESOFT", "LOADER.OBJ0", "FPBASIC", "INTBASIC",
    "MASTER", "MASTER CREATE", "COPY", "COPY.OBJ0", "COPYA",
    "CHAIN", "RENUMBER", "FILEM", "FID", "CONVERT13", "MUFFIN",
    "START13", "BOOT13", "SLOT#",
]


def get_dos_name(stem):
    """Return an Apple DOS filename for the given file stem.

    Apple DOS 3.3 filenames must start with a letter.
    If the generated name starts with a non-letter, prefix with 'A'.
    """
    name = DOS_NAMES.get(stem, stem[:8].upper().replace(" ", ""))
    if name and not name[0].isalpha():
        name = "A" + name[:7]
    return name


def run(cmd, check=True):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="")
    if check and result.returncode != 0:
        print(f"Error running command:\n  {cmd}", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result


def main():
    if len(sys.argv) < 8:
        print(
            f"Usage: {sys.argv[0]} "
            "album_dir data_dir output_dsk player_bin ac_jar dos33_master tools_dir",
            file=sys.stderr,
        )
        sys.exit(1)

    album_dir  = Path(sys.argv[1])
    data_dir   = Path(sys.argv[2])
    output_dsk = Path(sys.argv[3])
    player_bin = Path(sys.argv[4])
    ac_jar     = Path(sys.argv[5])
    dos33      = Path(sys.argv[6])
    tools_dir  = Path(sys.argv[7])

    python = sys.executable
    ac = f'java -jar "{ac_jar}"'

    print(f"=== Building disk for album: {album_dir.name} ===")

    # ------------------------------------------------------------------ #
    # Step 1: Convert VGZ -> A2M
    # ------------------------------------------------------------------ #
    data_dir.mkdir(parents=True, exist_ok=True)

    vgz_files = sorted(album_dir.glob("*.vgz"))
    if not vgz_files:
        print(f"Warning: No VGZ files found in {album_dir}", file=sys.stderr)
    for vgz in vgz_files:
        a2m = data_dir / (vgz.stem + ".a2m")
        print(f"  Convert: {vgz.name} -> {a2m.name}")
        run(f'{python} "{tools_dir}/vgz2a2m.py" "{vgz}" "{a2m}"')

    # ------------------------------------------------------------------ #
    # Step 2: Convert PNG -> HGR
    # ------------------------------------------------------------------ #
    title_hgr = data_dir / "title.hgr"
    png_files = sorted(album_dir.glob("*.png"))
    if png_files:
        png = png_files[0]
        print(f"  Convert: {png.name} -> title.hgr")
        run(f'{python} "{tools_dir}/png2hgr.py" "{png}" "{title_hgr}"')

    # ------------------------------------------------------------------ #
    # Step 3: Collect A2M files
    # ------------------------------------------------------------------ #
    a2m_files = sorted(data_dir.glob("*.a2m"))
    if not a2m_files:
        print("Error: No A2M files to add to disk!", file=sys.stderr)
        sys.exit(1)

    # ------------------------------------------------------------------ #
    # Step 4: Build disk image
    # ------------------------------------------------------------------ #
    print(f"\n  Creating: {output_dsk}")
    shutil.copy(dos33, output_dsk)

    # Remove default DOS system files to free space
    for f in DOS_SYSTEM_FILES:
        run(f'{ac} -d "{output_dsk}" "{f}"', check=False)

    # Add player binary (skip 2-byte load address header)
    run(f'tail -c +3 "{player_bin}" | {ac} -p "{output_dsk}" PLAYER B 0x9000')

    # Add title image
    if title_hgr.exists():
        run(f'cat "{title_hgr}" | {ac} -p "{output_dsk}" TITLEIMG B 0x2000')
    else:
        print("  Warning: No title image found — TITLEIMG not added.")

    # Add A2M music files
    for a2m in a2m_files:
        dos_name = get_dos_name(a2m.stem)
        print(f"  Adding:   {a2m.name} -> {dos_name}")
        run(f'cat "{a2m}" | {ac} -p "{output_dsk}" {dos_name} B 0x4000')

    # ------------------------------------------------------------------ #
    # Step 5: Generate HELLO (Applesoft BASIC menu)
    # ------------------------------------------------------------------ #
    a2m_args = " ".join(f'"{a}"' for a in a2m_files)
    menu_bas = output_dsk.parent / f"{album_dir.name}_menu.bas"
    run(f'{python} "{tools_dir}/genmenu.py" {a2m_args} > "{menu_bas}"')
    run(f'cat "{menu_bas}" | {ac} -bas "{output_dsk}" HELLO')

    # ------------------------------------------------------------------ #
    # Done
    # ------------------------------------------------------------------ #
    print()
    run(f'{ac} -l "{output_dsk}"')
    print(f"\nDisk image ready: {output_dsk}\n")


if __name__ == "__main__":
    main()
