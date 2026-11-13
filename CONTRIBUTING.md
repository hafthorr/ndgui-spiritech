# Working on ndGUI for Spiritech

## Layout of the repo

```
addons/                     the 9 hand-made packages, copied into client/UI/Addons as-is
  ndgui/                    settings host + all the tools and tests
    tools/                  generators (Python 3.8+, Pillow)
    tests/                  offline Lua 5.4 tests against a mock client host
  ndgui-lib/                shared library: window frame, art kit (assets/), Lua modules (lua/)
  ndgui-control-center/     prk.control-center   bottom strip
  ndgui-status-bars/        prk.status-bars      HP/NP/XP
  ndgui-compass/            prk.compass
  ndgui-target-panels/      prk.target-panels
  ndgui-hotbar/             prk.hotbar
  ndgui-playfield-map/      prk.playfield-map    Local Map
  ndgui-planet-map/         prk.planet-map       Planet Map
install.ps1, install.bat    the player installer (PowerShell; ships in the release zip)
install.py                  install straight from this checkout (developers, Linux/Mac)
build_release.py            builds release/ndgui-spiritech-<version>.zip (committed; CI publishes it)
docs/background/            original research and design notes
```

The other 30 packages (`ndgui-inventory`, `ndgui-ncu`, …) are **generated** from the game's own `UI/Packages`. They aren't in git: generate them with the tools below. `ndgui-lib/lua/table.lua` is generated too.

## Tools (`addons/ndgui/tools`, run from the installed `client/UI/Addons/ndgui`)

| Tool | Does |
| --- | --- |
| `fork_windows.py` | 20 `core.window` windows → `ndgui-<window>` with the ndGUI frame |
| `fork_hud.py` | NCU, target NCU, faction, chat, chat config, raid bars, timer bars, team invite, sneak, logout |
| `lib_table.py` | `ndgui-lib/lua/table.lua` from Core's table: movable and hideable list columns |
| `square_buttons.py` | square 3-slice buttons in every ndgui package and the game's `UI/Layouts`; `--restore`, `--addons-only` |
| `skin.py` | DarkTech skin into `cd_image/gui/Default` (from `*.stock`); `--restore`, `--preview DIR`, `--overlay DIR` |
| `select_providers.py` | select all ndGUI providers in prefs; `--reset` |
| `make_art.py`, `make_icons.py` | regenerate the original art kit in `ndgui-lib/assets` |

All generators **stop instead of guessing** when the game file they patch changed shape upstream. That's the signal to update the patch after a game update.

## Dev loop

```bash
python install.py --install          # checkout -> your client, builds everything (game closed)
# ...play, then edit files directly in client/UI/Addons/<package>...
python install.py --pull             # copy the hand-made packages back into addons/
git diff
```

Restart the game after every change. Package changes apply from the next character session.
Logs: `PRK-AO-Native/logs/client-*.log`.

## Tests (Lua 5.4)

They load the real Core modules from the client, so run them from the installed copy:

```bash
cd <client>/UI/Addons/ndgui
lua tests/test_providers.lua    # every provider loads and runs its callbacks in the mock host
lua tests/test_ndgui.lua
lua tests/test_view.lua
```

All three must print `ALL PASS`. CI only syntax-checks (it has no game client).

## Making a release

1. Bump `VERSION` in `install.py` and add a `## <version>` section to `CHANGELOG.md` (it becomes the release notes).
2. `python build_release.py` (game closed or not; it works on a staged copy of your client's stock files). It replaces the zip in `release/`.
3. Smoke-test: unpack `release/ndgui-spiritech-<version>.zip`, run `install.bat`, play.
4. Commit (including the zip), `git tag v<version>`, `git push --follow-tags`.

GitLab CI then creates the release by itself: notes from the changelog, the zip as the download. It fails loudly if the zip, `VERSION` or changelog section doesn't match the tag. CI can't build the zip itself because that needs a game client.

## Rules of thumb

- Colors come from `ndgui-lib/lua/dovvetech.lua` / `ndgui/theme.lua`; don't hard-code new ones in a window.
- Map sprite names must start with `GFX_GUI_` (the client refuses others on map surfaces); button art can be `GFX_NDGUI_*`.
- Inactive tabs are drawn by the client at ~50 % alpha with dark ink, so tab art must stay light.
- No baked text in art: use labelled buttons so text stays crisp at high UI scale.
- Every piece must stay movable.
