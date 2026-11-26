"""Square DarkTech buttons for ndGUI packages and optional client Layouts.

Run from the ndgui folder:
  python tools/square_buttons.py            patch packages + client UI/Layouts
  python tools/square_buttons.py --restore  put the stock UI/Layouts back (*.stock copies)
  python tools/square_buttons.py --addons-only  patch only ndgui packages

Packages (marketplace-safe): wrap labelled Buttons in ndgui_btnwrap with
library://notum.ndgui-lib/buttons/... chrome. No GFX_NDGUI_* atlas ids.

Layouts (player installer / residual skin only): still inject GFX_NDGUI_BTN*
atlas gfxids so Login/Options match when skin.py has been applied.

Optional: NDGUI_ADDONS=/path/to/UI/Addons overrides the packages root.
"""
import glob, os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.environ.get("NDGUI_ADDONS") or os.path.join(HERE, "..", ".."))
LAYOUTS = os.path.normpath(os.path.join(ADDONS, "..", "Layouts"))
HEIGHTS = (19, 20, 22, 23, 24, 26, 28, 32)  # must match skin.py
STATES = (("raised", "RAISED"), ("hover", "HOVER"), ("pressed", "PRESSED"))
TAG = re.compile(r"<Button\b[^>]*?/?>", re.S)
# ndgui_btnwrap chrome is BitmapViews only (never a nested View).
_CHROME = (
    r'<View name="ndgui_chrome"[^>]*>\s*'
    r'(?:<BitmapView\b[^>]*/>\s*)+'
    r'</View>'
)
WRAP = re.compile(
    r'<View name="ndgui_btnwrap"[^>]*>\s*'
    + _CHROME +
    r'\s*'
    r'(<Button\b[^>]*?/>|<Button\b[^>]*?>.*?</Button>)\s*'
    r'</View>',
    re.S,
)
SLOT = re.compile(r"<ItemSlotView\b[^>]*?/?>", re.S)
NDGUI_GFX = re.compile(r'\s+gfxid_[a-z_]+="GFX_(?:GUI_)?NDGUI_[^"]*"')
STOCK_SLOT = re.compile(r'\s+slot_gfx="GFX_GUI_[^"]*"')
CAP = 4


def height(tag):
    for attr in ("max_size", "min_size"):
        m = re.search(attr + r'="Point\(\s*-?\d+\s*,\s*(-?\d+)\s*\)"', tag)
        if m and int(m.group(1)) > 0:
            h = int(m.group(1))
            return min(HEIGHTS, key=lambda k: (abs(k - h), -k))
    return 28


BAKED = {"FAVOURITES": ("Favorites", 80), "COMBAT": ("Combat", 66), "MEDICAL": ("Medical", 68),
         "PROT": ("Prot", 50), "PSI": ("Psi", 42), "SPACE": ("Space", 56)}
BAKED_H, BAKED_FONT = 22, 11
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
            f'max_size="Point({width},{BAKED_H})" {close}')


def strip_ndgui_gfx(tag):
    return NDGUI_GFX.sub("", tag)


def attr(tag, name):
    m = re.search(r'\b' + name + r'="([^"]*)"', tag)
    return m.group(1) if m else None


def unwrap_buttons(text):
    """Peel ndgui_btnwrap layers until none remain (fixes nested wraps)."""
    total = 0
    while True:
        text, n = WRAP.subn(r"\1", text)
        total += n
        if n == 0:
            break
    return text, total


def skin_atlas(tag):
    """Player Layouts path: inject GFX_NDGUI_BTN* atlas ids (requires skin.py merge)."""
    tag = unbake(tag)
    tag = strip_ndgui_gfx(tag)
    if "gfxid_raised" in tag or 'flat="true"' in tag or 'button_style="select"' in tag:
        return tag
    if "label=" not in tag and "font_size=" not in tag:
        return tag
    h = height(tag)
    attrs = " ".join(f'gfxid_{s}_{p}="GFX_NDGUI_BTN{h}_{S}_{p.upper()}"'
                     for s, S in STATES for p in ("left", "middle", "right"))
    close = "/>" if tag.endswith("/>") else ">"
    body = tag[: -len(close)].rstrip()
    if f'gfxid_selected="GFX_NDGUI_BTN{h}_SELECTED"' not in body and "gfxid_selected" not in body:
        attrs += f' gfxid_selected="GFX_NDGUI_BTN{h}_SELECTED"'
    return f"{body} {attrs} {close}"


