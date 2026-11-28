# Progress

## Empty chrome, Intel crash, Intel options (2026-11-27)

Grious, `~/Downloads/LinkCrash1.png` and `LinkCrash2.png`. Clicking the "someone said your name" banner failed `notum.ndgui-intel` Floating combat text and Zone notice. Both stacks are `hud.lua:99` indexing global `os` (`os.date`) from `render_log`, reached through the bus poll in `floating_text_tick` / `zone_notice_apply`. The addon sandbox has no `os`, and the index happens before `pcall`, so a log line takes the role down. The log window stays marked open, so the next mention does it again after a relog. `clock_of` now calls `os.date` inside the `pcall` and otherwise formats the unix milliseconds. `drive` also catches a HUD tick error so combat text and the zone notice stay up.

The XP/hr strip and that banner had no switch. Options > Interface > Intel: **XP and credits per hour** and **Name and tell alerts**. `/ndgui hud` still hides the strip when the option is on.

Market confirm is the Skills empty-frame bug. `square_buttons.py` moves `visible="false"` onto `ndgui_btnwrap`. `ui.visible` on the Button hid the label and left the frame, and a frame that started hidden never came back, so Confirm cancellation was an empty unclickable box. `ui.find` and `ui.child` are not the same value, so `button.lua`'s child map missed `ui.visible(ui.find(...))`. The find hook now remembers the handle it just returned and shows or hides that wrap. `tests/test_button_wrap.lua` uses a different find handle from the child and checks Confirm's hidden wrap.

Full audit, 2026-11-27 night: parsed every `ndgui_btnwrap` in the live Addons tree and in `addons/` (407 XML files, 234 wrapped buttons, 30 packages). Then traced every `ui.visible` call back to a wrapped button name, including `view("name")` and variables assigned from `ui.find`. Lua shows or hides only these wrapped buttons:

- Market `confirm_cancel`, `keep_order` (wrap starts hidden), `cancel_order`. `view()` is `ui.find` after `filters.lua` loads grid, which loads the hook.
- Skills `reset_all`, `accept`, `quit`, `restore_priorities`, `save_priorities`, `cancel_priorities`. `show_priority_button` sets the wrap and the button. The three that start hidden are the last three. `reset_skill` sits inside `reset_area`, which is hidden as a parent. Skill row +/- and priority arrows are not wrapped.
- Terminal `map_toggle` (wrap starts hidden) and `reward_clear`. Both are `ui.find` after `win_terminal.lua` requires button.
- Team `leave_button`, which also sets `leave_chrome`.
- Pets Attack / Follow / Wait, which also set each wrap.

No other wrapped button is passed to `ui.visible`. Hiding a parent (page, toolbar row, credits section) hides the wrap with it. Intel never loads the hook and never toggles a single wrapped button.

One miss that is not a hide/show: Chat Config `row.xml` is only the `chat_config_row` button, so after the wrap `ui.load` returns the frame. Headings and the window list set their text and clicks on that frame, and the label stays blank. `fork_hud.py` and the live `notum.ndgui-chat-config/main.lua` now find `chat_config_row` for text, selection, tooltip, and clicks, and still add and destroy the wrap. Restart. Not tagged.

Release 0.5.0. The dev client is replaced from `release/ndgui-0.5.0.zip` after the tag. `Client.xml` and `.installed.json` are not touched by that copy. Restart to load it.

## Buff Watch NCU details (2026-11-27)

Screenshots `Pictures/Screenshots/Screenshot_20261127_145000.png` (NCU) and `Screenshot_20261127_145013.png` (Buff Watch), both hovering Composite Physical Special Expertise. NCU tooltip is `ncu.presentation`: kind, NCU cost, nano cost, remaining, total, radius, range, attack, recharge, one modifier line each, then the description. Shift-click opens the nano description because the slot is `ui.bind`ed to the effect reference (same as the team NCU strip). Buff Watch only showed name, "Cast by you", and the description, and never bound the row.

