# Design: ndGUI for Spiritech, v1

> Background notes from the first (v0.1) design pass. The packages have moved on since (see the top-level README); kept for the research and design rationale.

A native recreation of the Notum Dovvetech workflow. Visual recognition comes from original tokens (color, frame, density), not from classic texture packs. The pure core under `ndgui/` does not touch a client. `main.lua` is the package entry and no-ops any probe the host did not provide.

The client export in Lua API docs (shipped with the client in `client/docs/lua-api`) is the binding source. Lines below that the export does not state are marked ASSUMPTION.

## v1 (this package)

- Theme engine with four themes: `dovvetech` (Classic Dovvetech), `darktech` (DarkTech), `darktech_mini` (DarkTech Mini), and `adaptive` (the modern/adaptive variant). Switching themes swaps color, frame/border, and density tokens. Windows read those tokens. They do not carry their own copies.
- Config round-trip for theme, opacity, the user UI scale, menubar anchor, layout preset, raid preset, shortcut orientation and order, SoftMenu assignments, Quick Options, and an enable flag for the menubar, each HUD element, and each key window.
- Resolution band from 1080p through 5K. Layout is in logical pixels. The same preset at two UI scales produces rectangles scaled by that factor, to the nearest pixel.
- Slim menubar: one control row; anchors `top`, `bottom`, `left`, `right`; floating; fading; main-menu auto-hide.
- SoftMenu assignments chosen from a catalog that opens inventory, chat, raid/group, and options.
- Quick Options: Lock Wear, Lock Shortcutbar, Lock RaidBar, Inspect, Auto-AFK, Social, Show All Names. These are package preferences. The export does not list matching game commands.
- HUD: health, nano, and XP as clamped current/max fractions; compass; target frame; shortcut bars with static hotkey labels and a horizontal/vertical axis.
- Key windows: inventory, chat, raid/group, options. The compact raid/group preset uses a smaller row than the standard preset.
- Host adapter. Unbound probes are reported unavailable. Load still returns. The encoded config fits the documented 4096-byte storage value.

## v2 (later)

- Token tables for dovvetech dark, dovvetech edge, darktech mini HUD, and darktech glass.
- View XML once a widget schema is in the export. `TextView` and `BitmapView` are named; a full vocabulary is not.
- More SoftMenu targets when those windows exist.
- A Hotbar role package, if we ever replace the built-in bar. That package cannot also register standalone windows.
- Agg/Def, creds, NCU, mail, and the extended combat menus.
- Bitmap nine-patches painted from [assets.md](assets.md).

## Resolution and client scaling

Spiritech places widgets in logical pixels. `ui.pixel_scale_x` and `ui.pixel_scale_y` already say how many framebuffer pixels one logical pixel covers. Multiplying layout by that scale would draw a 4K panel twice as large as the client asked.

The reference layout is 1920×1080 logical pixels, which is 1080p. `layout.resolution` then does three things:

1. Reads the logical viewport. On the client that is `ui.parent_width` / `ui.parent_height`. Offline, the caller passes `input.screen`. If neither is present, the viewport is the 1080p reference.
2. Sets a viewport factor of `min(width/1920, height/1080)`, clamped to the closed band from 1080p (factor 1) through 5K (5120×2880, factor 5120/1920). A smaller window does not shrink chrome. A panel above 5K stays at the 5K factor until the user raises `ui_scale`.
3. Multiplies by the user `ui_scale` (default 1). That product is the layout scale passed to `layout.place` and to the menubar thickness.

`pixel_scale` is stored and is not part of the product. Two 4K setups then agree in physical pixels, rounding aside:

- Client already scaled: logical 1920×1080, `pixel_scale` 2. Layout scale stays 1. A 22px row is 44 framebuffer pixels.
- Logical pixels are the panel: logical 3840×2160, `pixel_scale` 1. Layout scale is 2. The same row is 44 logical pixels and 44 framebuffer pixels.

5K is the same pair: logical 5120×2880 at pixel scale 1, or logical 1080p at pixel scale 5120/1920. `layout.font_px` clamps to the documented `ui.font_size` range, 1 through 256.

Menubar thickness is one theme row times the layout scale. It is never a second row. The bar pins to the logical viewport edges, so a 3840-wide view anchors to 3840, not to a hardcoded 1920.

## Layout principles