def skin_package(tag):
    """Marketplace-safe: wrap labelled buttons with library:// DarkTech chrome."""
    tag = unbake(tag)
    had_ndgui = bool(NDGUI_GFX.search(tag))
    tag = strip_ndgui_gfx(tag)
    if 'button_style="select"' in tag:
        return tag
    if "label=" not in tag and "font_size=" not in tag:
        return tag
    # Stock icon buttons (non-NDGUI gfxid) stay on the atlas.
    if "gfxid_raised" in tag and not had_ndgui:
        return tag
    h = height(tag)
    close = "/>" if tag.endswith("/>") else ">"
    body = tag[: -len(close)].rstrip()
    body = re.sub(r'\s+flat="true"', "", body)
    body = re.sub(r'\s+text_alignment="[^"]*"', "", body)
    body += ' flat="true" text_alignment="center"'
    btn = f"{body} {close}"
    wrap_bits = []
    for name in ("weight", "layout_borders", "v_alignment", "h_alignment", "visible", "enabled"):
        val = attr(btn, name)
        if val is not None and name in ("weight", "layout_borders", "v_alignment", "h_alignment"):
            wrap_bits.append(f'{name}="{val}"')
            btn = re.sub(r'\s+' + name + r'="[^"]*"', "", btn)
    min_size = attr(btn, "min_size") or f"Point(-1,{h})"
    max_size = attr(btn, "max_size") or f"Point(-1,{h})"
    base = f"library://notum.ndgui-lib/buttons/btn{h}_raised"
    chrome = (
        f'<View name="ndgui_chrome" interactive="false" view_layout="horizontal">'
        f'<BitmapView name="ndgui_btn_l" interactive="false" image="{base}_left.png" '
        f'min_size="Point({CAP},{h})" max_size="Point({CAP},{h})" />'
        f'<BitmapView name="ndgui_btn_m" interactive="false" image="{base}_middle.png" '
        f'weight="1" min_size="Point(0,{h})" max_size="Point(-1,{h})" />'
        f'<BitmapView name="ndgui_btn_r" interactive="false" image="{base}_right.png" '
        f'min_size="Point({CAP},{h})" max_size="Point({CAP},{h})" />'
        f"</View>"
    )
    wrap_attr = " ".join(wrap_bits)
    return (
        f'<View name="ndgui_btnwrap" view_layout="stacked" min_size="{min_size}" '
        f'max_size="{max_size}"{(" " + wrap_attr) if wrap_attr else ""}>'
        f"{chrome}{btn}</View>"
    )


def slot_size(tag):
    for name in ("min_size", "max_size"):
        m = re.search(name + r'="Point\(\s*(\d+)\s*,\s*(\d+)\s*\)"', tag)
        if m:
            return int(m.group(1)), int(m.group(2))
    return 54, 54


def slot_asset(w, h):
    """Pick open_*.png for a slot size (exact 46x30, else nearest square)."""
    if (w, h) == (46, 30):
        return "library://notum.ndgui-lib/slots/open_46x30.png"
    side = min((36, 48, 54), key=lambda s: abs(s - max(w, h)))
    return f"library://notum.ndgui-lib/slots/open_{side}.png"


def skin_slot(tag):
    """Wrap an ItemSlotView in a stacked cell with library:// well art behind it."""
    if "ndgui_slot_back" in tag or 'name="ndgui_slotcell"' in tag or 'name="ndgui_slotwrap"' in tag:
        return tag
    if 'name="wear_cell_' in tag:
        return tag
    gfx = attr(tag, "slot_gfx")
    if gfx and gfx != "" and not gfx.startswith("GFX_GUI_"):
        return tag
    close = "/>" if tag.endswith("/>") else ">"
    body = tag[: -len(close)].rstrip()
    body = STOCK_SLOT.sub("", body)
    body = re.sub(r'\s+slot_gfx="[^"]*"', "", body)
    body = re.sub(r'\s+fill_color="[^"]*"', "", body)
    body = re.sub(r'\s+view_layout="[^"]*"', "", body)
    # Hotbar already draws its own well behind shortcut_slot.
    if 'name="shortcut_slot"' in tag:
        body += ' slot_gfx=""'
        return f"{body} {close}"
    w, h = slot_size(tag)
    # Tiny NCU status dots: strip atlas chrome only.
    if min(w, h) < 24:
        body += ' slot_gfx=""'
        return f"{body} {close}"
    if 'slot_gfx=""' not in body:
        body += ' slot_gfx=""'
    name = attr(tag, "name") or ""
    # Collection templates: rename the slot so slot_cells.lua can find it.
    if name in ("", "action_slot", "trade_slot", "nano_slot", "ncu_slot") or name.startswith("ndgui_slot"):
        body = re.sub(r'\s+name="[^"]*"', "", body)
        body += ' name="ndgui_slot"'
        cell_name = "ndgui_slotcell"
    elif name.startswith("wear_slot_"):
        cell_name = "wear_cell_" + name[len("wear_slot_"):]
    else:
        # Named icons (detail_icon, reward_slot, ...): keep the name; ui.find is recursive.
        cell_name = "ndgui_slotcell"
    slot = f"{body} {close}"
    uri = slot_asset(w, h)
    back = (
        f'<BitmapView name="ndgui_slot_back" interactive="false" image="{uri}" '
        f'min_size="Point({w},{h})" max_size="Point({w},{h})" />'
    )
    return (
        f'<View name="{cell_name}" view_layout="stacked" '
        f'min_size="Point({w},{h})" max_size="Point({w},{h})">'
        f"{back}{slot}</View>"
    )


