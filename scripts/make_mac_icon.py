"""Draws the Mac app icon set for the App Store target: the picture of scripts/make_ios_icon.py as a rounded
square inside the margin macOS icons keep (the same layout as scripts/MakeIcon.swift), at the ten sizes of an
AppIcon.appiconset. Needs Pillow.

Usage: python scripts/make_mac_icon.py <AppIcon.appiconset folder>
"""

import io
import json
import os
import sys

from PIL import Image

from make_ios_icon import DESIGN, draw

# The square is 824 of 1024 pixels with corners of 185 in a square of that size.
SQUARE = 824
CORNER = 185 / SQUARE * DESIGN
SIZES = (16, 32, 128, 256, 512)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python scripts/make_mac_icon.py <AppIcon.appiconset folder>")
    folder = sys.argv[1]
    os.makedirs(folder, exist_ok=True)
    art = Image.open(io.BytesIO(draw(int(DESIGN), corner=CORNER))).convert("RGBA")
    art = art.resize((SQUARE, SQUARE), Image.LANCZOS)
    master = Image.new("RGBA", (int(DESIGN), int(DESIGN)), (0, 0, 0, 0))
    margin = (int(DESIGN) - SQUARE) // 2
    master.paste(art, (margin, margin))

    images = []
    for size in SIZES:
        for scale in (1, 2):
            pixels = size * scale
            name = "icon_%dx%d%s.png" % (size, size, "@2x" if scale == 2 else "")
            master.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(folder, name))
            images.append({"filename": name, "idiom": "mac", "scale": "%dx" % scale, "size": "%dx%d" % (size, size)})
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8", newline="\n") as out:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, out, indent=2)
        out.write("\n")
    print("wrote %d icons to %s" % (len(images), folder))


if __name__ == "__main__":
    main()
