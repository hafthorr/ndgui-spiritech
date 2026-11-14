# Changelog

Versions follow Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH`.

- MAJOR bumps when a saved config field changes meaning or is removed.
- MINOR bumps add themes, windows, or config fields a 0.1 reader can ignore.
- PATCH bumps fix tokens, scale math, or docs without a config change.
- While the major version is 0, the client view layer is still incomplete. The Lua model is safe to load offline.

## 0.2.4

- **Fix:** XP / AXP bars were replaced by the stock ones in 0.2.3 (the bar code looked for a shadow label only HP/NP have). The offline tests now treat a missing view as an error, like the game does.
- **Installer: Update to the newest version** (menu option 2, or `install.ps1 -Update`). It asks GitLab for the latest release, downloads it and installs it when it's newer than what's installed. Menu numbers changed: Uninstall is now 4.
- Docs: HP/NP Lock / Flat, the updater.

## 0.2.3

- **HP/NP bars**: double-click one for a small **Lock / Flat** strip. Lock keeps it in place; Flat lays it horizontally with the number inside. Saved per bar.
- HP/NP numbers sit on a dark plate with a drop shadow, readable over bright ground.
- **Window frame** padding and title bar now add up exactly like the game expects: grids (loot, bags, bank) no longer slide under the scrollbar, and long titles no longer push the close button off the edge.
- **Lists**: fixed-width icon columns get a header divider; moving a column keeps its width (it used to swap widths with its neighbour).
- Linux/macOS: the skin step finds a bold font (since 0.2.1).

## 0.2.2

- Bugs, issues, ideas: ask **thedenis** on the Project Rubi-Ka Discord. Shown at the top of the README and at the end of the installer.

## 0.2.1

- Linux/macOS: `install.py` no longer dies in the skin step looking for a Windows font (`OSError: cannot open resource`). It finds DejaVu/Liberation/Noto, asks `fc-match`, or uses `$NDGUI_FONT`.
- Releases are published by GitLab CI when a `v*` tag is pushed.

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