def unwrap_slots(text):
    """Peel ndgui_slotcell / wear_cell / legacy wraps so re-skin is idempotent."""
    total = 0
    for pattern in (
        r'<View name="ndgui_slotwrap"[^>]*>\s*'
        r'<BitmapView name="ndgui_slot_back"[^>]*/>\s*'
        r'(<ItemSlotView\b[^>]*?/>)\s*'
        r'</View>',
        r'<View name="ndgui_slotcell"[^>]*>\s*'
        r'<BitmapView name="ndgui_slot_back"[^>]*/>\s*'
        r'(<ItemSlotView\b[^>]*?/>)\s*'
        r'</View>',
        r'<View name="wear_cell_[^"]*"[^>]*>\s*'
        r'<BitmapView name="ndgui_slot_back"[^>]*/>\s*'
        r'(<ItemSlotView\b[^>]*?/>)\s*'
        r'</View>',
    ):
        rx = re.compile(pattern, re.S)
        while True:
            text, n = rx.subn(r"\1", text)
            total += n
            if n == 0:
                break
    CHILD = re.compile(
        r'(<ItemSlotView\b[^>]*?)\s*>\s*'
        r'<BitmapView name="ndgui_slot_back"[^>]*/>\s*'
        r'</ItemSlotView>',
        re.S,
    )

    def flatten(m):
        nonlocal total
        total += 1
        body = m.group(1).rstrip()
        body = re.sub(r'\s+view_layout="[^"]*"', "", body)
        return f"{body} />"

    text = CHILD.sub(flatten, text)
    return text, total


def skin_wear_panels(text):
    """Flat DarkTech fills instead of stock GFX_GUI_WEARVIEW_BG* / tab border atlas."""
    if 'name="wear_frame"' not in text and "GFX_GUI_WEARVIEW_BG" not in text:
        return text, 0
    n = 0
    frame = re.compile(
        r'<BorderView name="wear_frame" view_layout="stacked"\s*'
        r'min_size="Point\(([^"]+)\)"\s*max_size="Point\(([^"]+)\)"\s*'
        r'tl_gfx="GFX_GUI_TAB_BORDER_TL"[^>]*bg_gfx="GFX_GUI_TAB_BACKGROUND">',
        re.S,
    )
    text2, c = frame.subn(
        r'<View name="wear_frame" view_layout="stacked" fill_color="0xFF0A121C" '
        r'min_size="Point(\1)" max_size="Point(\2)">',
        text,
        count=1,
    )
    if c:
        text, n = text2, n + c
        # wear_frame is the only BorderView in stock wear content.
        text, c = re.subn(r"</BorderView>", "</View>", text, count=1)
        n += c
    panel = re.compile(
        r'<BitmapView (name="wear_(?:weapons|clothing|implants|social)"[^>]*)\s*'
        r'image="gfx://GFX_GUI_WEARVIEW_BG[12]"\s*graphic_mode="tinted"',
        re.S,
    )
    text, c = panel.subn(r'<View \1 fill_color="0xFF070B0F"', text)
    n += c
    if c:
        for name in ("wear_weapons", "wear_clothing", "wear_implants", "wear_social"):
            text, c2 = re.subn(
                rf'(<View name="{name}"[^>]*>.*?)</BitmapView>',
                r"\1</View>",
                text,
                count=1,
                flags=re.S,
            )
            n += c2
    return text, n