Scalability: rectangles and the menubar go through `layout.scale_px` (nearest logical pixel). Theme density changes the base row, bar, and font before that multiply.

Resolution independence: presets store reference pixels for 1920×1080, not a fraction of a 1024×768 skin. The live viewport supplies the edges.

Space efficiency: one menubar row, short bars on DarkTech Mini, an `efficient` preset that keeps windows on the edges, and enable flags so an unused element is absent. Default type sizes stay in the low teens except Adaptive, which raises the font for a 4K logical viewport that would otherwise look thin.

Anchors and the shortcut axis are config, not separate XML files. Hotkey labels are a function of the slot index inside its own bar (`1`–`9`, then `0` for slot 10). That matches the native hotbar note that row ten is labelled zero. Hiding a bar or reordering bars does not renumber the bars that remain. ASSUMPTION: a standalone package cannot read `HotbarState`, so v1 stores orientation itself instead of writing `HotbarState.vertical`.

## Modules

| Module | Role |
| --- | --- |
| `ndgui/init.lua` | `load` builds a session. `format_observable` prints a stable summary. |
| `ndgui/theme.lua` | The four v1 token tables. |
| `ndgui/catalog.lua` | SoftMenu actions that open shipped windows. |
| `ndgui/config.lua` | Defaults, coercion, sandboxed encode/decode, 4096-byte check. |
| `ndgui/layout.lua` | Preset rectangles, 1080p–5K factor, nearest-pixel scale. |
| `ndgui/host.lua` | Real probe names. Missing calls become `unavailable`. |
| `ndgui/menubar.lua` | One-row bar, anchors, float, fade, auto-hide, SoftMenu, Quick Options. |
| `ndgui/hud.lua` | Bar fractions, compass, target, static hotkeys, axis. |
| `ndgui/windows.lua` | Inventory, chat, raid/group row size, options view. |
| `main.lua` | Client entry. Loads the core even when `ui` and `game` are absent. |

`load` publishes `session.elements`. A false enable flag omits that element.

Unknown theme ids fall back to `dovvetech` and record a warning. Unknown anchors fall back to `top`. Unknown layout presets fall back to `classic`. Unknown raid presets fall back to `standard`. A corrupt config string falls back to defaults. None of those paths abort the load.

## Visual language

Shared rules: square-to-barely-rounded frames, one header strip, flat bar tracks, no photographic metal. Fonts are a logical face, `ndgui-sans`, with the client sans as the fallback. Sizes are the theme’s `font_px` after layout scale, clamped to 1..256. Icons are 16px geometric glyphs specified in [assets.md](assets.md). Text colors below are the adjusted text colors for that theme.

Token values are original. They follow the public theme roles (orange Dovve accent, blue Dark accent, short Mini bars, heavier Dark frame, a higher-contrast modern variant). They are not measurements of ndGUI bitmaps.

### Classic Dovvetech (`dovvetech`)

Cool steel panels, light cool text, orange accent for the Dovve compass marker.

- Colors: panel `#24384a`, border `#8fb4cc`, text `#e7f2f8`, dim `#a9c6d6`, accent `#e07a2f`, health `#d24b4b`, nano `#4c92d4`, XP `#e0b341`, track `#152430`, menu `#1b2c3b`.
- Frame: `beveled`, 2px border, 0 radius, 18px header.
- Density: `standard`. Menu row 22px, bars 16px, font 12px, gap 4px, padding 4px. Raid rows 22px standard, 15px compact.

### DarkTech (`darktech`)

Near-black navy, blue accent, more frame than Mini.

- Colors: panel `#0e141b`, border `#3d6f9a`, text `#c5d7e6`, dim `#7f9bb0`, accent `#3d8fd4`, health `#c44747`, nano `#2f7ec4`, XP `#c6a24e`, track `#080c10`, menu `#0a1016`.
- Frame: `pronounced`, 3px border, 0 radius, 20px header.
- Density: `regular`. Menu row 24px, bars 18px, font 13px, gap 5px, padding 6px. Raid rows 24px standard, 16px compact.

### DarkTech Mini (`darktech_mini`)

Same dark family, less chrome. Short bars are the point.

- Colors: panel `#141a20`, border `#5c7c90`, text `#d0dde6`, dim `#8aa0b0`, accent `#67c3d4`, health `#d05a5a`, nano `#3d92c8`, XP `#d1b15e`, track `#0c1014`, menu `#10161c`.
- Frame: `hairline`, 1px border, 0 radius, 14px header.
- Density: `mini`. Menu row 16px, bars 8px, font 11px, gap 2px, padding 2px. Raid rows 16px standard, 11px compact.

