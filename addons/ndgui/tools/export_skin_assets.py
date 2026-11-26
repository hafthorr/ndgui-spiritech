#!/usr/bin/env python3
"""Export DarkTech atlas art (buttons, pin, compass, map) into ndgui-lib/assets.

Uses the same generators as skin.py so package PNGs match the former GFX_NDGUI_* pixels.
Green-key RGB atlas images become RGBA with alpha for package:// / library:// use.

Run from the ndgui folder:
  python tools/export_skin_assets.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import skin  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "ndgui-lib", "assets"))
KEY = skin.KEY


def to_rgba(img: Image.Image) -> Image.Image:
    """Atlas art uses pure green as transparency; package images use alpha."""
    if img.mode != "RGB":
        img = img.convert("RGB")
    rgba = Image.new("RGBA", img.size)
    src = img.load()
    dst = rgba.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            p = src[x, y]
            dst[x, y] = (0, 0, 0, 0) if p == KEY else (p[0], p[1], p[2], 255)
    return rgba


def save(img: Image.Image, rel: str) -> None:
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    to_rgba(img).save(path, optimize=True)
    print(rel.replace("/", os.sep))


def main() -> None:
    # Buttons: all heights skin.py knows (forks / layouts may use any of them).
    for h in skin.HEIGHTS:
        for state in ("raised", "hover", "pressed", "selected"):
            for part in ("left", "middle", "right"):
                save(skin.button(h, state, part), f"buttons/btn{h}_{state}_{part}.png")
        save(skin.flat_button((80, h), "selected"), f"buttons/btn{h}_selected.png")

    save(skin.cap((15, 15), skin.glyph_pin, 4), "window/pin_on.png")
    # Titlebar / rollup caps (package BitmapViews; hover stays flat without atlas).
    save(skin.cap((15, 15), skin.glyph_pin, 1), "window/pin.png")
    save(skin.cap((15, 15), skin.glyph_close, 1, True), "window/close.png")
    save(skin.cap((15, 15), skin.glyph_up, 1), "window/fold.png")
    save(skin.cap((15, 15), skin.glyph_down, 1), "window/expand.png")
    save(skin.cap((15, 15), skin.glyph_info, 1), "window/info.png")

    for side in (36, 48, 54):
        save(skin.square_slot((side, side), closed=False), f"slots/open_{side}.png")
        save(skin.square_slot((side, side), closed=True), f"slots/closed_{side}.png")
    # NCU grid cells (Core ncu_slot.xml is 46x30).
    save(skin.square_slot((46, 30), closed=False), "slots/open_46x30.png")
    save(skin.square_slot((46, 30), closed=True), "slots/closed_46x30.png")

    for key, make in skin.COMPASS_SPRITES.items():
        save(make(), f"compass/{key.lower()}.png")

    for key, (size, draw) in skin.MAP_SPRITES.items():
        save(skin.map_sprite(size, draw), f"map/{key.lower()}.png")

    print(f"exported under {OUT}")


if __name__ == "__main__":
    main()