`addons/ndgui-watch/main.lua` now builds that tooltip from the observed effect (seconds converted to the centiseconds `ncu.presentation` expects) and binds each buff row and icon to `effect.reference`. Right-click pin/hide is unchanged. The hint line is "Shift-click: full description". Copied into the live `notum.ndgui-watch`. Restart the client. Not tagged.

## Grious: Mission Terminal split out of the hub (2026-11-27)

`~/Downloads/image.png`. Options had Missions and Mission terminal on `notum.ndgui-mission-hub`. The open window was the built-in: "No missions loaded" is only in `UI/Packages/MissionTerminal/content.xml`. The debugger row selected was `MissionTerminal / Mission Terminal`. Header said 0 failed. `/uidebug` drops disposed instances, so that does not mean the hub's terminal role survived. A role whose provider cannot init is rebuilt as the bundled package and the Options selection stays (`UI/Packages/README.md`).

The hub attached `game.map_surface` at load onto a blank frame in every role VM, then built the real terminal only on the first `mission_terminal_*` callback. Stock and modern-ui attach once, while the terminal package loads, on the widget that stays. `win_terminal.lua` will move an already-mounted `Map.pane` onto `terminal_map_host` before `Shell.window` destroys the blank; `Map.wire` only binds zoom. That move never ran for a VM that did not get a terminal callback, and the adapter wants the surface on the lasting widget at load.

Split, in the tree, not released: `addons/ndgui-mission-terminal` (`notum.ndgui-mission-terminal`) provides only `prk.mission-terminal` and requires `win_terminal` at load, so the map attaches once on the offer column. The hub keeps `prk.info` and `prk.missions` and still shares briefings through its own `ui.storage`. The terminal cannot read those briefs. Offer pay, XP, zone, QL and rewards still come from the server. Options stays one row per role. Info and Missions stay on the hub. Mission terminal has to point at the new package.

Copied into the live client (`notum.ndgui-mission-hub` and new `notum.ndgui-mission-terminal`, plus the comment-level lib edits). No plain `ndgui-*` twin. `.installed.json` was not touched. Prefs `UiPackageProvider_mission_terminal` is `notum.ndgui-mission-terminal` (Missions stays on the hub). That is the same key Options writes. The game was closed when it was set, so the next launch uses it. `lua5.4 tests/test_providers.lua`: the new hub and terminal checks pass. The same 16 failures as before (generated packages and `inventory/slot.xml` are not in git). Ships in 0.5.0.

## Skills IP priorities (2026-11-27)

Screenshot `Pictures/Screenshots/Screenshot_20261127_143333.png`: Set IP priorities on an Engineer. The +/- pickers show the installed Engineer table (Strength Medium, and the detail says Matches default). Save Priorities, Cancel, and Restore defaults are missing. Save Changes and Close are empty frames.

`ui.visible` on those Buttons hides the label and leaves `ndgui_btnwrap` up. The wraps that start `visible="false"` (Save Priorities, Cancel, Restore defaults) never get shown, so the edit cannot be saved. Closing the window drops an unsaved priority edit. `save_priorities` is what writes `ip_priorities` in `~/.local/share/ProjectRubiKa/prefs/Client.xml`, per profession. The file already has an older `2:...` value. This Engineer screen is not using it.

Fix is in `fork_windows.py` and the live `notum.ndgui-skills/main.lua`: before category buttons are parented in, record the ten content.xml wraps in order and show or hide the wrap with the Button. A 3-leaf row is chrome only when its sibling is not, so the priority detail grid is skipped. Restart the client. Not tagged.

## Dev client check (2026-11-27, after the portal publish)

The live `notum.ndgui-*` folders match the published portal zip byte for byte: 40 packages, 1579 files, version 0.4.0, api 0.2.0. Portal sha256 `9E02CF786904A8AB7719F4366A2BB0704BAF2B9B10B2B68F82257A67154EAD60`. No plain `ndgui-*` folder beside them. `notum.ndgui-chat` is gone. Intel provides chat, floating combat text, and the zone notice. `.installed.json` has no ndGUI line (mtime 2026-11-25). Prefs at `~/.local/share/ProjectRubiKa/prefs/Client.xml` were last written 2026-11-26 22:43 and still point every HUD role at `notum.ndgui-*`, except status bars, which stay `ra.curved-bars`. The game client was not running. The launcher was. Addons load when the game starts, so the next login is 0.4.0.

