# Progress

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

You should be able to launch and test the pre-hub UI again.

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
