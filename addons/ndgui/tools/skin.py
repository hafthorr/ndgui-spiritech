"""ndGUI skin atlas: DarkTech square buttons (+ optional teal->steel retint) in the GUI skin.

Run from the ndgui folder:
  python tools/skin.py            build: stock atlas + GFX_NDGUI_* entries + retint
  python tools/skin.py --no-retint  only add the GFX_NDGUI_* entries
  python tools/skin.py --restore  put the untouched stock atlas back
  python tools/skin.py --preview DIR  write the generated art + a retint sheet to DIR, touch nothing

The skin lives in client/cd_image/gui/Default: Graphics.uvgi is "<count>" then one
"NAME offset length" line per graphic; Graphics.uvga is those PNGs back to back.
Pure green (0,255,0) is the transparency key, so all art here is RGB with a green key.
The first build copies the originals to *.stock; every build starts from *.stock, so it is
repeatable, and --restore is exact. Re-run after a client update replaces the skin.
"""
import colorsys, io, os, re, shutil, subprocess, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SKIN = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "cd_image", "gui", "Default"))
UVGI, UVGA = os.path.join(SKIN, "Graphics.uvgi"), os.path.join(SKIN, "Graphics.uvga")
COLORS = os.path.join(SKIN, "GUIColors.xml")
# GUIColors "Default" tints stock chrome (rollups, frames); stock is cyan 0x0080e9f3.
GUI_COLORS = {"Default": "0x00a9c4d8", "Selected": "0x00d6e8f5", "Hover": "0x006cb6ff",
              "Text": "0x00c5d7e6", "TextSelected": "0x00ffffff", "TextHover": "0x006cb6ff"}
KEY = (0, 255, 0)

C = {
    "black": (0, 0, 0), "edge": (0x3D, 0x6F, 0x9A), "edge_dark": (0x1C, 0x32, 0x48),
    "top": (0x1D, 0x2A, 0x37), "fill": (0x12, 0x1A, 0x23), "low": (0x0A, 0x10, 0x16),
    "accent": (0x3D, 0x8F, 0xD4), "focus": (0x6C, 0xB6, 0xFF), "sunk": (0x07, 0x0B, 0x0F),
}
# Every labelled-button height used by the stock + ndGUI layouts (others fall back to 28).
HEIGHTS = (19, 20, 22, 23, 24, 26, 28, 32)
CAP = 4  # left/right slice width


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def button(h, state, part):
    """One slice of a square DarkTech button. part: left|middle|right."""
    w = CAP if part != "middle" else 16
    img = Image.new("RGB", (w, h))
    px = img.load()
    hi, lo = {"raised": (C["top"], C["low"]), "hover": (lerp(C["top"], C["edge"], .35), C["fill"]),
              "pressed": (C["sunk"], C["low"]), "selected": (lerp(C["top"], C["accent"], .45), C["fill"])}[state]
    for y in range(h):
        c = lerp(hi, lo, y / max(1, h - 1))
        for x in range(w):
            px[x, y] = c
    d = ImageDraw.Draw(img)
    frame = C["focus"] if state == "hover" else C["accent"] if state == "selected" else C["edge"]
    # Even frame on all four sides (reads at 150-200% interface scale): black outline, steel
    # line, faint inner bevel; square corners, blue DarkTech tick top-left.
    inner = lerp(frame, hi, .65)
    d.line([0, 0, w, 0], fill=C["black"])
    d.line([0, h - 1, w, h - 1], fill=C["black"])
    d.line([0, 1, w, 1], fill=frame)
    d.line([0, h - 2, w, h - 2], fill=frame)
    d.line([0, 2, w, 2], fill=C["black"] if state == "pressed" else inner)
    if part == "left":
        d.line([0, 0, 0, h], fill=C["black"])
        d.line([1, 1, 1, h - 2], fill=frame)
        d.line([2, 2, 2, h - 3], fill=C["black"] if state == "pressed" else inner)
        d.rectangle([2, 2, 3, 3], fill=C["focus"] if state != "pressed" else C["accent"])
    if part == "right":
        d.line([w - 1, 0, w - 1, h], fill=C["black"])
        d.line([w - 2, 1, w - 2, h - 2], fill=frame)
    return img