def patch_text(text, package_mode):
    count = 0
    if package_mode:
        text, n = unwrap_buttons(text)
        count += n
        text, n = unwrap_slots(text)
        count += n

    skin = skin_package if package_mode else skin_atlas

    def one_btn(m):
        nonlocal count
        tag = m.group(0)
        if package_mode:
            # Skip buttons already inside a wrap (look farther back for nested leftovers).
            start = m.start()
            window = text[max(0, start - 200):start]
            if window.rstrip().endswith(">") and 'name="ndgui_btnwrap"' in window[-200:]:
                # Still inside an unwrapped-failed nest; unwrap pass should have cleared.
                pass
            if 'ndgui_btnwrap' in window and window.rfind("ndgui_btnwrap") > window.rfind("</View>"):
                cleaned = strip_ndgui_gfx(tag)
                if 'text_alignment="center"' not in cleaned and ("label=" in cleaned or "font_size=" in cleaned):
                    close = "/>" if cleaned.endswith("/>") else ">"
                    body = cleaned[: -len(close)].rstrip()
                    body = re.sub(r'\s+text_alignment="[^"]*"', "", body)
                    cleaned = f'{body} text_alignment="center" {close}'
                if cleaned != tag:
                    count += 1
                return cleaned
        new = skin(tag)
        count += new != tag
        return new

    text = TAG.sub(one_btn, text)

    if package_mode:
        def one_slot(m):
            nonlocal count
            tag = m.group(0)
            start = m.start()
            window = text[max(0, start - 120):start]
            if (
                'name="ndgui_slotwrap"' in window
                or 'name="ndgui_slotcell"' in window
                or 'name="wear_cell_' in window
                or "ndgui_slot_back" in window[-100:]
            ):
                return tag
            new = skin_slot(tag)
            count += new != tag
            return new

        text = SLOT.sub(one_slot, text)
        text, n = skin_wear_panels(text)
        count += n

    return text, count


MARKER = "NDGUI"


def patch(path, source=None, package_mode=True):
    text = open(source or path, encoding="utf-8").read()
    new, n = patch_text(text, package_mode)
    if new != text or source:
        open(path, "w", encoding="utf-8", newline="\n").write(new)
    return n


def addon_xml_paths():
    paths = []
    for pattern in ("ndgui-*", "notum.ndgui-*", "ndgui"):
        paths.extend(glob.glob(os.path.join(ADDONS, pattern, "**", "*.xml"), recursive=True))
        paths.extend(glob.glob(os.path.join(ADDONS, pattern, "*.xml")))
    out = []
    seen = set()
    for path in paths:
        path = os.path.normpath(path)
        if path in seen:
            continue
        seen.add(path)
        if path.endswith(os.path.join("ndgui-lib", "window.xml")):
            continue
        if path.endswith(os.path.join("ndgui-lib", "button_chrome.xml")):
            continue
        # Marketplace renamed lib folder
        if path.replace("\\", "/").endswith("notum.ndgui-lib/window.xml"):
            continue
        if path.replace("\\", "/").endswith("notum.ndgui-lib/button_chrome.xml"):
            continue
        out.append(path)
    return sorted(out)


def main(argv):
    layouts = sorted(glob.glob(os.path.join(LAYOUTS, "*.xml")))
    if "--restore" in argv:
        core_window = os.path.normpath(os.path.join(LAYOUTS, "..", "Packages", "Core", "window.xml"))
        for path in layouts + [core_window]:
            if os.path.exists(path + ".stock") and MARKER in open(path, encoding="utf-8").read():
                shutil.copyfile(path + ".stock", path)
        print("stock layouts restored")
        return
    total = 0
    for path in addon_xml_paths():
        total += patch(path, package_mode=True)
    if "--addons-only" in argv:
        print(f"square buttons: {total} package controls wrapped (library:// chrome/slots)")
        return
    for path in layouts:
        text = open(path, encoding="utf-8").read()
        if not os.path.exists(path + ".stock") and patch_text(text, False)[1]:
            shutil.copyfile(path, path + ".stock")
        elif os.path.exists(path + ".stock") and MARKER not in text:
            shutil.copyfile(path, path + ".stock")
        if os.path.exists(path + ".stock"):
            total += patch(path, path + ".stock", package_mode=False)
    core_window = os.path.normpath(os.path.join(LAYOUTS, "..", "Packages", "Core", "window.xml"))
    if not os.path.exists(core_window + ".stock") or MARKER not in open(core_window, encoding="utf-8").read():
        shutil.copyfile(core_window, core_window + ".stock")
    text = open(core_window + ".stock", encoding="utf-8").read()
    pin = 'gfxid_pressed="GFX_GUI_WINDOW_PIN_STATE3"'
    if text.count(pin) == 1 and "GFX_NDGUI_PIN_ON" not in text:
        text = text.replace(pin, pin + ' gfxid_selected="GFX_NDGUI_PIN_ON"')
        open(core_window, "w", encoding="utf-8", newline="\n").write(text)
        total += 1
    elif "GFX_NDGUI_PIN_ON" not in text and text.count(pin) != 1:
        print("Core/window.xml pin changed upstream; not patched")
    print(f"square buttons: {total} controls skinned")


if __name__ == "__main__":
    main(sys.argv[1:])