## Mission Terminal report (2026-11-27)


Crimson_Dawn: the Mission Terminal is not resizable, and the offer rows have small long boxes through them. Screenshot is the terminal (map open, watch list, reward rows), not the Missions list. The installed client already has both causes.

- `win_terminal.lua` used to create the window with `resizable = false`. `shell.lua` treats that as `fixed_size` and drops a drag. Fixed in the 0.4.0 tree: `resizable = true`, the layout keeps the dragged size (floor 480 px, map at least 220 px), offers sit in `offers_scroll`, and extra width goes to the map. Offer text uses the laid-out column width.
- `terminal_offer.xml` used to stack a 28 px `ndgui_btnwrap` on `offer_hit` (`label=""`). `skin_package` now leaves an empty label alone, and the row is the bare flat button again. Introduced in `8400809`, which is in the portal 0.3.7 zip and was not in the GitHub tag `v0.3.7` (`dd3f7c7`). The updater compares that tag to the install stamp, so a 0.3.7 install is told it is current.
- Shipped 2026-11-27. Tag `v0.4.0` is `43be1e9` (workflow YAML fix on top of the release commit). GitHub release: https://github.com/hafthorr/ndgui-spiritech/releases/tag/v0.4.0. Player zip matches the committed file. The marketplace zip CI rebuilt has the same 1579 files (zip checksum differs only by metadata). The first tag push did not publish: `.github/workflows/ci.yml` had the marketplace Python outside the YAML block, so Actions failed before any job. That was fixed and the tag was moved onto the fix. No release had been created yet.
- Live client `notum.ndgui-*` was replaced from `release/ndgui-0.4.0.zip` (40 packages, no extra files, other addons left in place). `Client.xml` and `.installed.json` were not touched. Portal 0.4.0 was published by hand on 2026-11-27. The file bytes match that portal zip.

## Dev install on this machine (2026-11-26)

The client is `/home/blasky/Games/PRK-Spiritech/client`. Play uses the
marketplace addon, not the install script.

Purged the script install on 2026-11-26 while the game was open. The 12
`.stock` backups matched the live graphics, colors, layouts, and core window
file, so those game files were already the originals; the backups were
deleted. `Client.xml` and `.installed.json` were not touched. Ra, modern-ui,
and the other non-ndGUI addons stayed.

Replaced the 40 `notum.ndgui-*` folders with `release/ndgui-0.3.7.zip`, built
from this working tree (`build_release.py`). The filename is still 0.3.7
because `VERSION` is 0.3.7. The launcher has no ndGUI receipt, so it will not
swap this tree for the published zip. There is no `ndgui-*` folder beside the
`notum.ndgui-*` ones.

A small edit copies `addons/ndgui-<name>/` into `UI/Addons/notum.ndgui-<name>/`.
Generated packages are not in the checkout; a full refresh rebuilds the
marketplace zip and replaces those folders again. Do not run the install
script, do not write a receipt, and do not touch `Client.xml`. The client
reads Addons only at launch. See `.cursor/rules/dev-install.mdc`.

## Compass frames (2026-11-26)

12px slices only drew one sliver. The clip is 34px tall and had no stacked layout, so the other slices were laid out below it. A bitmap wider than its parent is also scaled to the gap at its x, which is why the single 1080px strip stretched.

The marketplace compass now keeps one BitmapView at 320x34 and swaps `compass/frame/NNNN.png`. Each frame is the wrapped 320px window of `band.png` for that scroll pixel, so the layout never resizes it. The atlas path is unchanged. Restart the client to load it.

## Compass, maps, and chrome (2026-11-26)

