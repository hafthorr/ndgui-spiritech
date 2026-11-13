"""Generate the original ndGUI art kit into ndgui-lib/assets.

Run: python tools/make_art.py [theme]   (from the ndgui folder; default: darktech)
Everything is drawn procedurally from the theme palette below; no stock texture is sampled.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "ndgui-lib", "assets"))

# Palettes mirror theme.lua. DarkTech: near-black navy, steel-blue pronounced frame, blue accent, matte bars.
PALETTES = {
    "darktech": {
        "panel": "#0e141b", "panel_alt": "#16202a", "border": "#3d6f9a", "border_dark": "#1c3248",
        "accent": "#3d8fd4", "focus": "#6cb6ff", "track": "#080c10", "menu": "#0a1016",
        "health": "#c44747", "nano": "#2f7ec4", "xp": "#c6a24e", "alien": "#4f9a52",
    },
}
T = PALETTES[sys.argv[1] if len(sys.argv) > 1 else "darktech"]


def rgb(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(4))


def shade(h, k, a=255):
    """k > 0 lightens toward white, k < 0 darkens toward black."""
    c = rgb(h, a)
    return mix(c, (255, 255, 255, a), k) if k > 0 else mix(c, (0, 0, 0, a), -k)


def save(img, rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print(rel.replace("/", os.sep))


def gradient(size, stops, axis):
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    n = h if axis == "y" else w
    for i in range(n):
        t = i / max(1, n - 1)
        for k in range(len(stops) - 1):
            t0, c0 = stops[k]
            t1, c1 = stops[k + 1]
            if t0 <= t <= t1:
                c = mix(c0, c1, (t - t0) / max(1e-9, t1 - t0))
                break
        for j in range(w if axis == "y" else h):
            px[(j, i) if axis == "y" else (i, j)] = c
    return img


def bands(size, colors, axis):
    """Solid 1px bands across the thin axis (frame edges)."""
    w, h = size
    img = Image.new("RGBA", size)
    d = ImageDraw.Draw(img)
    for i, c in enumerate(colors):
        if axis == "y":
            d.line([0, i, w, i], fill=c)
        else:
            d.line([i, 0, i, h], fill=c)
    return img


# ---- Bars: matte, flat, faint segment ticks ----------------------------------
def bar_fill(key, size, axis):
    base = T[key]
    across = "y" if axis == "h" else "x"
    img = gradient(size, [(0.0, shade(base, 0.18)), (0.5, rgb(base)), (1.0, shade(base, -0.35))], across)
    d = ImageDraw.Draw(img)
    w, h = size
    if axis == "h":
        d.line([0, 0, w, 0], fill=shade(base, 0.35, 200))
        for x in range(24, w, 24):
            d.line([x, 0, x, h], fill=(0, 0, 0, 60))
    else:
        d.line([0, 0, 0, h], fill=shade(base, 0.35, 200))
        for y in range(24, h, 24):
            d.line([0, y, w, y], fill=(0, 0, 0, 60))
    return img


def bar_track(size, axis):
    w, h = size
    img = Image.new("RGBA", size, rgb(T["track"], 235))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=rgb(T["border_dark"]))
    return img


# ---- Chrome -----------------------------------------------------------------
def strip(size):
    w, h = size
    img = gradient(size, [(0.0, rgb(T["panel_alt"], 245)), (1.0, rgb(T["menu"], 250))], "y")
    d = ImageDraw.Draw(img)
    d.line([0, 0, w, 0], fill=rgb("#000000", 255))
    d.line([0, 1, w, 1], fill=rgb(T["border"], 255))
    d.line([0, 2, w, 2], fill=rgb(T["border_dark"], 255))
    return img


def plate(size):
    w, h = size
    img = Image.new("RGBA", size, rgb(T["panel"], 225))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=rgb(T["border"], 220))
    d.rectangle([1, 1, w - 2, h - 2], outline=rgb(T["border_dark"], 220))
    return img


# ---- Window frame (pronounced 3px steel frame, square corners) ---------------
EDGE = [rgb("#000000", 255), rgb(T["border"], 255), rgb(T["border_dark"], 255)]


def window_glass(size):
    return gradient(size, [(0.0, rgb(T["panel_alt"], 236)), (0.08, rgb(T["panel"], 236)), (1.0, shade(T["panel"], -0.3, 242))], "y")


def window_inner(size):
    img = Image.new("RGBA", size, rgb(T["track"], 150))
    return img


def titlebar(size):
    """Raised steel titlebar: lit top edge, deep gradient, blue rule + black line underneath."""
    w, h = size
    img = gradient(size, [(0.0, shade(T["panel_alt"], 0.14, 252)), (0.55, rgb(T["panel_alt"], 252)), (1.0, rgb(T["panel"], 252))], "y")
    d = ImageDraw.Draw(img)
    d.line([0, 3, w, 3], fill=shade(T["border_dark"], 0.25))
    d.line([0, h - 2, w, h - 2], fill=rgb(T["accent"], 255))
    d.line([0, h - 1, w, h - 1], fill=rgb("#000000"))
    return img


def corner(size=7):
    """Small solid accent notch inside each square corner (DarkTech rivet)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size - 1, 2], fill=rgb(T["accent"]))
    d.rectangle([0, 0, 2, size - 1], fill=rgb(T["accent"]))
    return img


