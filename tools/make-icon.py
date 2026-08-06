#!/usr/bin/env python3
"""Render the app icon at App Store size from the web app's icon.svg.

The icon is a black square and sixteen circles, so rather than depend on an
SVG rasteriser this draws the circles directly — supersampled 4x and scaled
down, which gives cleaner edges than most rasterisers manage on shapes this
small. The geometry is copied from funny-steps/public/icon.svg; keep the two
in step if the mark ever changes.

    python3 tools/make-icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

VIEWBOX = 120
SIZE = 1024
SS = 4  # supersampling factor

BACKGROUND = (0, 0, 0)
DEFAULT_FILL = "#d9d9d9"

# cx, cy, r, fill — straight from icon.svg
CIRCLES = [
    (30, 32, 7, None),
    (53, 32, 7, None),
    (75, 32, 3, None),
    (96, 32, 7, None),
    (32, 56, 4, None),
    (54, 56, 4, None),
    (75, 56, 2.4, "#8a8a8a"),
    (94, 56, 2.4, "#8a8a8a"),
    (34, 76, 2.4, "#7a7a7a"),
    (55, 76, 2.4, "#7a7a7a"),
    (75, 76, 2.4, "#6d6d6d"),
    (92, 76, 2.4, "#6d6d6d"),
    (36, 93, 1.8, "#5c5c5c"),
    (56, 93, 1.8, "#5c5c5c"),
    (75, 93, 1.8, "#5c5c5c"),
    (90, 93, 1.8, "#5c5c5c"),
]


def render(size: int) -> Image.Image:
    canvas = size * SS
    scale = canvas / VIEWBOX
    image = Image.new("RGB", (canvas, canvas), BACKGROUND)
    draw = ImageDraw.Draw(image)
    for cx, cy, r, fill in CIRCLES:
        x, y, radius = cx * scale, cy * scale, r * scale
        draw.ellipse(
            [x - radius, y - radius, x + radius, y + radius],
            fill=fill or DEFAULT_FILL,
        )
    return image.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / (
        "SQIA/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    render(SIZE).save(out)
    print(f"wrote {out} ({SIZE}x{SIZE})")
