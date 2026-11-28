# Changelog

Versions follow Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH`.

- MAJOR bumps when a saved config field changes meaning or is removed.
- MINOR bumps add themes, windows, or config fields a 0.1 reader can ignore.
- PATCH bumps fix tokens, scale math, or docs without a config change.
- While the major version is 0, the client view layer is still incomplete. The Lua model is safe to load offline.

## Unreleased

- **Market.** Cancel order shows Confirm cancellation and Keep order, labels and all. Those two were an empty frame.
- **Intel.** Hiding the strip also closes the Log and Alts, and a later login leaves them closed. An old name or tell no longer pops the banner again on every login.

## 0.4.2

- Intel strip: an x on the right hides the XP and credits bar. `/ndgui hud` shows it again.

## 0.4.1

In Options, set Mission terminal to Notum Dovvetech Mission Terminal. Info and Missions stay on Mission Hub.

- **Skills IP priorities.** Save Priorities, Cancel, and Restore defaults never appeared, and Save Changes and Close were empty frames, so the edit could not be saved. Those buttons show and hide with their frames.
- **Buff Watch.** Hover lists the same lines as the NCU tooltip: kind, NCU cost, nano cost, time left, radius, range, attack, recharge, modifiers, and the description. Shift-click opens the nano description.
- **Mission Terminal is its own package again** (`ndgui-mission-terminal`). The hub was attaching the offer map to a blank frame, and the built-in terminal came back. This package attaches the map while it loads. Info and Missions stay together and still share briefings. The terminal cannot read those briefs. Offer pay, XP, zone, QL and rewards still come from the server.
- **Empty button frames.** Showing or hiding a button shows or hides its frame. Market Confirm cancellation was an empty frame you could not click. Chat Config section headings and the window list were blank frames because the label was written on the frame. The name, selection, and click are on the button now.
- **Intel.** Options > Interface > Intel can turn off the XP and credits per hour strip, and the banner for your name, a tell, or a watch word. Clicking that banner no longer takes down floating combat text and the zone notice.

## 0.4.0

Needs the game client 0.3.5 (addon API 0.2.0) or newer. Run the installer again: the new Intel package takes over the chat role.

- **Intel** (new package `ndgui-intel`: chat, overhead combat text and zone notice in one package; its parts share data through `ndgui-lib/bus.lua`):
  - **Intel strip**: XP / alien XP / credits per hour, time to next level, session clock; Alts / Log / reset buttons. Movable.
  - **Alerts** for tells, your name and watch words (banner + a marker on the chat line), and a **Log** of this session's alerts and loot.
  - **Alts**: level, XP, credits (with a total), last zone, last played and raid locks of every character you play on this PC.
  - **Commands**: `ndgui alts | log | hud | reset | watch <word> | unwatch <word> | words`.
  - **Overhead combat numbers** in ndGUI style: quick hits merge (`2,340 x5`), big hits and crits pop in gold. Options > Combat > Floating combat text.
  - **Zone notice** in ndGUI colours.
- **"Which character has it?"**: bag and bank windows remember their items per character; their search box shows `Alts: N` with where else the item is.
- **Target Debuffs** (Buff Watch): your effects on the target, and a red REAPPLY row for any part of your learned rotation that's missing.
- The chat role moved from the generated `ndgui-chat` to `ndgui-intel` (the installer removes the old package).
- **Compass** reads on light ground again. The outlined strip is back at full width. With the ndGUI skin it uses the atlas art. Without the skin (the marketplace suite) it slides a 320 px window of that same strip as you turn, instead of stretching one sliver.
- **Local Map and Planet Map** use the custom markers when those graphics are in the skin. Otherwise they use the stock icons, which stay visible. Trails, rings, the route and the reticle stay dots and lines.
- **Control Center** wings, minibar and menubar use the stock tab and status-bar art again, which the installer retints.
- **Window titles** no longer have a rectangle behind the word. **Wear**'s page tabs are ndGUI buttons.
- Wrapped buttons hide their frame when the button is hidden, so an empty chrome frame does not stay on screen.
- **Skills:** the category and action columns sit in from the left edge again. Hidden priority buttons no longer leave an empty frame.
- **Floating combat text** no longer unloads the package when a number is at the edge of the screen.
- **Mission Terminal offer rows** no longer have a button bar through them. Clicking the row still picks that offer.
- **Mission Terminal** can be resized. The offer list scrolls when the window is shorter. With the map open, extra width goes to the map.
- Linux and Mac: the release zip includes `install.py`.

## 0.3.7

- **Mission Terminal shows every offer's pay, XP, playfield, QL and reward right away** (client 0.3.5 sends them with the offers), so no more Ctrl-clicking each offer into Info. The watch list matches the reward and playfield straight away too.
- **Mission Terminal offer map** (client 0.3.5+): the planet map beside the offer rows with a numbered marker per offer (gold when it matches your watch list, ringed when selected) and you. Click a number to pick that offer; drag to pan, mouse wheel or `-` `+` to zoom; the **Map** button hides it.
- **Troubleshooting:** type `/uidebug` in chat to see every UI package and the error of a failed one (README, INSTALL.md).
- Release packages carry `version` and `apiVersion` in their package.xml (the published-addon format the launcher checks).

## 0.3.6

Needs the game client 0.3.5 (addon API 0.2.0) or newer.

- **Control Center works again on client 0.3.5.** The update no longer sends the minibar / rollup / advanced Agg/Def options to the Control Center, which broke ndGUI's (gone from the screen, and players reported the camera stuck). Those four options are now ndGUI's own Options settings, read the new way. Thanks matty-jones for the first fix (#2).
- **Installer: `--keep-providers` / `-KeepProviders`** updates ndGUI's packages, skin and screens but leaves your Options > Interface & HUD > UI packages choices alone (for mixed setups). Thanks matty-jones (#1).
- **Nameplates** draw again: the client now places plates itself.
- **Planet Map and Local Map** markers are back (you, mission, route, rings, playfield markers): the marker call takes a new scale argument.
- **Mission Terminal** takes the client's new offer-map callbacks (ndGUI's terminal has no map yet).
- Raid bars and target NCU keep their Options (Lock raid bar positions, nano/fight target NCU).
- Grid Overlay and Damage Meter never take mouse input outside their own windows.

## 0.3.5

- **Hotbar:** perk timers really show big in the slot centre now, like item cooldowns. The client sends them as badge text, which 0.3.3 didn't move.

## 0.3.4

- **Buff Watch:** short buffs (under 1 minute, like team auras) no longer turn into amber warning rows; they stay small icons. Right-click any buff → **Don't warn about this buff** keeps it an icon and out of the alerts banner. The window menu's **Show hidden buffs again, warn about all** undoes it.

## 0.3.3

- **Hotbar:** perk timers now show big in the middle of the slot, like item cooldowns, instead of small in the corner. Stack counts stay in the corner.

## 0.3.2

- **Grid Overlay** (Control Center > Actions > Addons > Grid Overlay): shows the snap grid over the whole screen, with amber lines through the screen centre, to line up and centre windows and HUD pieces. It takes no clicks; close it from the same menu when done. Small grids draw every 2nd / 3rd line (at least 20 px apart) so it stays readable; every 5th drawn line is brighter.

## 0.3.1

- **Snap to grid.** Moving or resizing any ndGUI window or HUD piece (bars, hotbars, compass, target panels, maps...) now lands on a 10 px grid. It follows the game's own snapping switch: Options > Interface & HUD > Windows and HUD > magnetism above 0 turns on edge snapping and the grid, 0 turns both off. Snapping to another window's edge still wins when it is in reach. Grid size (any number of pixels, 0 = off): installer menu **Snap-to-grid size**, or `python install.py --grid 20`; updates keep your choice.

## 0.3.0

Needs the game client 0.3.4 or newer (the installer says so on an older game).

- **Client 0.3.4:** lists use the game's own column menu everywhere: right-click a header to show / hide columns or Move Left / Move Right, or drag a header to move it. Column orders and hidden columns saved by older ndGUI carry over. Control Center: **Attack Actions** lists your attacks (like Perk Actions), **Control Panel** opens Actions, **Settings** opens Options. The docking column lets clicks through where no page is. The Mission Terminal no longer reopens at login; Info shows "Label: value" lines in two tones.
- **Buff Watch shows what needs attention.** Rows are now only for debuffs on you, buffs about to run out (amber) and buffs you pin; every other buff is a small icon strip under them (hover: name, time left, cast by you or someone else). A buff moves up to a row when it has less than the warning time left (window menu: 30 s / 1 min / 5 min, and never before the last quarter of a short buff). Right-click a buff: **Always show as a row** or **Hide this buff**; the window menu has **Show hidden buffs again** and **Show every buff as a row** (the old list). The window is as tall as what it shows.

## 0.2.12

- **Health / Nano bars: four sizes.** Double-click a bar; the strip now has **Size** next to Lock and Flat and cycles S / M / L / XL (M is the old size). Works upright and flat, saved per bar.
- Nameplates: targeting one of two same-named mobs at the same health no longer marks the other one as selected (the guess is only used on attacking plates, where the client hides the selection).

## 0.2.11

- **Docking column** in ndGUI's Control Center (Options > Interface & HUD > Show rollup panel): a solid dark column down the right edge. **Right-click** a window's title, move the mouse to the column (no button held), **left-click** to dock it; the same undocks it or moves it in the stack. The game lets these dock: Actions, Team, Local Map, Friends, Missions, Inventory, NCU, Nano Programs, Planet Map, Stats, Wear, Tradeskills, Faction (not addon windows like Buff Watch). Wide windows are cut to the 190 px column. The opacity slider fades the column.
- **Minibar** (Show minibar): the nine small window buttons top right; the column starts under it.
- Docked pages: the scroll bar of a tall stack gets its own lane instead of covering the pages, and pages are no longer shifted (cut off on the right). Titles that change (NCU (2/10), Inventory, Missions...) also update on the docked page. **Team** docked fits the column: narrower Compact / NCU buttons, Leave and Recruit share the rest, and the page is as tall as its members (no empty floating height).

## 0.2.10

For the Spiritech client update of 14 November (window snapping, right-side docking, Control Center minibar, 1-10 hotbars, column hiding).

- **The game crashed at start after the client update if you re-ran the ndGUI installer.** The installer patched the game's screens from backups taken before the update, so the game got old versions of screens it had just replaced. Backups now follow game updates (a file that isn't ndGUI's own is the new original), and the installer only swaps in screens built from the same game version; any other screen stays stock, with a warning. Uninstall no longer puts back outdated backups either.
- **ndGUI windows fell back to stock after the client update.** The window and panel frames have the parts the new docking code needs.
- **List columns**: the game now hides columns itself; ndGUI uses that on every list (not just inventory, bank and bags) and keeps its own column moving. Right-click a header: Move left / right, Reset column order, the columns, Show all columns. Columns you had hidden stay hidden.
- **Hotbar**: no more 1-0 labels. The client doesn't tell addons your key bindings, so they were a guess.

## 0.2.9

- **Buff Watch** (new package; Control Center > Actions > Addons):
  - **Buff Watch**: your buffs and debuffs with icon, time left and a draining bar. Debuffs first in red, then soonest to end; amber under 1 minute, red under 15 s, the time blinks in the last 10 s. Under it, what you put on your target (your DoTs and debuffs, or your buffs on a friend). Targeting yourself says so instead of listing it twice.
  - **Team Buffs**: one row per member, one column per buff anyone on the team has (most common first). Each cell shows the time left; red means missing, and the name shows how many (`Bob  -1`). Click a member to target them.
  - **Alerts** under the compass: low health (under 30%), a debuff landing on you, low nano (under 20%), a buff of 1 minute or more ending within 15 s. Toggle from the Buff Watch title icon menu.
- **Nameplates**: the client reports one bracket state per plate, so a mob that was attacking you lost its "selected" look when you targeted it again. Your target now always gets the blue ticks, and a target that is also attacking shows blue outside the red.

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
