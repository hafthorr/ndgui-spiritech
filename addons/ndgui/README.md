# ndgui (notum.ndgui)

The settings host of **ndGUI for Spiritech**, and home of the build tools and tests.
Install, usage and development docs live at the top of the repo: `README.md`, `INSTALL.md`, `CONTRIBUTING.md`.

- `theme.lua`, `layout.lua`, `config.lua`, `hud.lua`, `menubar.lua`, `windows.lua`, `ndgui/`: the theme tokens (Classic Dovvetech, DarkTech, DarkTech Mini, Adaptive) and the logical-pixel layout model (1080p to 5K, the client's pixel scale is never applied twice).
- `tools/`: generators. See CONTRIBUTING.md.
- `tests/`: offline Lua 5.4 tests against a mock client host. Run them from the installed copy (`client/UI/Addons/ndgui`).

## Package family

The client doesn't let one package mix a standalone overlay with role providers, so ndGUI ships as sibling folders in `UI/Addons`:

| Folder | Kind | Role |
| --- | --- | --- |
| `ndgui` | standalone overlay | settings host |
| `ndgui-lib` | shared library | frame, art kit, Dovvetech tokens, `table` module |
| `ndgui-control-center` | provider | `prk.control-center` |
| `ndgui-status-bars` | provider | `prk.status-bars` |
| `ndgui-compass` | provider | `prk.compass` |
| `ndgui-target-panels` | provider | `prk.target-panels` |
| `ndgui-hotbar` | provider | `prk.hotbar` |
| `ndgui-maps` | provider hub | `prk.playfield-map`, `prk.planet-map` |
| `ndgui-team-hub` | provider hub | `prk.team`, `prk.team-invite` |
| `ndgui-<window>` / `*-hub` | generated providers | remaining window and HUD roles (≤32 packages total) |

The client only runs providers once they're selected (**Options → Interface & HUD → UI packages**; the installer does it for you). Changes apply from the next character session. A provider that fails is replaced by the built-in for that session, so the HUD never disappears.