`8400809` (25 Nov 2026) replaced the outlined compass with unoutlined text so a marketplace
package would not reference atlas ids. Both install paths share `ndgui-compass`, so a script
reinstall kept that text strip. `band.png` was exported and never shown.

Checked `TEMP/screenshots` pixel by pixel. Original.png is the outlined strip (light ink,
1px black outline) with the world showing through the gaps. That outline is the border.
Packageable.png is the unoutlined light-blue line. A plate behind the band would cover the
sky and would not match Original. `band.png` is the outlined art: transparent ground, opaque
black outline, opaque `#C8E6FF` ink.

Both paths hide the plate and `GFX_GUI_COMPASS_FRAME`:

- Install plus skin (`graphic_width` of the assembled compass band id is greater than 0):
  atlas sprites, the same pixels `skin.py` merges.
- Marketplace (width 0): `band.png` cut into 90 slices of 12x34
  (`compass/slice/NN.png`). Each slice is narrower than `pkg_clip`, so the layout
  cannot scale it to the gap between its x and the clip edge. That gap was the
  stretch. North's first slice is x=160. Waypoint and caret stay pinned.
  Window is 320x54 plus the distance line.

The stock plate and frame are used only when those png widgets are missing. `letter.xml`
and `tick.xml` are gone. Ids are assembled (`"GFX_GUI_" .. "NDGUI_COMPASS_" .. part`) so
the marketplace scan does not see a quoted custom atlas id.

Restarting the game does not load git edits. The client reads `UI/Addons` only, and only at
launch. For a dev look, copy into the live `notum.ndgui-*` folders (see "Dev install" above).
A restart against the old client files still shows the text strip.

Maps: local and planet maps try the assembled NDGUI map ids when `graphic_width` of
that id is greater than 0 (install plus skin). `surface.sprite` appends nothing and does
not fail when the graphic is missing, so a pcall never reached the stock fallback and
the marketplace client drew no you-are-here or mission icons. Width 0 uses the stock
map sprites for entities, and the existing fan and line dots for the trail, rings,
route and reticle. The check lives in playfield `markers.lua` and planet `main.lua`,
copied into the live `notum.ndgui-*` folders on 2026-11-26. No quoted `GFX_*NDGUI_*` id.
Denis's Intel `hud_strip.xml` still has its button gfx ids; the player-zip wrap
handles those. Do not strip them.

Control-center left and right wings, the minibar, and the menubar are back to the
pre-`8400809` stock gfx (`GFX_GUI_TAB_BACKGROUND` / `ACTIVE`, `GFX_GUI_SB_*`). `skin.py`
still retints those on the install path.

`install.py` `copy_packages` calls `remove_release_packages` before copying, so a checkout
install deletes launcher `notum.ndgui-*` folders as well as `ndgui-*`.

`lua5.4 tests/test_providers.lua`: compass (atlas and png) and both maps pass, including the
no-skin fallbacks. 16 failures are the pre-existing missing generated packages plus the
missing inventory `slot.xml`.

## Title plate and tab faces (2026-11-26)

### Dark box under the window text

Removed `ndgui_tab` (`tab.png`) from `addons/ndgui-lib/window.xml`. The title word stays
in `window_title_tab`. `glass.png` and `inner.png` were not touched. After a full client
restart every ndGUI window title has no rectangle around the word.

### Wear tabs

`square_buttons.skin_wear_tabs` turns the four Wear `TabButton`s into ordinary buttons and
the existing wrap pass draws `btn19` chrome. Names stay `wear_*_tab`. `main.lua` is unchanged.
`button.lua` updates that chrome when `ui.selected` runs. Perks and chat tabs are still
engine `TabButton`s. Do not add `Button.paint` or `ui.child` indexing in Wear; that is what
aborted the package last time.

Running `square_buttons.py` peels `ndgui_slotcell` wraps and refuses to put back slots whose
shorter side is under 24 (team 16px, pet 26x18). That pass used to delete those wells. It now
leaves a sub-24 well in place. Do not "fix" team/pet NCU slots by re-wrapping them in the
under-24 branch.

