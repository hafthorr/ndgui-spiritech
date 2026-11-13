"""Give every labelled Button the square DarkTech 3-slice skin (GFX_NDGUI_BTN* from skin.py).

Run from the ndgui folder:
  python tools/square_buttons.py            patch ndgui-* package XML + client UI/Layouts
  python tools/square_buttons.py --restore  put the stock UI/Layouts back (*.stock copies)
  python tools/square_buttons.py --addons-only  patch only the ndgui-* packages

A Button is patched when it has a label or font_size (i.e. it draws text), has no gfxid_*
skin of its own, and is not flat="true" or button_style="select" (dropdown). Idempotent.
UI/Layouts is the client's own global layout folder (Options, Login, ...): the first patch
keeps <file>.stock, later patches start from it. Re-run after a client update or after
fork_windows.py regenerates the forks. Requires the skin from tools/skin.py.
"""
import glob, os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.path.join(HERE, "..", ".."))
LAYOUTS = os.path.normpath(os.path.join(ADDONS, "..", "Layouts"))
HEIGHTS = (19, 20, 22, 23, 24, 26, 28, 32)  # must match skin.py
STATES = (("raised", "RAISED"), ("hover", "HOVER"), ("pressed", "PRESSED"))
TAG = re.compile(r"<Button\b[^>]*?/?>", re.S)


def height(tag):
    for attr in ("max_size", "min_size"):
        m = re.search(attr + r'="Point\(\s*-?\d+\s*,\s*(-?\d+)\s*\)"', tag)
        if m and int(m.group(1)) > 0:
            h = int(m.group(1))
            return min(HEIGHTS, key=lambda k: (abs(k - h), -k))
    return 28


# Stock image buttons with text baked into low-res art (blurry at interface scale > 100%):
# turned into labelled buttons so the client renders the text at full resolution.
BAKED = {"FAVOURITES": ("Favorites", 80), "COMBAT": ("Combat", 66), "MEDICAL": ("Medical", 68),
         "PROT": ("Prot", 50), "PSI": ("Psi", 42), "SPACE": ("Space", 56)}
BAKED_H, BAKED_FONT = 22, 11  # fills the 22px toolbar row; 11px text leaves room inside the frame
BAKED_TAG = re.compile(r'gfxid_raised="GFX_GUI_NANO_([A-Z]+)"')


def unbake(tag):
    m = BAKED_TAG.search(tag)
    if not m or m.group(1) not in BAKED:
        return tag
    label, width = BAKED[m.group(1)]
    tag = re.sub(r'\s+gfxid_[a-z_]+="[^"]*"', "", tag)
    close = "/>" if tag.endswith("/>") else ">"
    body = tag[: -len(close)].rstrip()
    body = body.replace('layout_borders="Rect(8,0,0,0)"', 'layout_borders="Rect(4,0,0,0)"')
    return (f'{body} label="{label}" font_size="{BAKED_FONT}" min_size="Point({width},{BAKED_H})" '
            f'max_size="Point({width},{BAKED_H})" gfxid_selected="GFX_NDGUI_BTN{BAKED_H}_SELECTED" {close}')


def skin(tag):
    tag = unbake(tag)
    if "gfxid_raised" in tag or 'flat="true"' in tag or 'button_style="select"' in tag:
        return tag
    if "label=" not in tag and "font_size=" not in tag:
        return tag
    h = height(tag)
    attrs = " ".join(f'gfxid_{s}_{p}="GFX_NDGUI_BTN{h}_{S}_{p.upper()}"'
                     for s, S in STATES for p in ("left", "middle", "right"))
    close = "/>" if tag.endswith("/>") else ">"
    body = tag[: -len(close)].rstrip()
    return f"{body} {attrs} {close}"


def patch_text(text):
    count = 0

    def one(m):
        nonlocal count
        new = skin(m.group(0))
        count += new != m.group(0)
        return new

    return TAG.sub(one, text), count


def patch(path, source=None):
    text = open(source or path, encoding="utf-8").read()
    new, n = patch_text(text)
    if new != text or source:
        open(path, "w", encoding="utf-8", newline="").write(new)
    return n


def main(argv):
    layouts = sorted(glob.glob(os.path.join(LAYOUTS, "*.xml")))
    if "--restore" in argv:
        core_window = os.path.normpath(os.path.join(LAYOUTS, "..", "Packages", "Core", "window.xml"))
        for path in layouts + [core_window]:
            if os.path.exists(path + ".stock"):
                shutil.copyfile(path + ".stock", path)
        print("stock layouts restored")
        return
    total = 0
    for path in sorted(glob.glob(os.path.join(ADDONS, "ndgui-*", "**", "*.xml"), recursive=True)):
        total += patch(path)
    if "--addons-only" in argv:
        print(f"square buttons: {total} buttons skinned (ndgui-* packages only)")
        return
    for path in layouts:
        text = open(path, encoding="utf-8").read()
        if not os.path.exists(path + ".stock") and patch_text(text)[1]:
            shutil.copyfile(path, path + ".stock")
        if os.path.exists(path + ".stock"):
            total += patch(path, path + ".stock")
    # Stock windows we do not replace (Find Team, reward picker...) use Core/window.xml:
    # give their pin the same lit "pinned" key (GFX_NDGUI_PIN_ON from skin.py).
    core_window = os.path.normpath(os.path.join(LAYOUTS, "..", "Packages", "Core", "window.xml"))
    if not os.path.exists(core_window + ".stock"):
        shutil.copyfile(core_window, core_window + ".stock")
    text = open(core_window + ".stock", encoding="utf-8").read()
    pin = 'gfxid_pressed="GFX_GUI_WINDOW_PIN_STATE3"'
    if text.count(pin) == 1:
        text = text.replace(pin, pin + ' gfxid_selected="GFX_NDGUI_PIN_ON"')
        open(core_window, "w", encoding="utf-8", newline="").write(text)
        total += 1
    else:
        print("Core/window.xml pin changed upstream; not patched")
    print(f"square buttons: {total} buttons skinned")


if __name__ == "__main__":
    main(sys.argv[1:])