# ---- local map markers (GFX_NDGUI_MAP_*; drawn crisp, black outline, green key) ----
def map_sprite(size, draw):
    img = Image.new("RGB", (size, size), KEY)
    draw(ImageDraw.Draw(img), size)
    return img


def diamond(fill, outline=(0, 0, 0)):
    def draw(d, s):
        m = (s - 1) / 2
        d.polygon([(m, 0), (s - 1, m), (m, s - 1), (0, m)], fill=fill, outline=outline)
    return draw


def square(fill, outline=(0, 0, 0)):
    def draw(d, s):
        d.rectangle([0, 0, s - 1, s - 1], fill=fill, outline=outline)
    return draw


def dot(fill):
    def draw(d, s):
        d.ellipse([0, 0, s - 1, s - 1], fill=fill, outline=(0, 0, 0) if s > 3 else None)
    return draw


def arrow(fill, edge):
    """Points up (-y); the surface rotates it by the marker facing."""
    def draw(d, s):
        m = (s - 1) / 2
        d.polygon([(m, 0), (s - 1, s - 1), (m, s * .68), (0, s - 1)], fill=fill, outline=edge)
    return draw


def reticle(d, s):
    m = s // 2
    c = (0xC5, 0xD7, 0xE6)
    for a, b in (((0, m), (m - 2, m)), ((m + 2, m), (s - 1, m)), ((m, 0), (m, m - 2)), ((m, m + 2), (m, s - 1))):
        d.line([a, b], fill=c)
    d.point((m, m), fill=C["focus"])


def beacon(d, s):
    """Waypoint: gold target ring with a bright core (rotation-invariant)."""
    g = (0xE8, 0xC0, 0x5A)
    d.ellipse([0, 0, s - 1, s - 1], fill=KEY, outline=(0, 0, 0))
    d.ellipse([1, 1, s - 2, s - 2], fill=KEY, outline=g)
    d.ellipse([2, 2, s - 3, s - 3], fill=KEY, outline=(0, 0, 0))
    m = s // 2
    d.rectangle([m - 2, m - 2, m + 2, m + 2], fill=(0, 0, 0))
    d.rectangle([m - 1, m - 1, m + 1, m + 1], fill=(0xFF, 0xE6, 0x9A))


def beacon_you(d, s):
    """Planet map 'you': blue ring with a white core."""
    b = C["focus"]
    d.ellipse([0, 0, s - 1, s - 1], fill=KEY, outline=(0, 0, 0))
    d.ellipse([1, 1, s - 2, s - 2], fill=KEY, outline=b)
    d.ellipse([2, 2, s - 3, s - 3], fill=KEY, outline=(0, 0, 0))
    m = s // 2
    d.rectangle([m - 2, m - 2, m + 2, m + 2], fill=(0, 0, 0))
    d.rectangle([m - 1, m - 1, m + 1, m + 1], fill=(0xFF, 0xFF, 0xFF))


def coin(d, s):
    d.ellipse([0, 0, s - 1, s - 1], fill=(0xC6, 0xA2, 0x4E), outline=(0, 0, 0))


MAP_SPRITES = {
    # Sizes are small on purpose: the surface scales sprites with map zoom and UI scale.
    "PLAYER": (13, arrow(C["focus"], (0xFF, 0xFF, 0xFF))),
    "MARKED": (15, beacon),
    "YOU": (15, beacon_you),
    "ROUTE": (2, square((0xE8, 0xC0, 0x5A), None)),
    "SELECTED": (9, arrow((0xFF, 0xFF, 0xFF), (0, 0, 0))),
    "MONSTER": (5, diamond((0xD2, 0x4B, 0x4B))),
    "TEAM": (7, diamond((0x5F, 0xD0, 0x6A))),
    "CLAN": (3, square((0xE0, 0x8A, 0x3A), None)),
    "OMNI": (3, square((0x4F, 0x9A, 0xE8), None)),
    "NEUTRAL": (3, square((0xB8, 0xC4, 0xCC), None)),
    "DOOR": (4, square((0x6C, 0xB6, 0xFF), (0x0A, 0x10, 0x16))),
    "SHOP": (7, coin),
    "MISSION": (7, diamond((0x3D, 0xE0, 0xD0))),
    "TRAIL": (2, dot((0x6C, 0xB6, 0xFF))),
    "TRAIL_NEW": (3, dot((0xC5, 0xE2, 0xFF))),
    "RING": (2, square((0x6C, 0xB6, 0xFF), None)),
    "RETICLE": (9, reticle),
}