### Marketplace cap

The portal cap was raised. Ship every role. Do not run `bundle_hubs.py`.

### Intel (merged from `feature/intel`, 2026-11-26)

Denis's unreleased Intel package provides chat, floating combat text, and the zone
notice. `fork_hud.py` no longer generates `ndgui-chat`. The installer deletes a leftover
`ndgui-chat` / `notum.ndgui-chat`. Inventory search and Buff Watch Target Debuffs come
with that merge. Changelog section is still `## Unreleased`, and `VERSION` is still 0.3.7.

A tag `vX.Y.Z` publishes the committed player zip and CI rebuilds `release/ndgui-<version>.zip`
from it for the Spiritech portal. CI cannot build the player zip; that still needs a client.

The player zip ships `install.py` beside `install.bat`. From that unpacked folder it installs
the prebuilt `game/` tree (no Pillow, no generators). A git checkout still builds from source.

### Floating combat text (2026-11-26)

The first overhead number unloaded the package. `ui.place` only accepts coordinates from
-16384 to 16384. `fct.lua` clamped the text, then placed the shadow one pixel further, and
that error is fatal for the whole role. The shadow is now clamped too, and a non-finite
anchor becomes 0. Confirmed in game on 2026-11-26. The portal will not replace a published
version, so the 0.3.7 zips stay as released and this fix waits for the next version.

## Hub bundling — rolled back (2026-11-25)

### What was working

One package per role (and Mission Hub, which was purpose-built). Each provider’s
`main.lua` ran at load and called `Window.create` + `ui.root` immediately. Prefs
pointed at those package ids. Marketplace visual parity (library:// buttons, slots,
compass, maps) was tested on that layout.

### What we changed (broke it)

To fit the portal’s **32-package** cap we added `bundle_hubs.py` and merged related
roles into multi-Provide hubs (chat / NCU / maps / raid / team / HUD indicators).

That approach was **not** the Mission Hub design:

| | Mission Hub (works) | `bundle_hubs.py` (crashed) |
| --- | --- | --- |
| Member code | Real lib modules (`win_info`, …) | Entire `main.lua` stuffed into a string and `load()`’d on first callback |
| Root at load | `shell.mount()` blank frame | None at first; later taped on `shell.mount()` without adopting into it |
| Window fill | `shell.window()` adopts content | Stock `Window.create` + `ui.root` still inside the deferred embed |
| InteractionScript | Declared in manifest | Dropped from hub manifests (only embedded in boot) |
| Prefs | Same package id for years | Pointed at new hub ids; old member folders deleted → “Unavailable” then crash after re-select |

Crash after selecting hubs: SIGABRT while provider VMs load. Dump noise included
`Core/modules.lua` duplicate/cyclic module asserts — consistent with deferred boot /
double-define / missing root, not with a single missing PNG.

Whack-a-mole (`shell.mount` only, prefs remap, Skills wrap fix) did not make hubs
safe. **Do not ship or re-enable that bundler as-is.**

### Client restored for testing (now)

- Removed hub folders from `UI/Addons`
- Restored individual packages from `release/ndgui-spiritech-0.3.7.zip` as `notum.ndgui-*`
- Restored prefs from `Client.xml.ndgui-backup-20261125-225543` (member package ids)
- Re-ran `square_buttons.py --addons-only` for marketplace chrome

### Post-restore chrome fixes (2026-11-25 evening)

Zip restore left NCU/pet on Core shared pale Multilistview slots, and Skills/Nano
looked stock because wrap reparent keyed on `View.name` (userdata does **not**
reliably expose the XML name — use child identity / `ui.find` instead).

| Surface | Fix |
| --- | --- |
| Character / target NCU | Package-local `ncu_slot.xml` (open_46x30 well) + `slot_cells` (no `shared`) |
| Pet / team NCU strips | `notum.ndgui-lib/ncu_strip` (slot_cells, not Core `shared=true`) + package `pet_ncu_slot.xml` / `team_ncu_slot.xml` |
| Skills category labels | Reparent wrap by button identity (`wrap_holding`), not `kid.name` |
| Nano school toolbar | Same identity `chrome_or`; size wraps to `CONTROL_HEIGHT` (22), not stock 16 |
| Team Compact/NCU/Leave/Recruit | Size chrome wraps + inner buttons together |

