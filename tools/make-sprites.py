#!/usr/bin/env python3
"""Pack the twelve note illustrations into one atlas for the field.

The field draws a sounding cell as an illustration, chosen by the cell's
column. Twelve marks, one per column, packed 4x3 into a single texture the
fragment shader slices by slot.

Two decisions are baked in here rather than left to the renderer:

Size. As drawn, the marks occupy anywhere from 298 to 501 points of their
600-point canvases — a 1.7x spread. Column is pitch, so drawing them at their
authored sizes would read as an accent pattern that is not in the music. Each
mark is therefore scaled so its own bounding box fills the same share of its
slot, and centred on that box: an off-centre mark visibly wobbles, because it
turns about the middle of its slot.

Order. The file numbers carry no meaning, so the marks are laid out to keep
neighbouring columns apart — no two adjacent columns share a shape family
(rounded petals, spiky rays, concentric discs) or a dominant colour.

    python3 tools/make-sprites.py

No third-party imaging library: PNG in, PNG out, through zlib.
"""

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art" / "notes"
DEST = ROOT / "SQIA" / "Resources" / "Assets.xcassets" / "FlowerAtlas.imageset"

COLUMNS, ROWS = 4, 3
SLOT = 256
# How much of a slot the mark's bounding box fills. The rest is room for the
# bloom, which grows the quad rather than the picture in it.
FILL = 0.90

# Column 0 is the leftmost and lowest note. See the note on order above.
ORDER = ["04", "10", "09", "12", "11", "03", "08", "05", "01", "07", "02", "06"]


def read_png(path):
    data = path.read_bytes()
    width, height, depth, colour = struct.unpack(">IIBB", data[16:26])
    if depth != 8 or colour != 6:
        raise SystemExit(f"{path.name}: expected 8-bit RGBA, got depth {depth} type {colour}")

    idat = b""
    i = 8
    while i < len(data):
        length = struct.unpack(">I", data[i : i + 4])[0]
        if data[i + 4 : i + 8] == b"IDAT":
            idat += data[i + 8 : i + 8 + length]
        i += 12 + length

    raw = zlib.decompress(idat)
    stride = width * 4
    out = bytearray(height * stride)
    previous = bytearray(stride)
    pos = 0
    for y in range(height):
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if filter_type == 1:
            for x in range(4, stride):
                line[x] = (line[x] + line[x - 4]) & 255
        elif filter_type == 2:
            for x in range(stride):
                line[x] = (line[x] + previous[x]) & 255
        elif filter_type == 3:
            for x in range(stride):
                left = line[x - 4] if x >= 4 else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 255
        elif filter_type == 4:
            for x in range(stride):
                a = line[x - 4] if x >= 4 else 0
                c = previous[x - 4] if x >= 4 else 0
                b = previous[x]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                nearest = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + nearest) & 255
        out[y * stride : (y + 1) * stride] = line
        previous = line
    return width, height, out


def write_png(path, width, height, pixels):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride : (y + 1) * stride]

    def chunk(tag, body):
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def bounds(width, height, pixels):
    """The mark's own extent, ignoring what the export left transparent."""
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            if pixels[row + x * 4 + 3] > 8:
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    if max_x < 0:
        raise SystemExit("an illustration is entirely transparent")
    return min_x, min_y, max_x, max_y


def sample(width, height, pixels, x, y):
    """Bilinear, in premultiplied space so a transparent neighbour cannot
    drag colour into the edge of a petal."""
    x = min(max(x, 0.0), width - 1.0)
    y = min(max(y, 0.0), height - 1.0)
    x0, y0 = int(x), int(y)
    x1, y1 = min(x0 + 1, width - 1), min(y0 + 1, height - 1)
    fx, fy = x - x0, y - y0

    out = [0.0, 0.0, 0.0, 0.0]
    for (px, py, weight) in (
        (x0, y0, (1 - fx) * (1 - fy)),
        (x1, y0, fx * (1 - fy)),
        (x0, y1, (1 - fx) * fy),
        (x1, y1, fx * fy),
    ):
        if weight == 0:
            continue
        i = (py * width + px) * 4
        a = pixels[i + 3] / 255
        out[0] += pixels[i] * a * weight
        out[1] += pixels[i + 1] * a * weight
        out[2] += pixels[i + 2] * a * weight
        out[3] += a * weight

    if out[3] <= 1e-6:
        return (0, 0, 0, 0)
    return (
        min(255, round(out[0] / out[3])),
        min(255, round(out[1] / out[3])),
        min(255, round(out[2] / out[3])),
        min(255, round(out[3] * 255)),
    )


def main():
    atlas_w, atlas_h = SLOT * COLUMNS, SLOT * ROWS
    atlas = bytearray(atlas_w * atlas_h * 4)

    for slot, name in enumerate(ORDER):
        path = SOURCE / f"{name}.png"
        width, height, pixels = read_png(path)
        min_x, min_y, max_x, max_y = bounds(width, height, pixels)
        span = max(max_x - min_x + 1, max_y - min_y + 1)
        centre_x = (min_x + max_x) / 2
        centre_y = (min_y + max_y) / 2

        # Source points per destination point, so every mark ends up the same
        # size on screen whatever it was drawn at.
        step = span / (SLOT * FILL)
        ox, oy = (slot % COLUMNS) * SLOT, (slot // COLUMNS) * SLOT

        for y in range(SLOT):
            sy = centre_y + (y - SLOT / 2 + 0.5) * step
            for x in range(SLOT):
                sx = centre_x + (x - SLOT / 2 + 0.5) * step
                r, g, b, a = sample(width, height, pixels, sx, sy)
                i = ((oy + y) * atlas_w + ox + x) * 4
                atlas[i : i + 4] = bytes((r, g, b, a))

        print(f"slot {slot:2d}  {name}.png  {span}px -> {round(SLOT * FILL)}px")

    DEST.mkdir(parents=True, exist_ok=True)
    write_png(DEST / "flower-atlas.png", atlas_w, atlas_h, atlas)
    (DEST / "Contents.json").write_text(
        '{\n'
        '  "images" : [\n'
        '    {\n'
        '      "filename" : "flower-atlas.png",\n'
        '      "idiom" : "universal"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n'
    )
    print(f"wrote {DEST}/flower-atlas.png  {atlas_w}x{atlas_h}")


if __name__ == "__main__":
    main()
