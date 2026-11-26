# Installing ndGUI for Spiritech

You can install from the **Spiritech Marketplace** (in-game HUD) or with the **install script** (same HUD, plus a fuller atlas merge for Login/Options and native chrome). Use either, or Marketplace first and the script's `-SkinLayouts` later for the extra skin.

## Spiritech Marketplace

1. Quit the game.
2. Install **ndGUI** from the Launcher **Addons** page (packages land as `notum.ndgui*` under `client/UI/Addons`).
3. Options → Interface & HUD → **UI packages** → select the Notum Dovvetech providers; re-enter the character.

That covers the in-game HUD, DarkTech buttons, slot wells, compass, and maps. Login / Options / character screens stay stock until you also run the install script (or `-SkinLayouts` below). Details: [docs/marketplace-listing.md](docs/marketplace-listing.md).

## Windows install script (full atlas)

Merges DarkTech art into the game's graphics atlas and squares Login / Options / character screens. You don't need Python or an exe: `install.ps1` is plain PowerShell, and `install.bat` just starts it. Open either in Notepad if you want to see what they do.

1. **Quit the game.** The game reads its skin at start and rewrites its settings on exit. If it's running, the installer waits until you close it.
2. Download **`ndgui-spiritech-<version>.zip`** from the [Releases page](../../releases).
3. **Unpack it:** right-click → *Extract All*. Running from inside the zip won't work.
4. Double-click **`install.bat`**. A window opens:

   ```
   ndGUI for Spiritech 0.3.7

   Game folder: C:\Games\PRK-AO-Native\client

     1) Install / update to 0.3.7 (this folder)
     2) Update to the newest version (downloads from GitHub)
     3) Install 0.3.7, but keep the game's own screens stock (Options, login...)
     4) Uninstall (back to the stock UI)
     5) Snap-to-grid size (now: 10 px)
     6) Quit
   ```

   Press **Enter** to install.
5. Start the game.

**Already installed from Marketplace?** For atlas + Login/Options only, without touching packages or providers:

```powershell
.\install.ps1 -SkinLayouts
.\install.ps1 -SkinLayouts -KeepProviders   # keep providers you already chose
```

### It can't find my game

It looks around itself, in the launcher's `LauncherSettings.json`, and in the usual places (`C:\Games\PRK-AO-Native`, the same on other drives, your user folder). If that fails, it opens a folder picker. Pick **the folder that holds `PRK.Client.exe`**, usually `...\PRK-AO-Native\client`. The launcher folder, which contains `client`, works too.

Tip: unpack the zip inside your `PRK-AO-Native` folder and it always finds the game.

From a PowerShell window you can also point it at the game directly:

```powershell
.\install.ps1 -Install -Client "D:\Games\PRK-AO-Native\client"
.\install.ps1 -Install -StockScreens      # keep Options/login screens stock
.\install.ps1 -Install -KeepProviders     # leave current HUD/window UI package choices alone
.\install.ps1 -SkinLayouts                # skin + screens only (marketplace packages already present)
.\install.ps1 -SkinLayouts -KeepProviders
.\install.ps1 -Uninstall
.\install.ps1 -Update                    # download the newest release from GitHub and install it
.\install.ps1 -Update -KeepProviders     # update packages without rewriting providers
```

`-KeepProviders` skips rewriting Options → Interface & HUD → UI packages in `Client.xml`, so a hybrid mix of providers stays as you set it. Packages, skin, and screens still update.

### "Windows protected your PC" / "Do you want to run this file?"

Windows asks about scripts that came from the internet. Click **Run** (or **More info → Run anyway**). Nothing is downloaded or installed outside the game folder.

## What it changes

| Step | What | Where | Undo |
| --- | --- | --- | --- |
| 1 | Copies the ndGUI packages (HUD, windows, maps, library) | `client\UI\Addons\ndgui*` (player zip) or `notum.ndgui*` (marketplace) | removed |
| 2 | Square buttons on the game's own screens (Options, login, character select, loading) and pin state on stock windows | 8 files in `client\UI\Layouts\`, `client\UI\Packages\Core\window.xml` | `*.stock` copies put back |
| 3 | DarkTech skin: merges ~475 images (button art, slots, tabs, scrollbars, sliders, map markers, steel retint) into the game's graphics file | `client\cd_image\gui\Default\Graphics.uvg*`, `GUIColors.xml` | `*.stock` copies put back |
| 4 | Switches every HUD/window role to the ndGUI provider | `%LOCALAPPDATA%\ProjectRubiKa\prefs\Client.xml` | roles reset; `Client.xml.ndgui-backup-*` kept |