Options window staying stock is expected (no SkinLayouts). Full client restart
needed after these Addons patches (Lua modules are cached for the session).

### Skills / IP column (same night)

Stock category and action buttons are centered with `layout_borders`. Skinning
dropped those insets, so both left columns sat flush left. Buttons Lua hides
(`restore_priorities`, `save_priorities`, `cancel_priorities`, and Reset/Save/Close
while editing priorities) only hid the Button, leaving the wrap chrome as an
empty ghost. Category reparent also has to move that wrap: match the 2-child
view that contains `ndgui_chrome` and the named button (`ui.find`), not
`View.name` or userdata equality.

Live client `notum.ndgui-skills` XML has the stock borders back on the wraps,
and hidden controls start `visible="false"` on the wrap. `square_buttons.py`
unwrap copies `layout_borders` back onto the Button so a later reskin keeps them.

Do not search for a wrap with `ui.find` on views that may not contain that name.
A missing view aborts the Skills script and the window opens with only the
top-left panel. Category reparent takes the next direct child (`take_wrap`).

Ghost buttons are one pattern: `ui.visible` on a Button leaves `ndgui_btnwrap`
on screen (Team Leave, Pets Attack/Follow/Wait, Market confirm/keep, Mission
Terminal Map, Skills priority buttons). `button.lua` records Button to wrap
when the layout loads and hides the wrap with the Button. `boot.lua` installs
that hook from `grid.lua` before `ui.load`. Layouts that start hidden put
`visible="false"` on the wrap, not the Button. The hook keys the map by the
Button userdata from `ui.child` during load; `ui.find` later can be a different
proxy, so a table lookup misses and Team Leave still ghosted. `ui.visible` now
also matches with `==` and remembers that proxy. Team still hides the Leave wrap
by structure (button-row wraps in order: Compact, NCU, Leave, Recruit). Pets
Attack/Follow/Wait do the same when Show buttons is off. Restart the client
after copying `notum.ndgui-team`, `notum.ndgui-pets`, and `notum.ndgui-lib`.

The dark box under the window text and the Wear tab buttons are recorded at the top of
this file (2026-11-26). An earlier Wear tab swap aborted the package because it also
rewrote `main.lua`. The current buttons keep the original script.

You should be able to launch and test the pre-hub UI again. Restart the client after
copying `notum.ndgui-lib` and `notum.ndgui-wear`.

### Marketplace 32-cap (open)

Full role coverage is ~41 packages. Options that are not frankenstein embeds:

1. **Proper hubs** — Mission Hub pattern only: load-time shell, real modules, `shell.window()`, InteractionScript in the manifest, no `load(src)` of whole packages.
2. **Omit roles** — like modern-ui, stay ≤32 by not shipping every Options row.
3. **Ask Spiritech** — whether the 32 limit can be raised for large suites.

`build_marketplace.py` no longer calls `bundle_hubs`; it warns if count > 32.

### Repo state

- Restored `addons/ndgui-playfield-map`, `planet-map`, `team` (hub trees removed)
- `bundle_hubs.py` / hub-related install OBSOLETE lists left in tree as reference only — do not run bundler on a live client

## Marketplace visual parity (branch `marketplace-visual-parity`)

Implemented so the marketplace suite zip is self-sufficient for in-game HUD (library://
buttons / slots / compass / maps). Still valid on the unbundled package layout.

### Verify

```bash
cd /tmp/.../ndgui && lua5.4 tests/test_providers.lua
NDGUI_ADDONS=/path/to/client/UI/Addons python3 addons/ndgui/tools/square_buttons.py --addons-only
python3 build_marketplace.py --addons-dir /path/to/client/UI/Addons
```