def generated():
    out = {}
    for key, (size, draw) in MAP_SPRITES.items():
        out["GFX_GUI_NDGUI_MAP_" + key] = map_sprite(size, draw)
    for h in HEIGHTS:
        for state in ("raised", "hover", "pressed", "selected"):
            for part in ("left", "middle", "right"):
                out[f"GFX_NDGUI_BTN{h}_{state.upper()}_{part.upper()}"] = button(h, state, part)
        out[f"GFX_NDGUI_BTN{h}_SELECTED"] = flat_button((80, h), "selected")
    # Pinned window: lit blue key (core.window shows it via ui.selected -> gfxid_selected).
    out["GFX_NDGUI_PIN_ON"] = cap((15, 15), glyph_pin, 4)
    return out


# ---- square replacements for rounded stock frames ---------------------------
def square_slot(size, closed):
    """Item/slot frame: square 3-line DarkTech frame; OPEN keeps a see-through (key) centre."""
    w, h = size
    img = Image.new("RGB", size, C["sunk"] if closed else KEY)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=C["black"])
    d.rectangle([1, 1, w - 2, h - 2], outline=C["edge_dark"])
    d.line([2, 2, w - 3, 2], fill=C["black"])
    d.line([2, 2, 2, h - 3], fill=C["black"])
    k = 3 if min(w, h) >= 20 else 2
    d.line([1, 1, k + 1, 1], fill=C["accent"])
    d.line([1, 1, 1, k + 1], fill=C["accent"])
    return img


GLYPH = (0xC5, 0xD7, 0xE6)


def glyph_close(d, s):
    w = s // 7
    d.line([s * .3, s * .3, s * .7, s * .7], fill=GLYPH, width=w)
    d.line([s * .7, s * .3, s * .3, s * .7], fill=GLYPH, width=w)


def glyph_pin(d, s):
    w = s // 8
    d.rectangle([s * .38, s * .22, s * .62, s * .5], fill=GLYPH)
    d.line([s * .28, s * .5, s * .72, s * .5], fill=GLYPH, width=w)
    d.line([s * .5, s * .5, s * .5, s * .8], fill=GLYPH, width=w)


def glyph_info(d, s):
    d.rectangle([s * .44, s * .22, s * .56, s * .32], fill=C["focus"])
    d.rectangle([s * .44, s * .4, s * .56, s * .78], fill=C["focus"])


def glyph_up(d, s):
    d.polygon([(s * .5, s * .33), (s * .74, s * .66), (s * .26, s * .66)], fill=GLYPH)


def glyph_down(d, s):
    d.polygon([(s * .26, s * .36), (s * .74, s * .36), (s * .5, s * .69)], fill=GLYPH)


def glyph_max(d, s):
    w = s // 9
    d.rectangle([s * .28, s * .28, s * .72, s * .72], outline=GLYPH, width=w)
    d.rectangle([s * .28, s * .28, s * .72, s * .36], fill=GLYPH)


def glyph_help(d, s):
    w = s // 8
    d.arc([s * .32, s * .2, s * .68, s * .52], 200, 90, fill=GLYPH, width=w)
    d.line([s * .5, s * .5, s * .5, s * .62], fill=GLYPH, width=w)
    d.rectangle([s * .44, s * .7, s * .56, s * .8], fill=GLYPH)


