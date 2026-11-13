"""Original ndGUI line icons for the bottom strip (drawn at 4x, downsampled).

Run: python tools/make_icons.py   (from the ndgui folder)
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "ndgui-lib", "assets", "icons"))
S = 4            # supersample
N = 20           # final icon size
LINE = (197, 215, 230, 255)   # darktech text #c5d7e6
ACCENT = (61, 143, 212, 255)  # darktech accent #3d8fd4
W = int(1.6 * S)  # stroke width at supersample


def canvas():
    img = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def P(x, y):
    return (x * S, y * S)


def box(x0, y0, x1, y1):
    return [x0 * S, y0 * S, x1 * S, y1 * S]


def finish(img, name):
    small = img.resize((N, N), Image.LANCZOS)
    glow = small.copy().filter(ImageFilter.GaussianBlur(1.1))
    r, g, b, a = glow.split()
    a = a.point(lambda v: int(v * 0.35))
    glow = Image.merge("RGBA", (Image.new("L", glow.size, 61), Image.new("L", glow.size, 143), Image.new("L", glow.size, 212), a))
    out = Image.alpha_composite(glow, small)
    os.makedirs(OUT, exist_ok=True)
    out.save(os.path.join(OUT, name + ".png"), optimize=True)
    return out


def actions():
    img, d = canvas()
    d.line([P(11.5, 2), P(5.5, 11), P(10, 11), P(8.5, 18), P(14.5, 8.5), P(10, 8.5), P(11.5, 2)], fill=LINE, width=W, joint="curve")
    return img


def character():
    img, d = canvas()
    d.ellipse(box(7, 2.5, 13, 8.5), outline=LINE, width=W)
    d.arc(box(3.5, 10, 16.5, 23), 180, 360, fill=LINE, width=W)
    d.line([P(3.6, 16.5), P(16.4, 16.5)], fill=LINE, width=W)
    return img


def nano():
    img, d = canvas()
    cx, cy, r = 10, 10, 7.5
    pts = [P(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in range(-90, 271, 60)]
    d.line(pts, fill=LINE, width=W, joint="curve")
    d.ellipse(box(8, 8, 12, 12), fill=ACCENT)
    for a in (-90, 30, 150):
        d.line([P(cx, cy), P(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))], fill=LINE, width=int(W * 0.6))
    return img


def inventory():
    img, d = canvas()
    d.rounded_rectangle(box(3.5, 6.5, 16.5, 17), radius=2 * S, outline=LINE, width=W)
    d.arc(box(7, 2.5, 13, 9), 180, 360, fill=LINE, width=W)
    d.line([P(3.5, 11), P(16.5, 11)], fill=LINE, width=W)
    d.rectangle(box(9, 10, 11, 12.5), fill=ACCENT)
    return img


def wear():
    img, d = canvas()
    d.line([P(7, 3), P(3, 6), P(4.5, 10), P(6, 9.5), P(6, 17), P(14, 17), P(14, 9.5), P(15.5, 10), P(17, 6), P(13, 3)], fill=LINE, width=W, joint="curve")
    d.arc(box(7, 1, 13, 6.5), 0, 180, fill=LINE, width=W)
    d.line([P(10, 9), P(10, 15)], fill=ACCENT, width=W)
    return img


def ncu():
    img, d = canvas()
    d.rectangle(box(5, 5, 15, 15), outline=LINE, width=W)
    d.rectangle(box(8, 8, 12, 12), fill=ACCENT)
    for t in (7.5, 10, 12.5):
        d.line([P(t, 2), P(t, 5)], fill=LINE, width=int(W * 0.7))
        d.line([P(t, 15), P(t, 18)], fill=LINE, width=int(W * 0.7))
        d.line([P(2, t), P(5, t)], fill=LINE, width=int(W * 0.7))
        d.line([P(15, t), P(18, t)], fill=LINE, width=int(W * 0.7))
    return img


def map_icon():
    img, d = canvas()
    d.line([P(2.5, 5), P(7.5, 3), P(12.5, 5), P(17.5, 3), P(17.5, 15), P(12.5, 17), P(7.5, 15), P(2.5, 17), P(2.5, 5)], fill=LINE, width=W, joint="curve")
    d.line([P(7.5, 3), P(7.5, 15)], fill=LINE, width=int(W * 0.7))
    d.line([P(12.5, 5), P(12.5, 17)], fill=LINE, width=int(W * 0.7))
    d.ellipse(box(9, 8, 11.5, 10.5), fill=ACCENT)
    return img


def missions():
    img, d = canvas()
    d.line([P(5, 2.5), P(5, 18)], fill=LINE, width=W)
    d.polygon([P(5.6, 3.5), P(16, 6.5), P(5.6, 10)], fill=ACCENT)
    d.line([P(5.6, 3.5), P(16, 6.5), P(5.6, 10)], fill=LINE, width=int(W * 0.6))
    return img


def store():
    img, d = canvas()
    d.ellipse(box(3, 3, 17, 17), outline=LINE, width=W)
    d.arc(box(7, 6, 13, 10.5), 90, 360, fill=ACCENT, width=W)
    d.arc(box(7, 9.5, 13, 14), 270, 180, fill=ACCENT, width=W)
    d.line([P(10, 4.5), P(10, 15.5)], fill=ACCENT, width=int(W * 0.7))
    return img


def team():
    img, d = canvas()
    for cx, s in ((10, 1.0), (4.8, 0.75), (15.2, 0.75)):
        r = 2.4 * s
        top = 4.5 if s == 1.0 else 6
        d.ellipse(box(cx - r, top, cx + r, top + 2 * r), outline=LINE, width=int(W * (0.9 if s == 1.0 else 0.7)))
        d.arc(box(cx - 4.2 * s, top + 2 * r + 1.2, cx + 4.2 * s, top + 2 * r + 9 * s), 180, 360, fill=LINE, width=int(W * (0.9 if s == 1.0 else 0.7)))
    return img


def friends():
    img, d = canvas()
    d.ellipse(box(3, 4, 8.5, 9.5), outline=LINE, width=W)
    d.arc(box(1, 11, 10.5, 21), 180, 360, fill=LINE, width=W)
    # heart
    d.ellipse(box(11, 5, 14, 8), fill=ACCENT)
    d.ellipse(box(13.5, 5, 16.5, 8), fill=ACCENT)
    d.polygon([P(11.1, 7), P(16.4, 7), P(13.75, 11)], fill=ACCENT)
    return img


def crosshair(enemy):
    img, d = canvas()
    col = (196, 71, 71, 255) if enemy else LINE
    d.ellipse(box(4, 4, 16, 16), outline=col, width=W)
    for a, b in (((10, 1.5), (10, 6)), ((10, 14), (10, 18.5)), ((1.5, 10), (6, 10)), ((14, 10), (18.5, 10))):
        d.line([P(*a), P(*b)], fill=col, width=W)
    if enemy:
        d.line([P(8, 8), P(12, 12)], fill=col, width=W)
        d.line([P(12, 8), P(8, 12)], fill=col, width=W)
    else:
        d.ellipse(box(8.8, 8.8, 11.2, 11.2), fill=ACCENT)
    return img


ICONS = {
    "actions": actions, "character": character, "nano": nano, "inventory": inventory, "wear": wear,
    "ncu": ncu, "map": map_icon, "missions": missions, "store": store, "team": team, "friends": friends,
    "target_self": lambda: crosshair(False), "target_other": lambda: crosshair(True),
}


def main():
    sheet = Image.new("RGBA", (len(ICONS) * 52 + 8, 60), (16, 30, 40, 255))
    for i, (name, fn) in enumerate(ICONS.items()):
        icon = finish(fn(), name)
        sheet.alpha_composite(icon.resize((40, 40), Image.NEAREST), (8 + i * 52, 10))
        print("icons/" + name + ".png")
    return sheet


if __name__ == "__main__":
    import sys
    sheet = main()
    if len(sys.argv) > 1:
        sheet.save(sys.argv[1])