The first run keeps an untouched `*.stock` copy of each game file before changing it. Every later run starts from those copies, so running it twice doesn't stack changes.

If step 4 says there are no game settings yet (it's your first-ever start), start the game once, quit, and run it again. You can also pick providers by hand: **Options → Interface & HUD → UI packages** → the `Notum Dovvetech …` entry for each role. Provider changes apply from your next character session (log out to character select and back in).

## Updating

- **New ndGUI version:** run `install.bat` → **2**. It asks GitHub for the newest release, and if that's newer than what's installed, downloads the zip and installs it. With no window, from PowerShell: `.\install.ps1 -Update`. It tells you where it unpacked the new version, so you can use that copy's `install.bat` later. (Or download the zip by hand and run its `install.bat` → **1**.)
- **After a game patch:** run `install.bat` again. A patch can put stock files back.
  - If the patch changed the game's UI a lot, the installer warns that the build was made for another game version. Pieces that no longer fit fall back to the stock UI by themselves (the game never shows a broken HUD), and a new ndGUI release will catch up.
  - If a patch replaced a game file the installer had backed up, delete that `*.stock` file before reinstalling. Otherwise uninstall would put the *old* file back.

## Uninstalling

Run `install.bat` → **4**. It resets the providers to the built-ins, puts back the stock skin, screens and window file from the `*.stock` copies, and removes every ndGUI package (`ndgui*` and marketplace `notum.ndgui*`). Window positions saved by ndGUI stay in the game settings, where they're harmless. If you installed from the Launcher Addons page, also remove the listing there so it does not reappear as an unmanaged conflict later.

## Linux / Mac (Python)

The player zip includes `install.py` next to `install.bat`. Unpack the whole zip and run it from that folder. Python 3.8+ is enough; it installs the prebuilt packages, screens, and skin, same as `install.bat`.

```bash
python install.py --install
python install.py --install --client "/path/to/PRK-AO-Native/client"
python install.py --uninstall
```

From a git checkout you need **Python 3.8+** and **Pillow**. That builds everything on your machine from the repo:

```bash
python -m pip install pillow
git clone <this repo> && cd ndgui-spiritech
python install.py                         # menu
python install.py --install               # no questions
python install.py --install --client "/path/to/PRK-AO-Native/client"
python install.py --install --stock-screens
python install.py --install --keep-providers   # leave current HUD/window UI package choices alone
python install.py --skin-layouts          # residual skin + screens (marketplace packages already present)
python install.py --skin-layouts --keep-providers
python install.py --uninstall
python install.py --grid 20               # snap-to-grid size in px (0 = off); kept across updates
python install.py --update                # newest GitHub release: git pull in a checkout, else downloads the source
python install.py --update --keep-providers
python install.py --check                 # only check game folder + requirements
```


Settings are looked for under `~/.local/share/ProjectRubiKa/prefs/Client.xml`. Set `NDGUI_PREFS=/full/path/Client.xml` if yours is elsewhere. Linux and Mac are untested so far. Reports welcome: ask **thedenis** on the PRK Discord.

## Troubleshooting

- **The window flashes and closes:** run `install.bat` from an unpacked folder, not from inside the zip.
- **Still looks stock in game:** log out to character select and back in. Check **Options → Interface & HUD → UI packages** lists the `Notum Dovvetech` providers.
- **One HUD piece is stock again, or missing:** a package hit an error. Type **`/uidebug`** in chat: it lists every UI package and marks failed ones; click the failed row to see the error and where it happened. Send a screenshot of that to **thedenis** on the PRK Discord (or open an issue). The newest file in `PRK-AO-Native\logs\` has the same error under `ndgui`.
- **After a game update something breaks:** game updates can change the addon API. Run `install.bat` → **2** for the newest ndGUI, and check `/uidebug`.
- **Everything is broken:** `install.bat` → **4** (Uninstall). If even that fails, delete the `client\UI\Addons\ndgui*` folders, then rename each `*.stock` file back over its neighbour. You can also let the launcher repair the game.
