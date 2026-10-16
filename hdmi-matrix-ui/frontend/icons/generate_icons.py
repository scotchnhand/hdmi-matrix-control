#!/usr/bin/env python3
"""One-off, dependency-free PNG icon generator (matches icon.svg's 4-quadrant
design). Run again if you ever want to tweak colors/sizes; the output PNGs are
checked in so this doesn't need to run normally."""

import struct
import zlib
from pathlib import Path

BG = (10, 12, 15)
BLUE = (91, 176, 255)
GRAY = (52, 59, 68)
GREEN = (51, 209, 122)

OUT_DIR = Path(__file__).parent


def rounded_rect_mask(size, x0, y0, x1, y1, radius):
    mask = [[False] * size for _ in range(size)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            # distance to nearest corner, only matters within radius of a corner
            near_left = x < x0 + radius
            near_right = x >= x1 - radius
            near_top = y < y0 + radius
            near_bottom = y >= y1 - radius
            inside = True
            if near_left and near_top:
                cx, cy = x0 + radius, y0 + radius
                inside = (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2
            elif near_right and near_top:
                cx, cy = x1 - radius, y0 + radius
                inside = (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2
            elif near_left and near_bottom:
                cx, cy = x0 + radius, y1 - radius
                inside = (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2
            elif near_right and near_bottom:
                cx, cy = x1 - radius, y1 - radius
                inside = (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2
            if inside:
                mask[y][x] = True
    return mask


def render(size):
    scale = size / 64
    pixels = [[BG for _ in range(size)] for _ in range(size)]

    quadrants = [
        (8, 8, 29, 29, BLUE),
        (35, 8, 56, 29, GRAY),
        (8, 35, 29, 56, GRAY),
        (35, 35, 56, 56, GREEN),
    ]
    for x0, y0, x1, y1, color in quadrants:
        sx0, sy0, sx1, sy1 = (round(v * scale) for v in (x0, y0, x1, y1))
        radius = max(1, round(4 * scale))
        mask = rounded_rect_mask(size, sx0, sy0, sx1, sy1, radius)
        for y in range(sy0, sy1):
            for x in range(sx0, sx1):
                if mask[y][x]:
                    pixels[y][x] = color
    return pixels


def write_png(path, pixels):
    size = len(pixels)
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # no filter
        for (r, g, b) in row:
            raw.extend((r, g, b, 255))

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png = sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')
    path.write_bytes(png)


if __name__ == '__main__':
    for size, name in ((180, 'icon-180.png'), (512, 'icon-512.png')):
        write_png(OUT_DIR / name, render(size))
        print(f'wrote {name}')
