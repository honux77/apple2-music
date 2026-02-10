#!/usr/bin/env python3
"""
Generate BASIC menu program for Apple II music player
Lists all A2M files and allows selection
"""

import sys
from pathlib import Path

# Mapping of A2M files to DOS filenames (must match Makefile)
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


def generate_menu(a2m_files):
    """Generate Applesoft BASIC menu program"""
    lines = []

    # Startup - slot selection (only once)
    lines.append('1 HOME')
    lines.append('2 PRINT "HONUX MUSIC PLAYER LOADING..."')
    lines.append('3 FOR I = 1 TO 500 : NEXT I')
    lines.append('4 IF PEEK(768) >= 4 AND PEEK(768) <= 7 THEN GOTO 15')
    lines.append('5 HOME')
    lines.append('6 PRINT "SELECT MOCKINGBOARD SLOT:"')
    lines.append('7 PRINT : PRINT "  4 - SLOT 4"')
    lines.append('8 PRINT "  5 - SLOT 5" : PRINT "  7 - SLOT 7"')
    lines.append('9 PRINT : INPUT "YOUR CHOICE (4,5,7): ";S')
    lines.append('10 IF S < 4 OR S > 7 THEN GOTO 5')
    lines.append('11 IF S = 6 THEN GOTO 5')
    lines.append('12 POKE 768,S')

    # Header - song menu
    lines.append('15 HOME')
    lines.append('20 PRINT "MOCKINGBOARD MUSIC PLAYER"')
    lines.append('30 PRINT "========================="')
    lines.append('35 PRINT "        (SLOT ";PEEK(768);")"')
    lines.append('40 PRINT')
    lines.append('50 PRINT "SELECT A SONG:"')
    lines.append('60 PRINT')

    # Song list
    line_num = 100
    for i, (filename, display_name, dos_name) in enumerate(a2m_files, 1):
        # Truncate display name if too long
        if len(display_name) > 22:
            display_name = display_name[:19] + "..."
        lines.append(f'{line_num} PRINT " {i:2}. {display_name}"')
        line_num += 10

    # Quit option and input prompt
    lines.append(f'{line_num} PRINT')
    line_num += 10
    lines.append(f'{line_num} PRINT "  0. QUIT"')
    line_num += 10
    lines.append(f'{line_num} PRINT')
    line_num += 10
    lines.append(f'{line_num} INPUT "YOUR CHOICE: ";C')
    line_num += 10

    # Handle quit
    lines.append(f'{line_num} IF C = 0 THEN END')
    line_num += 10

    # Validate input
    lines.append(f'{line_num} IF C < 1 OR C > {len(a2m_files)} THEN GOTO 10')
    line_num += 10

    # Branch to load routines
    for i in range(1, len(a2m_files) + 1):
        lines.append(f'{line_num} IF C = {i} THEN GOTO {1000 + i * 100}')
        line_num += 10

    # Jump back to menu (shouldn't reach here)
    lines.append(f'{line_num} GOTO 10')
    line_num += 10

    # Load routines for each song
    # BLOAD music to $4000, BLOAD player to $6000, CALL player
    # 24576 = $6000 in decimal
    for i, (filename, display_name, dos_name) in enumerate(a2m_files, 1):
        base_line = 1000 + i * 100
        lines.append(f'{base_line} PRINT CHR$(4);"BLOAD {dos_name},A$4000"')
        lines.append(f'{base_line + 10} PRINT CHR$(4);"BLOAD PLAYER,A$6000"')
        lines.append(f'{base_line + 20} CALL 24576')
        lines.append(f'{base_line + 30} GOTO 15')

    return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <a2m_file1> [a2m_file2] ...", file=sys.stderr)
        sys.exit(1)

    a2m_files = []
    for filepath in sys.argv[1:]:
        path = Path(filepath)
        filename = path.stem  # filename without extension

        # Get DOS name from mapping
        dos_name = DOS_NAMES.get(filename, filename[:8].upper().replace(' ', ''))

        # Create display name (remove leading numbers)
        display = filename
        if len(display) > 2 and display[:2].isdigit():
            display = display[3:] if display[2] == ' ' else display[2:]

        a2m_files.append((filename, display, dos_name))

    menu = generate_menu(a2m_files)
    print(menu)


if __name__ == '__main__':
    main()