def cap(size, glyph, state, danger=False):
    """15px DarkTech titlebar cap: square steel-framed key with a crisp glyph (drawn 8x)."""
    w, h = size
    k = 8
    big = Image.new("RGB", (w * k, h * k))
    d = ImageDraw.Draw(big)
    top, low = {4: (lerp(C["accent"], C["focus"], .3), lerp(C["accent"], C["low"], .45)), 1: (C["top"], C["low"]), 2: (lerp(C["top"], (0x8A, 0x2A, 0x2A) if danger else C["edge"], .45), C["fill"]),
                3: (C["sunk"], C["low"])}[state]
    for y in range(h * k):
        d.line([0, y, w * k, y], fill=lerp(top, low, y / (h * k - 1)))
    glyph(d, w * k)
    img = big.resize((w, h), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    frame = (C["focus"] if not danger else (0xD0, 0x5A, 0x5A)) if state in (2, 4) else C["edge"]
    d.rectangle([0, 0, w - 1, h - 1], outline=C["black"])
    d.rectangle([1, 1, w - 2, h - 2], outline=frame if state != 3 else C["edge_dark"])
    return img


FONT_BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
NANO_LABELS = {"FAVOURITES": "Favorites", "COMBAT": "Combat", "MEDICAL": "Medical", "PROT": "Prot", "PSI": "Psi", "SPACE": "Space"}


def flat_button(size, state):
    """Whole (non-sliced) square button face, same look as the GFX_NDGUI_BTN slices."""
    w, h = size
    img = Image.new("RGB", size)
    img.paste(button(h, state, "left"), (0, 0))
    mid = button(h, state, "middle")
    for x in range(CAP, w - CAP, mid.width):
        img.paste(mid, (x, 0))
    img.paste(button(h, state, "right"), (w - CAP, 0))
    return img


def labelled(size, text, pressed):
    from PIL import ImageFont
    img = flat_button(size, "selected" if pressed else "raised")
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_BOLD, 10)
    box = d.textbbox((0, 0), text, font=font)
    x = (size[0] - (box[2] - box[0])) // 2 - box[0]
    y = (size[1] - (box[3] - box[1])) // 2 - box[1]
    d.text((x, y), text, font=font, fill=(0xFF, 0xFF, 0xFF) if pressed else GLYPH)
    return img


def tab_piece(size, active, part):
    """Square DarkTech tab: lit top rule on the active tab, dim flat face otherwise."""
    w, h = size
    img = Image.new("RGB", size, KEY)
    face_w = w if part != "right" else w - 5
    # Inactive tabs are light steel: the client draws their label in a dark ink (stock inactive
    # tabs were light teal); on a dark or mid face the label disappears.
    top, low = ((lerp(C["top"], C["edge"], .3), C["fill"]) if active else ((0xA9, 0xC0, 0xD2), (0x76, 0x92, 0xA8)))
    d = ImageDraw.Draw(img)
    for y in range(h):
        d.line([0, y, face_w - 1, y], fill=lerp(top, low, y / (h - 1)))
    d.line([0, 0, face_w - 1, 0], fill=C["accent"] if active else (0xD6, 0xE4, 0xEE))
    if active:
        d.line([0, 1, face_w - 1, 1], fill=lerp(C["accent"], C["fill"], .5))
    if part == "left":
        d.line([0, 0, 0, h], fill=C["edge"] if active else C["edge_dark"])
    if part == "right":
        d.line([face_w - 1, 0, face_w - 1, h], fill=C["black"])
    return img


def scroll_track(size):
    w, h = size
    img = Image.new("RGB", size, C["sunk"])
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=C["black"])
    d.line([1, 1, 1, h - 2], fill=C["edge_dark"])
    return img


def scroll_thumb(size):
    w, h = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for x in range(w):
        d.line([x, 0, x, h], fill=lerp(lerp(C["edge"], C["top"], .2), C["edge_dark"], x / (w - 1)))
    d.rectangle([0, 0, w - 1, h - 1], outline=C["black"])
    d.line([1, 1, 1, h - 2], fill=lerp(C["edge"], C["focus"], .4))
    return img