### Adaptive (`adaptive`)

Higher contrast for a large logical viewport, flat frame, larger type.

- Colors: panel `#121418`, border `#d7dde4`, text `#f4f7fa`, dim `#b7c0c8`, accent `#ffb020`, health `#ff5d5d`, nano `#59a6ff`, XP `#ffe08a`, track `#08090b`, menu `#181c22`.
- Frame: `flat`, 1px border, 3px radius, 18px header.
- Density: `adaptive`. Menu row 20px, bars 12px, font 15px, gap 6px, padding 6px. Raid rows 20px standard, 13px compact.

## Config document

One table, encoded as a Lua literal in an empty environment. `core.storage` can hold that string under the key `config` when it is at most 4096 bytes. The store is per installation, shared by characters on this machine. It is not the account cloud sync from the Spiritech announcement. The string is still plain text, so a later sync tool can move it.

Fields that survive a round-trip:

- `theme`, `opacity`, `ui_scale` (user multiplier, not the resolved viewport factor), `layout_preset`
- `menubar.anchor`, `menubar.floating`, `menubar.fading`, `menubar.auto_hide`, `menubar.enabled`
- `elements.<id>` for `menubar`, `health`, `nano`, `xp`, `compass`, `target`, `shortcutbar`, `inventory`, `chat`, `raid`, `options`
- `quick_options` for the seven toggles
- `softmenu` slots whose `action` is a catalog id
- `shortcutbar.orientation`, `shortcutbar.order`, `shortcutbar.hidden`
- `raid.preset` (`standard` or `compact`)

Layout presets are `classic`, `efficient`, and `wide`. They place windows. They do not restyle them. The raid/group preset is independent.

## Host boundary

Probes use the exported names: `ui.pixel_scale_x`, `ui.pixel_scale_y`, `ui.parent_width`, `ui.parent_height`, `ui.place`, `ui.font_size`, `ui.fill_color`, `ui.text_color`, `ui.opacity`, `ui.fade`, `ui.progress`, `ui.storage.read`, `ui.storage.write`, `game.character.subscribe`, `game.team.subscribe`, `game.targeting.subscribe`.

`load` returns `ok = true` when the package itself is intact. `session.unavailable` lists probes that were not functions. `session.host.call` returns `false, "unavailable"` for those names. A bound function that throws is caught and returned as `false, "error"` so one bad call cannot unwind the load.

Vitals on the client come from `CharacterBar`. Offline, `load` accepts a snapshot with `current` and `maximum`. The fraction is always our clamp of current/max when those numbers exist. A native `fraction` is used only when current and maximum are both absent, and it is clamped again.

## API assumptions

- ASSUMPTION: The package script can `require("ndgui")` after `main.lua` prepends the package directory to `package.path`. The export documents `ui.require` for library modules and `ui.load` for XML, not `require` of the package’s own tree.
- ASSUMPTION: `ui.parent_width(nil)` and `ui.parent_height(nil)` report the viewport. The export says an unattached view uses the viewport, and it requires a view argument. The adapter pcalls. A throw falls back to `input.screen` or 1920×1080.
- ASSUMPTION: Idle fade is opacity 0.35 while the pointer is off a fading bar, and 1 otherwise. `ui.fade` is a boolean plus an optional tint. The classic low/high fade sliders are not in the export. Floating insets the bar by 12 reference pixels (scaled) from the anchored edge.
- ASSUMPTION: `ndgui-sans` is a logical font name. The client supplies a sans face. This package does not embed a font file.
- ASSUMPTION: Opening a window is a catalog action id. It is not a verified command. Quick Options do not call native lock or nameplate APIs; they persist in config.
- ASSUMPTION: Compass heading and shortcut slot contents are snapshot fields. Standalone addons do not receive `compass_apply` or `hotbar_apply`. `game.team.subscribe` is the raid/group roster source when the host provides it; v1 row size does not depend on that callback.
- ASSUMPTION: No view XML is shipped. Inventing tags would risk the client disabling the package. `main.lua` reads `ui.storage` key `config`, loads that text, and writes the normalized document. An empty string seeds defaults. A failed read or a document that fails to decode is left in place. It does not call `ui.load`.