def tab(size):
    """Recessed title slot (no vertical edges, so it stretches cleanly to any title width)."""
    w, h = size
    img = gradient(size, [(0.0, rgb("#05080b", 255)), (1.0, rgb(T["track"], 255))], "y")
    d = ImageDraw.Draw(img)
    d.line([0, 0, w, 0], fill=rgb("#000000"))
    d.line([0, h - 1, w, h - 1], fill=rgb(T["border_dark"]))
    return img


def accent_bar(size):
    """Blue cap on the left of the title slot."""
    w, h = size
    img = gradient(size, [(0.0, rgb(T["focus"])), (1.0, shade(T["accent"], -0.3))], "y")
    d = ImageDraw.Draw(img)
    d.line([0, 0, w, 0], fill=rgb("#000000"))
    d.line([0, h - 1, w, h - 1], fill=rgb("#000000"))
    return img


# ---- Target health (neutral, tinted at runtime by the native con colour) -------
def target_fill(size):
    w, h = size
    img = gradient(size, [(0.0, rgb("#ffffff")), (0.5, rgb("#d8dde2")), (1.0, rgb("#8c949b"))], "y")
    d = ImageDraw.Draw(img)
    for x in range(24, w, 24):
        d.line([x, 0, x, h], fill=(0, 0, 0, 50))
    return img


# ---- Shortcut bars ----------------------------------------------------------
HOT_CELL = 36           # one shortcut cell
HOT_PAD = 4             # plate frame + inner padding
HOT_LONG = 398          # 4 + 6 active + 2 + 20 spinner + 2 + 360 slots + 4
HOT_SHORT = 44


def hot_slot(size=HOT_CELL):
    """Recessed well: dark core, shadowed top-left, faint lit bottom-right, blue corner tick."""
    s = size
    img = Image.new("RGBA", (s, s), rgb(T["track"], 245))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, s - 1, s - 1], outline=rgb("#000000"))
    d.rectangle([1, 1, s - 2, s - 2], outline=rgb(T["border_dark"]))
    d.line([2, 2, s - 3, 2], fill=rgb("#000000", 200))
    d.line([2, 2, 2, s - 3], fill=rgb("#000000", 200))
    d.line([3, s - 3, s - 3, s - 3], fill=rgb(T["panel_alt"]))
    d.line([s - 3, 3, s - 3, s - 3], fill=rgb(T["panel_alt"]))
    d.line([1, 1, 5, 1], fill=rgb(T["accent"], 220))
    d.line([1, 1, 1, 5], fill=rgb(T["accent"], 220))
    return img