def arrow_key(size, direction, pressed):
    w, h = size
    img = Image.new("RGB", size, C["sunk"] if pressed else C["fill"])
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=C["black"])
    cx, cy = w / 2 - .5, h / 2 - .5
    r = min(w, h) * .28
    tri = {"UP": [(cx, cy - r), (cx + r, cy + r * .6), (cx - r, cy + r * .6)],
           "DOWN": [(cx - r, cy - r * .6), (cx + r, cy - r * .6), (cx, cy + r)],
           "LEFT": [(cx - r, cy), (cx + r * .6, cy - r), (cx + r * .6, cy + r)],
           "RIGHT": [(cx + r, cy), (cx - r * .6, cy - r), (cx - r * .6, cy + r)]}[direction]
    d.polygon(tri, fill=C["focus"] if pressed else GLYPH)
    return img


def dropdown(name, size):
    w, h = size
    part = name.rsplit("_", 1)[-1]
    if part in ("LEFT", "MIDDLE", "RIGHT"):
        return button(h, "pressed", part.lower()).resize((w, h)) if part == "MIDDLE" else             flat_button((max(w, 2 * CAP), h), "pressed").crop((0, 0, w, h) if part == "LEFT" else (max(w, 2 * CAP) - w, 0, max(w, 2 * CAP), h))
    img = flat_button(size, "raised")
    d = ImageDraw.Draw(img)
    cx, cy, r = w / 2, h / 2, 4
    pts = [(cx - r, cy - 2), (cx + r, cy - 2), (cx, cy + 3)] if part == "CLOSED" else [(cx - r, cy + 2), (cx + r, cy + 2), (cx, cy - 3)]
    d.polygon(pts, fill=GLYPH)
    return img


CAPS = {
    "GFX_GUI_WINDOW_CLOSE_X": (glyph_close, True), "GFX_GUI_WINDOW_PIN": (glyph_pin, False),
    "GFX_GUI_WINDOW_MAXIMIZE": (glyph_max, False), "GFX_GUI_WINDOW_QUESTIONMARK": (glyph_help, False),
    "GFX_GUI_ROLLUP_COLLAPSE": (glyph_up, False), "GFX_GUI_ROLLUP_EXPAND": (glyph_down, False),
}


SLIDER_TRACKS = ("GFX_GUI_MISSION_SLIDER_BACKGROUND", "GFX_GUI_CONTROLCENTER_AGGDEF_SLIDER_BACKGROUND")
SLIDER_THUMBS = ("GFX_GUI_MISSION_SLIDER", "GFX_GUI_CONTROLCENTER_AGGDEF_SLIDER", "GFX_GUI_AGGDEF_SLIDER")


