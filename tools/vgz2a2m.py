#!/usr/bin/env python3
"""
VGZ to A2M Converter
Converts VGZ (compressed VGM) files to Apple II Mockingboard format (.a2m)

VGM Commands handled:
  0xA0 rr dd - AY-3-8910 write register rr with data dd
  0x61 nn nn - Wait n samples (44100Hz)
  0x62       - Wait 735 samples (1/60 sec)
  0x63       - Wait 882 samples (1/50 sec)
  0x66       - End of data

A2M Output Format:
  Header (16 bytes):
    0-3:  Magic "A2M\x00"
    4-5:  Data length (little-endian)
    6-7:  Loop offset (little-endian, 0=no loop)
    8-15: Reserved

  Data Stream:
    $00-$0D vv : Write value vv to register $00-$0D
    $80-$FE    : Wait 1-127 frames (60Hz)
    $FF nn nn  : Wait nn*256 frames (extended wait)
    $FE        : End of song
    $FD        : Loop start marker
"""

import gzip
import struct
import sys
import os
from pathlib import Path

# VGM command bytes
CMD_AY8910 = 0xA0
CMD_WAIT_N = 0x61
CMD_WAIT_60HZ = 0x62
CMD_WAIT_50HZ = 0x63
CMD_END = 0x66

# A2M special bytes
A2M_END = 0xFE
A2M_LOOP = 0xFD
A2M_WAIT_EXT = 0xFF

# Samples per frame at 60Hz (44100 / 60 = 735)
SAMPLES_PER_FRAME = 735


def read_vgz(filename):
    """Read and decompress VGZ file, return VGM data"""
    with gzip.open(filename, 'rb') as f:
        return f.read()


def read_vgm(filename):
    """Read VGM file directly"""
    with open(filename, 'rb') as f:
        return f.read()


def parse_vgm_header(data):
    """Parse VGM header and return data offset and loop info"""
    if data[0:4] != b'Vgm ':
        raise ValueError("Not a valid VGM file")

    # Version (offset 0x08)
    version = struct.unpack_from('<I', data, 0x08)[0]

    # Loop offset (offset 0x1C) - relative to 0x1C
    loop_offset_raw = struct.unpack_from('<I', data, 0x1C)[0]
    loop_offset = (0x1C + loop_offset_raw) if loop_offset_raw else 0

    # Data offset (offset 0x34 for version >= 1.50, else 0x40)
    if version >= 0x150:
        data_offset_raw = struct.unpack_from('<I', data, 0x34)[0]
        data_offset = 0x34 + data_offset_raw if data_offset_raw else 0x40
    else:
        data_offset = 0x40

    return data_offset, loop_offset