def hot_plate(size):
    """Whole-bar backplate: window glass + 3px steel frame + blue corner notches."""
    w, h = size
    axis = "y" if w >= h else "x"
    img = gradient(size, [(0.0, rgb(T["panel_alt"], 238)), (1.0, shade(T["panel"], -0.3, 242))], axis)
    d = ImageDraw.Draw(img)
    for i, c in enumerate(EDGE):
        d.rectangle([i, i, w - 1 - i, h - 1 - i], outline=c)
    notch = corner(6)
    for flip, (x, y) in ((None, (3, 3)), (Image.FLIP_LEFT_RIGHT, (w - 9, 3)),
                         (Image.FLIP_TOP_BOTTOM, (3, h - 9)), (Image.ROTATE_180, (w - 9, h - 9))):
        n = notch if flip is None else notch.transpose(flip)
        img.alpha_composite(n, (x, y))
    return img


def hot_active(size, on):
    """Active-bar indicator: lit blue rail when this bar owns the 1-0 keys, dim slot otherwise."""
    w, h = size
    axis = "x" if h >= w else "y"
    if on:
        img = gradient(size, [(0.0, shade(T["focus"], 0.2)), (0.5, rgb(T["accent"])), (1.0, shade(T["accent"], -0.4))], axis)
    else:
        img = Image.new("RGBA", size, rgb(T["track"], 245))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=rgb("#000000"))
    return img


def spinner(size):
    w, h = size
    img = Image.new("RGBA", size, rgb(T["track"], 200))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=rgb("#000000"))
    d.rectangle([1, 1, w - 2, h - 2], outline=rgb(T["border_dark"]))
    return img


def main():
    for key, name in (("health", "hp"), ("nano", "np"), ("xp", "xp"), ("alien", "axp")):
        save(bar_fill(key, (256, 16), "h"), f"bars/{name}_h.png")
        save(bar_fill(key, (16, 256), "v"), f"bars/{name}_v.png")
    save(bar_track((256, 16), "h"), "bars/track_h.png")
    save(bar_track((16, 256), "v"), "bars/track_v.png")
    save(strip((64, 26)), "chrome/strip.png")
    save(plate((128, 32)), "chrome/plate.png")
    save(window_glass((128, 128)), "window/glass.png")
    save(window_inner((64, 64)), "window/inner.png")
    save(titlebar((64, 26)), "window/titlebar.png")
    save(bands((64, 3), EDGE, "y"), "window/edge_top.png")
    save(bands((64, 3), list(reversed(EDGE)), "y"), "window/edge_h.png")
    save(bands((3, 64), EDGE, "x"), "window/edge_v.png")
    save(bands((3, 64), list(reversed(EDGE)), "x"), "window/edge_v_r.png")
    tl = corner()
    save(tl, "window/corner_tl.png")
    save(tl.transpose(Image.FLIP_LEFT_RIGHT), "window/corner_tr.png")
    save(tl.transpose(Image.FLIP_TOP_BOTTOM), "window/corner_bl.png")
    save(tl.transpose(Image.ROTATE_180), "window/corner_br.png")
    save(tab((64, 17)), "window/tab.png")
    save(accent_bar((3, 18)), "window/accent.png")
    save(target_fill((256, 10)), "bars/target_h.png")
    save(bar_track((256, 10), "h"), "bars/track_thin.png")
    save(hot_slot(), "hotbar/slot.png")
    save(hot_plate((HOT_LONG, HOT_SHORT)), "hotbar/plate_h.png")
    save(hot_plate((HOT_SHORT, HOT_LONG)), "hotbar/plate_v.png")
    save(hot_active((6, HOT_CELL), True), "hotbar/active_on_h.png")
    save(hot_active((6, HOT_CELL), False), "hotbar/active_off_h.png")
    save(hot_active((HOT_CELL, 6), True), "hotbar/active_on_v.png")
    save(hot_active((HOT_CELL, 6), False), "hotbar/active_off_v.png")
    save(spinner((20, HOT_CELL)), "hotbar/spinner_h.png")
    save(spinner((HOT_CELL, 20)), "hotbar/spinner_v.png")


if __name__ == "__main__":
    main()
