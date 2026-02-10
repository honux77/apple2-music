#!/usr/bin/env python3
"""
PNG to Apple II Lo-Res Graphics Converter
Converts PNG images to Apple II Lo-Res format (40x48, 16 colors)
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow library required. Install with: pip install Pillow")
    sys.exit(1)

# Apple II Lo-Res color palette (approximate RGB values)
LORES_PALETTE = [
    (0, 0, 0),        # 0 - Black
    (227, 30, 96),    # 1 - Magenta
    (96, 78, 189),    # 2 - Dark Blue
    (255, 68, 253),   # 3 - Purple
    (0, 163, 96),     # 4 - Dark Green
    (156, 156, 156),  # 5 - Gray 1
    (20, 207, 253),   # 6 - Medium Blue
    (208, 195, 255),  # 7 - Light Blue
    (96, 114, 3),     # 8 - Brown
    (255, 106, 60),   # 9 - Orange
    (156, 156, 156),  # 10 - Gray 2
    (255, 160, 208),  # 11 - Pink
    (20, 245, 60),    # 12 - Light Green
    (208, 221, 141),  # 13 - Yellow
    (114, 255, 208),  # 14 - Aqua
    (255, 255, 255),  # 15 - White
]


def get_text_line_address(row):
    """
    Calculate the base address for a text/lo-res row (0-23).
    Apple II screen memory layout:
    - Rows 0-7: $400, $480, $500, $580, $600, $680, $700, $780
    - Rows 8-15: $428, $4A8, $528, $5A8, $628, $6A8, $728, $7A8
    - Rows 16-23: $450, $4D0, $550, $5D0, $650, $6D0, $750, $7D0
    """
    group = row // 8          # 0, 1, or 2
    row_in_group = row % 8    # 0-7

    # Base address calculation
    address = 0x400 + (row_in_group * 0x80) + (group * 0x28)
    return address


def color_distance(c1, c2):
    """Calculate color distance between two RGB colors"""
    return sum((a - b) ** 2 for a, b in zip(c1, c2))


def find_nearest_color(rgb):
    """Find nearest Apple II Lo-Res color"""
    min_dist = float('inf')
    best_color = 0

    for i, palette_color in enumerate(LORES_PALETTE):
        dist = color_distance(rgb, palette_color)
        if dist < min_dist:
            min_dist = dist
            best_color = i

    return best_color


def convert_png_to_lores(input_path, output_path):
    """Convert PNG to Apple II Lo-Res format"""

    # Load and resize image
    img = Image.open(input_path)
    img = img.convert('RGB')
    img = img.resize((40, 48), Image.Resampling.LANCZOS)

    # Create Lo-Res screen buffer
    # Screen memory is $400-$7FF (1024 bytes)
    screen = bytearray(0x400)

    # Convert pixels
    # Lo-Res has 48 pixel rows, organized as 24 text rows
    # Each text row byte contains 2 vertical pixels:
    # - Low nibble (bits 0-3) = top pixel
    # - High nibble (bits 4-7) = bottom pixel

    for text_row in range(24):
        base_addr = get_text_line_address(text_row)
        offset = base_addr - 0x400  # Convert to buffer offset

        pixel_row_top = text_row * 2
        pixel_row_bottom = text_row * 2 + 1

        for x in range(40):
            # Get colors for top and bottom pixels
            rgb_top = img.getpixel((x, pixel_row_top))
            color_top = find_nearest_color(rgb_top)

            rgb_bottom = img.getpixel((x, pixel_row_bottom))
            color_bottom = find_nearest_color(rgb_bottom)

            # Pack into byte: low nibble = top, high nibble = bottom
            byte_value = (color_bottom << 4) | color_top
            screen[offset + x] = byte_value

    # Write output file
    with open(output_path, 'wb') as f:
        f.write(screen)

    print(f"Converted: {input_path}")
    print(f"Output: {output_path}")
    print(f"Size: {len(screen)} bytes")


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.png> [output.lores]")
        print()
        print("Converts PNG to Apple II Lo-Res format (40x48, 16 colors)")
        print("Output can be BLOADed to $400 on Apple II")
        sys.exit(1)

    input_path = sys.argv[1]

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        output_path = str(Path(input_path).stem) + '.lores'

    convert_png_to_lores(input_path, output_path)


if __name__ == '__main__':
    main()