def convert_vgm_to_a2m(vgm_data):
    """Convert VGM data stream to A2M format"""
    data_offset, loop_offset = parse_vgm_header(vgm_data)

    a2m_data = bytearray()
    pending_samples = 0
    pos = data_offset
    a2m_loop_offset = 0

    def flush_wait():
        """Flush accumulated wait samples as frames"""
        nonlocal pending_samples
        if pending_samples == 0:
            return

        frames = pending_samples // SAMPLES_PER_FRAME
        pending_samples = pending_samples % SAMPLES_PER_FRAME

        while frames > 0:
            if frames <= 127:
                # Single byte wait: $80-$FE = 1-127 frames
                a2m_data.append(0x7F + frames)
                frames = 0
            elif frames <= 65535:
                # Extended wait: $FF nn nn
                wait = min(frames, 65535)
                a2m_data.append(A2M_WAIT_EXT)
                a2m_data.append(wait & 0xFF)
                a2m_data.append((wait >> 8) & 0xFF)
                frames -= wait
            else:
                # Very long wait - split
                a2m_data.append(A2M_WAIT_EXT)
                a2m_data.append(0xFF)
                a2m_data.append(0xFF)
                frames -= 65535

    while pos < len(vgm_data):
        # Check for loop point
        if loop_offset and pos == loop_offset and a2m_loop_offset == 0:
            flush_wait()
            a2m_loop_offset = len(a2m_data)
            a2m_data.append(A2M_LOOP)

        cmd = vgm_data[pos]

        if cmd == CMD_AY8910:
            # AY-3-8910 write: A0 rr dd
            if pos + 2 >= len(vgm_data):
                break
            reg = vgm_data[pos + 1]
            val = vgm_data[pos + 2]

            # Only handle registers 0-13 (0x00-0x0D)
            if reg <= 0x0D:
                flush_wait()
                a2m_data.append(reg)
                a2m_data.append(val)
            pos += 3

        elif cmd == CMD_WAIT_N:
            # Wait n samples: 61 nn nn
            if pos + 2 >= len(vgm_data):
                break
            samples = struct.unpack_from('<H', vgm_data, pos + 1)[0]
            pending_samples += samples
            pos += 3

        elif cmd == CMD_WAIT_60HZ:
            # Wait 735 samples (1/60 sec)
            pending_samples += 735
            pos += 1

        elif cmd == CMD_WAIT_50HZ:
            # Wait 882 samples (1/50 sec)
            pending_samples += 882
            pos += 1

        elif cmd == CMD_END:
            # End of data
            flush_wait()
            a2m_data.append(A2M_END)
            break

        elif 0x70 <= cmd <= 0x7F:
            # Short wait: 0x70-0x7F = wait n+1 samples
            pending_samples += (cmd & 0x0F) + 1
            pos += 1

        elif 0x80 <= cmd <= 0x8F:
            # YM2612 sample with wait - just handle the wait part
            pending_samples += cmd & 0x0F
            pos += 1

        else:
            # Unknown/unsupported command - try to skip
            # Common 2-byte commands
            if cmd in (0x30, 0x3F, 0x4F, 0x50, 0xB0, 0xB1, 0xB2):
                pos += 2
            # Common 3-byte commands
            elif cmd in (0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
                        0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0xA1, 0xA2, 0xA3,
                        0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB,
                        0xBC, 0xBD, 0xBE, 0xBF):
                pos += 3
            # 4-byte commands
            elif cmd in (0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8):
                pos += 4
            # Data block
            elif cmd == 0x67:
                if pos + 6 < len(vgm_data):
                    block_size = struct.unpack_from('<I', vgm_data, pos + 3)[0]
                    pos += 7 + block_size
                else:
                    pos += 1
            else:
                # Skip unknown single-byte command
                pos += 1

    # Ensure we have an end marker
    if not a2m_data or a2m_data[-1] != A2M_END:
        a2m_data.append(A2M_END)

    return bytes(a2m_data), a2m_loop_offset


def create_a2m_file(a2m_data, loop_offset):
    """Create A2M file with header"""
    header = bytearray(16)

    # Magic
    header[0:4] = b'A2M\x00'

    # Data length (little-endian)
    data_len = len(a2m_data)
    header[4] = data_len & 0xFF
    header[5] = (data_len >> 8) & 0xFF

    # Loop offset (little-endian)
    header[6] = loop_offset & 0xFF
    header[7] = (loop_offset >> 8) & 0xFF

    return bytes(header) + a2m_data


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.vgz|input.vgm> [output.a2m]")
        print()
        print("Converts VGZ/VGM files to Apple II Mockingboard format (.a2m)")
        sys.exit(1)

    input_file = sys.argv[1]

    # Determine output filename
    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    else:
        output_file = str(Path(input_file).stem) + '.a2m'

    print(f"Converting: {input_file}")

    # Read input file
    try:
        if input_file.lower().endswith('.vgz') or input_file.lower().endswith('.gz'):
            vgm_data = read_vgz(input_file)
        else:
            vgm_data = read_vgm(input_file)
    except Exception as e:
        print(f"Error reading input file: {e}")
        sys.exit(1)

    # Convert
    try:
        a2m_data, loop_offset = convert_vgm_to_a2m(vgm_data)
    except Exception as e:
        print(f"Error converting: {e}")
        sys.exit(1)

    # Create output file
    output_data = create_a2m_file(a2m_data, loop_offset)

    with open(output_file, 'wb') as f:
        f.write(output_data)

    print(f"Output: {output_file}")
    print(f"  Data size: {len(a2m_data)} bytes")
    print(f"  Loop offset: {loop_offset if loop_offset else 'none'}")
    print("Done!")


if __name__ == '__main__':
    main()
