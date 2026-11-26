# Spiritech Addons marketplace listing

ndGUI is offered two ways: the **Spiritech Marketplace** suite (packages only) and the
GitHub **player zip** / `install.ps1` (packages plus a fuller graphics-atlas merge).
Marketplace alone is enough for the in-game HUD; the install script adds Login/Options
squaring and optional atlas retint that the Launcher cannot apply.

## What the marketplace can and cannot do

The Spiritech Launcher Addons page installs a **suite zip** of packages into
`client/UI/Addons/` and records a receipt in `.installed.json`. It does **not**
run a custom installer, merge a graphics atlas, patch Login/Options layouts, or
rewrite `Client.xml` UI package providers.

| Piece | Marketplace zip alone | Install script (`install.ps1` / `-SkinLayouts`) |
| --- | --- | --- |
| HUD / window packages + Buff Watch / Meter / Grid | yes | yes (or already present) |
| DarkTech window chrome, 3-slice buttons, pin, compass, slot wells in `notum.ndgui-lib` | yes | — |
| Maps usable (stock facing sprites + DarkTech fan/line primitives) | yes | — |
| Pixel-identical custom map-marker bitmaps | **no** (atlas-only API) | yes if you still merge skin.py map sprites |
| Square buttons on Login / Options / character screens | **no** | yes (Layouts patch) |
| Auto-select every ndGUI provider | **no** | yes (or pick in Options) |
| Native-interior teal (list scrollbars, system dropdown guts) | residual | optional atlas retint |

**In-game product:** the marketplace zip is self-sufficient for HUD functionality and
DarkTech buttons / pin / compass / maps / slot wells. The install script is the path for
**more complete atlas replacement** (Login/Options squaring and optional native-chrome
retint). Use `-SkinLayouts` after a Marketplace install if you only want that residual skin.

## Artifacts

| File | Purpose |
| --- | --- |
| `release/ndgui-spiritech-<version>.zip` | Full player zip: packages + skin overlay + Layouts + `install.ps1` |
| `release/ndgui-<version>.zip` | **Marketplace suite** for portal upload (packages only) |

Build:

```bash
python build_release.py                  # player zip, then marketplace zip
python build_marketplace.py              # marketplace zip from existing player zip
python build_marketplace.py --addons-dir /path/to/client/UI/Addons
```

`build_marketplace.py` **fails** if any staged package still references
`GFX_NDGUI_*` / `GFX_GUI_NDGUI_*` atlas ids (quoted or as `gfxid_*`).

Suite rules (match modern-ui): top-level folders only, folder name == package id
(`notum.ndgui-hotbar/`), every `package.xml` stamped with the same `version` and
`apiVersion` (default `0.1.0`), each folder contains `LICENSE`, no `tools/`.

## Portal listing metadata (upload outside this repo)

Catalog API (browse): `https://portal.project-rk.com/api/addons`

Suggested listing fields:

| Field | Suggested value |
| --- | --- |
| Name | `ndGUI` (or `Notum Dovvetech`) |
| Author | ndGUI / thedenis (confirm with maintainer) |
| Description | Full DarkTech / Notum Dovvetech UI for Spiritech: HUD, windows, Buff Watch, Damage Meter, maps, compass. After install, pick Notum Dovvetech providers under Options → Interface & HUD → UI packages. For square Login/Options and a fuller atlas merge, also run the GitHub player zip (`install.ps1` or `-SkinLayouts`). |
| Version | match `install.py` `VERSION` |
| Changelog | copy the matching `## <version>` section from `CHANGELOG.md` |
| Screenshots | in-game HUD, inventory, Buff Watch (upload via portal) |
| Artifact | `release/ndgui-<version>.zip` |

Publish steps (process owned by Spiritech / listing author):

1. `python build_marketplace.py` (or full `build_release.py`).
2. Upload `release/ndgui-<version>.zip` through the Spiritech addon publish path.
3. Fill description, changelog, screenshots.
4. Confirm the listing appears in the Launcher Addons browse page and installs into `UI/Addons` with a `.installed.json` receipt.

Published versions cannot be replaced; bump `VERSION` for every upload.

## Player path (marketplace + optional residual)

1. Quit the game.
2. If an older **unmanaged** `ndgui*` install exists, uninstall it first (duplicate package ids are refused). Marketplace folders are named `notum.ndgui*`.
3. Launcher → **Addons** → install **ndGUI**.
4. Options → Interface & HUD → **UI packages** → select the Notum Dovvetech providers.
5. Optional Login/Options squaring: unpack the GitHub **player** zip and run:
   ```powershell
   .\install.ps1 -SkinLayouts
   .\install.ps1 -SkinLayouts -KeepProviders   # keep the choices from step 4
   ```
   Or from source: `python install.py --skin-layouts` / `--skin-layouts --keep-providers`.
6. Start the game; re-enter the character if providers just changed.

### Clean-client smoke (marketplace only)

On a client with **no** prior ndGUI skin/Layouts:

1. Install the marketplace suite zip (Launcher or copy `notum.ndgui*` into `UI/Addons`).
2. Select Notum Dovvetech providers; re-enter character.
3. Confirm: labelled toolbars (meter, maps, terminal), window pin/close, compass strip, local + planet maps (markers/route), control-center tabs/minibar.
4. Expect residual teal only on native list scrollbars / system dropdown guts; Login/Options remain stock unless `-SkinLayouts` is run.

The full `install.ps1` / `install.bat` path (packages + atlas skin + screens + providers) remains a supported one-shot install and does not require the marketplace.
