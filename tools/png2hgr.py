#!/usr/bin/env python3
"""
PNG to Apple II Hi-Res Graphics Converter
Converts PNG images to Apple II HGR format (280x192, monochrome with dithering)
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow library required. Install with: pip install Pillow")
    sys.exit(1)


def get_hgr_line_address(y):
    """
    Calculate the base address for an HGR line (0-191).
    Apple II HGR screen memory layout at $2000-$3FFF:

    Address = $2000 + (y % 8) * $400 + (y // 64) * $28 + ((y // 8) % 8) * $80
    """
    base = 0x2000
    offset = (y % 8) * 0x400 + (y // 64) * 0x28 + ((y // 8) % 8) * 0x80
    return base + offset


def convert_png_to_hgr(input_path, output_path):
    """Convert PNG to Apple II HGR format (monochrome with Floyd-Steinberg dithering)"""

    # Load and resize image to HGR resolution
    img = Image.open(input_path)
    img = img.convert('L')  # Convert to grayscale
    img = img.resize((280, 192), Image.Resampling.LANCZOS)

    # Apply Floyd-Steinberg dithering to convert to 1-bit
    pixels = list(img.getdata())
    width, height = img.size

    # Create error diffusion buffer
    errors = [[0.0] * (width + 2) for _ in range(2)]

    # Create output bitmap (1 = white, 0 = black)
    bitmap = [[0] * width for _ in range(height)]

    for y in range(height):
        row_idx = y % 2
        next_row_idx = (y + 1) % 2

        # Clear next row errors
        errors[next_row_idx] = [0.0] * (width + 2)

        for x in range(width):
            # Get pixel value with accumulated error
            old_pixel = pixels[y * width + x] + errors[row_idx][x + 1]

            # Threshold
            new_pixel = 255 if old_pixel > 127 else 0
            bitmap[y][x] = 1 if new_pixel == 255 else 0

            # Calculate error
            quant_error = old_pixel - new_pixel

            # Distribute error (Floyd-Steinberg)
            if x + 1 < width:
                errors[row_idx][x + 2] += quant_error * 7 / 16
            if y + 1 < height:
                if x > 0:
                    errors[next_row_idx][x] += quant_error * 3 / 16
                errors[next_row_idx][x + 1] += quant_error * 5 / 16
                if x + 1 < width:
                    errors[next_row_idx][x + 2] += quant_error * 1 / 16

    # Create HGR screen buffer (8KB)
    screen = bytearray(0x2000)

    # Convert bitmap to HGR format
    # Each byte contains 7 pixels, bit 7 is palette select (set to 0)
    for y in range(192):
        line_addr = get_hgr_line_address(y) - 0x2000  # Offset in buffer

        for byte_x in range(40):
            byte_val = 0
            for bit in range(7):
                x = byte_x * 7 + bit
                if x < 280 and bitmap[y][x]:
                    byte_val |= (1 << bit)
            # Bit 7 = 0 for violet/green palette (can set to 1 for blue/orange)
            screen[line_addr + byte_x] = byte_val

    # Write output file
    with open(output_path, 'wb') as f:
        f.write(screen)

    print(f"Converted: {input_path}")
    print(f"Output: {output_path}")
    print(f"Size: {len(screen)} bytes (8KB)")


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.png> [output.hgr]")
        print()
        print("Converts PNG to Apple II HGR format (280x192, monochrome)")
        print("Output can be BLOADed to $2000 on Apple II")
        sys.exit(1)

    input_path = sys.argv[1]

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        output_path = str(Path(input_path).stem) + '.hgr'

    convert_png_to_hgr(input_path, output_path)


if __name__ == '__main__':
    main()
