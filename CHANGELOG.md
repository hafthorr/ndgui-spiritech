# Changelog

Versions follow Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH`.

- MAJOR bumps when a saved config field changes meaning or is removed.
- MINOR bumps add themes, windows, or config fields a 0.1 reader can ignore.
- PATCH bumps fix tokens, scale math, or docs without a config change.
- While the major version is 0, the client view layer is still incomplete. The Lua model is safe to load offline.

## 0.2.0 (first public release)

- **Full HUD and window replacement**: 39 packages; every `core.window` window and most HUD roles on the DarkTech frame.
- **Installer** with no Python needed: release zip with `install.bat` / `install.ps1`; install, update, keep-stock-screens and uninstall; `*.stock` backups of everything.
- **Hotbars** rebuilt: plate, recessed slots, `1`–`0` labels on the active bar, spinner drag handle.
- **Square 3-slice buttons** everywhere, including the game's own screens; titlebar caps; pin state visible.
- **DarkTech skin**: tabs, scrollbars, dropdowns, item slots, sliders, steel retint of stock teal; real labels instead of blurry baked text (high UI scale).
- **Local Map**: toolbar, follow, trail, range rings, marker filters, minimap mode, live world X/Z, cursor position + distance, self-calibrating scale. (Map waypoints parked: the native command refuses.)
- **Planet Map**: toolbar, zoom readout, follow, mission route, mission distance + bearing, DarkTech beacons.
- **Lists**: right-click a column header to move or hide columns, remembered per list.
- Restyled NCU, target NCU, faction, chat, chat config, raid bars, timer bars, team invite, sneak indicator, logout countdown.
- License: WTFPL.

## 0.1.0

- Research note and design spec for ndGUI 4.3.4.x behavior and the in-tree Spiritech Lua export.
- Four themes: Classic Dovvetech, DarkTech, DarkTech Mini, Adaptive.
- Config round-trip, Quick Options, SoftMenu catalog, one-row menubar (anchors, float, fade, auto-hide).
- Clamped health, nano, and XP fractions; static hotkey labels; horizontal and vertical shortcut bars.
- Inventory, chat, raid/group, and options, each with an enable flag. Compact raid rows are shorter.
- Logical-pixel layout from 1080p through 5K. Client `pixel_scale` is not applied twice.
- Host probes use exported names. A missing call is reported and load still returns.
- Original nine-patch and icon spec. No classic texture pack.
