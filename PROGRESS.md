# Progress

## Marketplace visual parity (branch `marketplace-visual-parity`)

Implemented end-to-end so the marketplace suite zip is self-sufficient for in-game HUD.

### Done

- **Art export:** `addons/ndgui/tools/export_skin_assets.py` writes buttons / pin / close / fold / expand / info / compass / map / `slots/open_{36,48,54}.png` into `ndgui-lib/assets/`.
- **Buttons:** `ndgui-lib` `button.lua` + `button_chrome.xml` + `boot.lua`; `square_buttons.py --addons-only` unwraps nested `ndgui_btnwrap` (chrome = BitmapViews only), re-wraps labelled Buttons with `library://` chrome + `flat` + `text_alignment="center"`. Set `NDGUI_ADDONS=/path/to/UI/Addons` for an installed client tree.
- **Slots:** same tool wraps `ItemSlotView` in `ndgui_slotwrap` with `library://notum.ndgui-lib/slots/open_*.png` and `slot_gfx=""`.
- **Pin / window chrome:** package `pin.png` / `pin_on.png` / `close.png` / `fold.png` / `expand.png` / `info.png`; flat titlebar Buttons with BitmapView children.
- **Compass:** mark strip at **3 px/degree** (TextView letters + tick Views via `ui.place`, same scale as former atlas band: 320 px ≈ 107° visible). Waypoint/caret are `library://` PNGs. Stock framed `PannedSurfaceView` kept as emergency fallback. (Earlier BitmapView band path was layout-scaled into 320 px and looked compressed.)
- **Maps:** playfield + planet use stock `GFX_GUI_MAP_*` / planet markers + DarkTech `fan`/`line` primitives. No `GFX_GUI_NDGUI_MAP_*` runtime dependency.
- **Owned chrome:** CC tabs + minibar flat fills + library icons; menubar uses library tab art; AGG/DEF Slider still stock atlas (Slider API is atlas-only).
- **Guards/docs:** `build_marketplace.py` fails on quoted/`gfxid_*` `GFX_NDGUI_*` / `GFX_GUI_NDGUI_*` refs; `docs/marketplace-listing.md` states `-SkinLayouts` is optional Login/Options only; README/INSTALL updated; `build_release.py` invokes marketplace zip after player zip.

### Verify

```bash
# Provider tests (need client Core; packages as ndgui-* siblings of ndgui/)
# Physical tree: copy client notum.ndgui-* -> ndgui-* and overlay repo packages; Core at ../../Packages/Core
cd /tmp/.../ndgui && lua5.4 tests/test_providers.lua   # ALL PASS (incl. mark-based compass)

NDGUI_ADDONS=/path/to/client/UI/Addons python3 addons/ndgui/tools/square_buttons.py --addons-only
python3 build_marketplace.py --addons-dir /path/to/client/UI/Addons
```

### Honest gaps (documented)

- Map marker bitmaps cannot be package-identical (sprite API = atlas IDs only).
- AGG/DEF Slider track/thumb stay stock atlas.
- Native list scrollbars / system dropdown guts remain teal without skin merge.
- Login/Options squaring still needs `-SkinLayouts` / full player install.

## Atlas vs package art (platform facts)

- `game.map_surface.sprite` / `ui.compass.sprite` / Button `gfxid_*` = atlas names only.
- `BitmapView` / `ui.image` accept `package://` and `library://`.
- No Lua API to register graphics into the atlas.

## Prior context

- Local `main` at **v0.3.7**; branch work here is marketplace-only visual+functional parity on top of that.
- `addons/ndgui-lib/lua/table.lua` is gitignored (forked Core table); present on installed client lib and required by forked windows / missions tests.

## Before/after comparison (2026-11-25)

### Before state (frozen)
- Snapshot: `.snapshots/before-state-20261125/` (Addons, Layouts, Core window, skin live+stock, Client.xml prefs, screenshot)
- Restore anytime (game closed): `.snapshots/restore_before_state.sh`
- Reference shot: `Pictures/Screenshots/Screenshot_20261125_121706.png` (also in snapshot `meta/`)
- Content: atlas-era 0.3.7 DarkTech (GFX_NDGUI_BTN*, compass atlas, skin merged)

### After fix pass (2026-11-25, marketplace-only client)
- Synced branch packages onto `/home/blasky/Games/PRK-Spiritech/client/UI/Addons/notum.ndgui*`
- Re-ran `square_buttons.py --addons-only` (unwrap nested wraps, center labels, package slot wells)
- Compass rewritten to mark-based 3 px/deg strip; `letter.xml` / `tick.xml` added
- Slot PNGs exported; provider tests **ALL PASS**

### Slot / wear / NCU wells (2026-11-25)
- Wells are stacked cells: `BitmapView` (`library://…/slots/open_*.png` from `skin.py` `square_slot`) behind `ItemSlotView` with `slot_gfx=""`. Do not bind `icon_grid` to the wrap root or put the PNG as a child of the slot.
- Collection grids: template root = `ndgui_slotcell`, inner slot = `ndgui_slot`; Lua uses `notum.ndgui-lib/slot_cells` (same API as `core.icon_grid`). Wear uses `wear_cell_*` + `core.icon_grid` on the named `wear_slot_*` views; dark `wear_frame` fills kept.
- `square_buttons.py` emits/unwraps slotcells; `fork_windows.py` / `fork_hud.py` swap the require for inventory/actions/trade/nano/npc-chat/NCU. Hotbar already had package chrome.
- Provider tests ALL PASS; client synced; `release/ndgui-0.3.7.zip` rebuilt.
- Style: slot/compass/button/tool comments brought in line with Core (sparse) and ndgui-lib prose headers (`briefs.lua` / `grid.lua` voice); dropped "modern-ui"/"sibling-behind" jargon from code comments.