def slider_track(img):
    """Recessed DarkTech groove in the stock bar's exact footprint (key and outline kept):
    blue at the left end fading to deep navy, with a centre tick and quarter ticks."""
    img = img.convert("RGB")
    px = img.load()
    inner = [(x, y) for y in range(img.height) for x in range(img.width)
             if px[x, y] != KEY and sum(px[x, y]) > 60]
    if not inner:
        return img
    x0, x1 = min(p[0] for p in inner), max(p[0] for p in inner)
    y0, y1 = min(p[1] for p in inner), max(p[1] for p in inner)
    for x, y in inner:
        t = (x - x0) / max(1, x1 - x0)
        c = lerp((0x1E, 0x4A, 0x72), (0x0C, 0x16, 0x22), t)
        if y == y0:
            c = C["sunk"]
        elif y == y1:
            c = C["edge_dark"]
        px[x, y] = c
    mid = (x0 + x1) // 2
    for qx, tall in ((mid, True), ((x0 + mid) // 2, False), ((mid + x1) // 2, False)):
        for y in range(y0 + 1, y1):
            if tall or y >= y1 - 2:
                px[qx, y] = C["edge"] if not tall else C["focus"]
    return img


def slider_thumb(img):
    """Grey/cyan stock knob re-inked onto the steel-blue ramp by brightness."""
    img = img.convert("RGB")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            if p == KEY:
                continue
            l = sum(p) / 765
            q = lerp(C["edge_dark"], (0xD6, 0xEA, 0xFF), l) if l > 0.08 else p
            px[x, y] = q if q != KEY else (0, 254, 0)
    return img


def replacement(name, img):
    if name in SLIDER_TRACKS:
        return slider_track(img)
    if name in SLIDER_THUMBS:
        return slider_thumb(img)
    if name.startswith("GFX_GUI_MULTILISTVIEW_SLOT") or name == "GFX_GUI_ICONSLOT":
        return square_slot(img.size, "CLOSED" in name)
    if name.startswith("GFX_GUI_NANO_") and name.split("_")[3] in NANO_LABELS:
        return labelled(img.size, NANO_LABELS[name.split("_")[3]], name.endswith("_PRESSED"))
    if name.startswith(("GFX_GUI_TAB_ACTIVE_", "GFX_GUI_TAB_INACTIVE_")):
        return tab_piece(img.size, "_ACTIVE_" in name, name.rsplit("_", 1)[-1].lower())
    if name in ("GFX_GUI_SCROLLBAR_EMPTY", "GFX_GUI_SCROLLBAR_GRAY_EMPTY"):
        return scroll_track(img.size)
    if name in ("GFX_GUI_SCROLLBAR_FILLED", "GFX_GUI_SCROLLBAR_GRAY_FULL"):
        return scroll_thumb(img.size)
    if name.startswith("GFX_GUI_SCROLLBAR_GRAY_") and ("_UP_" in name or "_DOWN_" in name):
        return arrow_key(img.size, "UP" if "_UP_" in name else "DOWN", name.endswith("PRESSED"))
    if name.startswith("GFX_GUI_DROPDOWNMENU_"):
        return dropdown(name, img.size)
    if name == "GFX_GUI_WINDOW_ICON_I":
        return cap(img.size, glyph_info, 1)
    for base, (glyph, danger) in CAPS.items():
        if name == base or name.startswith(base + "_STATE"):
            state = int(name[-1]) if "_STATE" in name else 1
            return cap(img.size, glyph, state, danger)
    return None


# ---- teal -> steel retint of the classic skin --------------------------------
SKIP = ("FONT", "POINTER", "ICON", "MAP", "PORTRAIT", "LOADING", "SPLASH", "CHARREF", "LOGO", "BUFF")


def retint(img):
    """Shift cyan/teal (hue ~160-200 deg) to DarkTech steel blue (~207 deg), keep the key."""
    img = img.convert("RGB")
    px = img.load()
    changed = False
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            if p == KEY:
                continue
            h, l, s = colorsys.rgb_to_hls(p[0] / 255, p[1] / 255, p[2] / 255)
            if 0.44 <= h <= 0.56 and s > 0.18:
                r, g, b = colorsys.hls_to_rgb(0.575, l * 0.92, s * 0.8)
                q = (int(r * 255), int(g * 255), int(b * 255))
                if q == KEY:
                    q = (0, 254, 0)
                px[x, y] = q
                changed = True
    return img, changed


def png(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def read(uvgi, uvga):
    lines = open(uvgi, encoding="latin1").read().splitlines()
    blob = open(uvga, "rb").read()
    entries = []
    for line in lines[1:]:
        if line.strip():
            name, off, ln = line.split()
            entries.append((name, blob[int(off):int(off) + int(ln)]))
    assert int(lines[0]) == len(entries), "uvgi count mismatch"
    return entries


def client_running():
    if os.environ.get("NDGUI_ASSUME_CLOSED") == "1":  # developer testing against a copy of the client
        return False
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True).stdout
        return "PRK.Client.exe" in out
    except OSError:
        return False


def main(argv):
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    stock_i, stock_a = UVGI + ".stock", UVGA + ".stock"
    if "--restore" in argv:
        if not os.path.exists(stock_a):
            raise SystemExit("no .stock backup: skin was never modified")
        if client_running():
            raise SystemExit("quit PRK.Client.exe first")
        shutil.copyfile(stock_i, UVGI)
        shutil.copyfile(stock_a, UVGA)
        if os.path.exists(COLORS + ".stock"):
            shutil.copyfile(COLORS + ".stock", COLORS)
        print("stock skin restored")
        return
    src_i, src_a = (stock_i, stock_a) if os.path.exists(stock_a) else (UVGI, UVGA)
    entries = read(src_i, src_a)
    names = {n for n, _ in entries}
    retinted = 0
    squared = 0
    new = []
    for name, data in entries:
        rep = replacement(name, Image.open(io.BytesIO(data)))
        if rep is not None:
            data = png(rep)
            squared += 1
        new.append((name, data))
    entries = new
    if "--no-retint" not in argv:
        new = []
        for name, data in entries:
            squared_name = replacement(name, Image.new("RGB", (15, 15))) is not None
            if name.startswith("GFX_GUI_") and not any(k in name for k in SKIP) and not squared_name:
                img, changed = retint(Image.open(io.BytesIO(data)))
                if changed:
                    data = png(img)
                    retinted += 1
            new.append((name, data))
        entries = new
    art = generated()
    for name in art:
        assert name not in names, name
    entries += [(n, png(i)) for n, i in art.items()]

    overlay = argv[argv.index("--overlay") + 1] if "--overlay" in argv else None
    if overlay:
        # Release build: only what differs from stock, for install.ps1 to merge (no Python
        # on the player's side). <NAME>.png per graphic, new.txt = appended names in order,
        # colors.txt = GUIColors values.
        stock = dict(read(src_i, src_a))
        os.makedirs(overlay, exist_ok=True)
        changed = 0
        for n, data in entries:
            if stock.get(n) != data:
                open(os.path.join(overlay, n + ".png"), "wb").write(data)
                changed += 1
        open(os.path.join(overlay, "new.txt"), "w", encoding="ascii", newline="\n").write(
            "".join(n + "\n" for n in art))
        open(os.path.join(overlay, "colors.txt"), "w", encoding="ascii", newline="\n").write(
            "".join(f"{k}={v}\n" for k, v in GUI_COLORS.items()))
        print(f"skin overlay: {changed} graphics ({len(art)} new) -> {overlay}")
        return
    if preview:
        os.makedirs(preview, exist_ok=True)
        for n, data in entries:
            if n.startswith("GFX_NDGUI_") or n.startswith(("GFX_GUI_WINDOW", "GFX_GUI_ROLLUP", "GFX_GUI_MULTILISTVIEW", "GFX_GUI_NANO", "GFX_GUI_TAB", "GFX_GUI_SCROLLBAR", "GFX_GUI_DROPDOWN")):
                open(os.path.join(preview, n + ".png"), "wb").write(data)
        print(f"preview: {len(art)} new, {retinted} retinted -> {preview}")
        return
    if client_running():
        raise SystemExit("quit PRK.Client.exe first (it reads the skin at start)")
    if not os.path.exists(stock_a):
        shutil.copyfile(UVGI, stock_i)
        shutil.copyfile(UVGA, stock_a)
    blob, index, off = bytearray(), [str(len(entries))], 0
    for name, data in entries:
        index.append(f"{name} {off} {len(data)}")
        blob += data
        off += len(data)
    open(UVGA, "wb").write(bytes(blob))
    if not os.path.exists(COLORS + ".stock"):
        shutil.copyfile(COLORS, COLORS + ".stock")
    colors = open(COLORS + ".stock", encoding="latin1").read()
    for key, value in GUI_COLORS.items():
        colors = re.sub(r'(<Color name="%s"\s+color=")[^"]*"' % key, r'\g<1>%s"' % value, colors)
    open(COLORS, "w", encoding="latin1", newline="").write(colors)
    open(UVGI, "w", encoding="latin1", newline="").write("\r\n".join(index) + "\r\n")
    print(f"skin written: {len(entries)} graphics ({len(art)} ndGUI, {squared} squared, {retinted} retinted)")


if __name__ == "__main__":
    main(sys.argv[1:])
