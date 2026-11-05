#!/usr/bin/env python3
"""Bake the shared value-noise lattice used by landscape shaders, without PIL.

The shader retains its original cubic interpolation, scales, octaves and colors.
One bilinear texture fetch replaces four trigonometric hashes per noise sample.
"""
from pathlib import Path
import math
import struct
import zlib

def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

def main() -> None:
    size = 256
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            value = math.sin(x * 127.1 + y * 311.7) * 43758.5453123
            rows.append(round((value - math.floor(value)) * 255))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    output = Path(__file__).resolve().parents[1] / "assets/environment_v11/landscape_noise_v131.png"
    output.write_bytes(png)
    print(f"Wrote {output}: {size}x{size} grayscale, {len(png)} bytes")

if __name__ == "__main__":
    main()
