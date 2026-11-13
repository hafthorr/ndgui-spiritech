# Asset specification

> Background notes from the first (v0.1) design pass. The packages have moved on since (see the top-level README); kept for the research and design rationale.

Original art direction for v1. Do not drop in ndGUI or Funcom texture zips, XML skins, or `gfx://` ids from the stock client as a substitute for these frames. Package images, when they are painted, are PNG, JPEG, or WebP under an `<Assets root="assets" />` directory and are referenced as `package://…`.

No bitmaps ship in v1. The metrics below are the contract for a later nine-patch set. Colors are the theme tokens in `ndgui/theme.lua`.

## Nine-patch frames

All frames are a single stretchable border. Corners do not rotate. The center is a flat fill of the theme panel color. The border color is the theme border token. Draw them at 32×32 logical pixels and slice as follows. `ui.pixel_scale` is the client’s job; author the source at 1× logical and let the client scale, plus a 2× export only if a bitmap looks soft at pixel scale 2.

| Frame | Theme | Border | Corner slice | Radius | Edge treatment |
| --- | --- | --- | --- | --- | --- |
| `frame_beveled` | Classic Dovvetech | 2px | 8px | 0 | 1px highlight on the top and left (`#d5e8f2` at 70% over the border), 1px shadow on the bottom and right (`#0b1218` at 50%). |
| `frame_pronounced` | DarkTech | 3px | 10px | 0 | Double line: outer 1px `#163044`, inner 2px border token. Header band is 20px of panel_alt. |
| `frame_hairline` | DarkTech Mini | 1px | 4px | 0 | Single border pixel. No highlight. Header band is 14px. |
| `frame_flat` | Adaptive | 1px | 6px | 3px | Flat border in the text-adjacent border token. No bevel. Header band is 18px. |

The center slice is whatever remains after the corner inset. Do not paint a noise texture into the center. Bar tracks are not nine-patches: a 4px radius-0 rect, fill `bar_track`, fill width = fraction × inner width, color health / nano / xp.

Menu row background is a 1×N strip of `menu`, height = one `menu_row_px`, not a window frame.

## Icons

16×16 logical grid, 1px padding, geometric, two colors (accent and text). Mini uses the same paths at 12px. Stroke 1.5px on Adaptive, 2px on DarkTech, 1px on Mini, 1.5px on Classic. No borrowed AO item icons.

| Id | Shape |
| --- | --- |
| `icon_compass` | Circle, four ticks, a wedge toward heading. Classic wedge is the orange accent. DarkTech wedge is the blue accent. |
| `icon_health` | Horizontal bar with a squared cap. |
| `icon_nano` | Diamond. |
| `icon_xp` | Chevron pointing up. |
| `icon_lock` | Rounded shackle over a square body. Used for Lock Wear, Lock Shortcutbar, Lock RaidBar. |
| `icon_inspect` | Ring with a short handle. |
| `icon_afk` | Clock face, two hands. |
| `icon_social` | Two overlapping circles. |
| `icon_names` | Rectangle nameplate with a baseline. |
| `icon_inventory` | Open box, three-quarter view, no lid art from the old GUI. |
| `icon_chat` | Rounded speech rectangle. |
| `icon_raid` | Three short horizontal bars stacked, the compact-row silhouette. |
| `icon_options` | Vertical slider with one knob. |

Generation prompt, if a bitmap is produced later: “flat UI icon, 16px, dark steel background transparent, single accent color, geometric, no text, no photoreal metal, no copied game logo.” Run it once per icon with the accent hex from the theme. Do not img2img from a screenshot of ndGUI.

## Color

Use the hex values in `ndgui/theme.lua` only. Text on panel must stay the theme `text` against `panel`. Adaptive is the high-contrast pair (`#f4f7fa` on `#121418`). Do not recolor by sampling a classic screenshot.

## What not to ship

- Classic `ndGUI_*.zip` theme packages, `Graphics.uvgi`, or `ControlCenter.xml`.
- Funcom GUI textures and `gfx://` art used as the skin itself. A later build may borrow a native icon only through `ui.icon` for a hotbar slot the client already owns. That is not this frame set.
