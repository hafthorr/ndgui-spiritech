# Changelog

Versions follow Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH`.

- MAJOR bumps when a saved config field changes meaning or is removed.
- MINOR bumps add themes, windows, or config fields a 0.1 reader can ignore.
- PATCH bumps fix tokens, scale math, or docs without a config change.
- While the major version is 0, the client view layer is still incomplete. The Lua model is safe to load offline.

## 0.2.8

- The project moved to **GitHub: https://github.com/hafthorr/ndgui-spiritech**. The installer's updater and its download links now read releases from there. Installers from 0.2.7 and older still look on GitLab, which is gone: download this release by hand once (Releases on the GitHub page), and the updater works from then on.

## 0.2.7

- **Mission Hub** (new package; replaces the Info, Missions and Mission Terminal windows):
  - **Info keeps each mission briefing you look at**: cash, XP, zone, item reward and description, shared by all your characters.
  - **Missions**: the list with draining time-left bars (blue, yellow under 30 min, red under 10) and a side pane with the chosen mission's briefing, pay, zone and reward. Left-click a row to show it, right-click for the stock menu. **Folds** to its title bar with the time left (`Missions (2) - 1:20`) and comes back at its old height.
  - **Mission Terminal**: offer rows with the summary; offers you've Ctrl-clicked once show pay, zone and reward. **Watch list** (comma separated) lights matching offers gold, matching the briefing and reward too, and logs this session's matches. Four slider **presets** (left-click applies, right-click saves, auto-named), all seven sliders, roll counter, credits spent on chosen-reward rolls, recent chosen rewards.
  - Each new offer still needs one Ctrl-click: the client gives its details only to the Info window, and only on a real click.
- **Compass** redrawn: outlined dotted strip with N / E / S / W that reads on light and dark ground, a green waypoint marker pinned to the edge, a caret, and the distance. Without the ndGUI skin it keeps the old framed compass.
- **Team**: **Compact** button (name, level and health bar only), remembered with the window.
- **Target panels**: long names scroll inside their box; HP text turns black on bright (green, yellow) bars.
- **Local Map**: after zoning it re-applies the zoom and keeps centring on you until your position arrives. If the map is still black after logging in or zoning, close and reopen it: the stock map does the same (client bug).
- Installer: packages replaced by the Mission Hub (`ndgui-info`, `ndgui-missions`, `ndgui-mission-terminal`) are removed on update.

## 0.2.6

- **Team window**: every member is a unit frame like the target panels: profession portrait, name and level, exact HP with the damage ghost and low-HP pulse, nano, profession / side and distance. The leader gets a green name and stripe; absent members are greyed. Click to target, right-click menu, NCU strips, Leave and Recruit work as before.
- **Floating combat numbers** on target panels and team frames: damage, bigger yellow crits, healing, misses (from the game's combat feed).
- **Target-of-target**: the target panel shows who your target is attacking (`» You` in orange), for 8 s after its last attack.
- **Damage Meter** (new addon window: Control Center > Actions > Addons > Damage Meter):
  - **Damage / Healing / Taken / Targets / Deaths** as skinned bars: amount, per second, share.
  - **Click a row** for its breakdown: abilities (weapon by damage type, named specials, nanos, shields) with hits, crit %, biggest hit; who hit a target; or the last 10 hits before a death.
  - **Live per-second graph**, a stat strip (crit, miss, biggest hit, best 5 s burst) and a fight clock that ticks while you fight.
  - **Me / Team / Raid / All** (default Me), **fight history** (`<` `>`, last 10, named after the main enemy), **Overall**, **Pets** folded into you, players tinted by profession.
- **Nameplates** (new provider, `prk.nameplates`): clean overhead names with a thin outline, a framed health bar in soft consider colours (green, amber, red), organization in muted steel, thin corner ticks for selected (blue) / attacking (red), one dark panel when backing is on. GM / PvP / roleplay tags and distance scaling as stock.
- XP / AXP (and HP / NP) numbers get thousands separators like the credits counter: `1,396 / 4,500`.
- Changing any ndGUI file needs a full game restart (the client reads addons only at launch).
- The unit frame lives in ndgui-lib (`unit.xml`, `lua/unit.lua`); Team is now a hand-made package instead of a generated fork.

## 0.2.5

- **New target panels**: proper unit frames with a profession portrait (or the level for NPCs), name and level, exact HP like `941 / 941 (100%)`, a pale ghost of damage just taken that drains away, a pulsing fill under 25%, nano bar, profession / side, distance and a reach dot. Double-click for **Lock**, **Size** (S / M / L) and **Compact**. Saved per panel.
- **Fix:** HP/NP bars and target panels now remember their position, Lock and Flat / Size across relogs (the saved values were read too early and came back empty).
- HP, nano, XP, AXP and target bars are smooth fills, no more segment blocks.
- `install.py --update` (and menu option 2) for Linux/macOS: installs the newest GitLab release (`git pull` in a checkout, otherwise downloads the source).

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
