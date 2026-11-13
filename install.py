#!/usr/bin/env python3
"""ndGUI for Spiritech: installer / updater / uninstaller.

Players don't need this: they use the release zip and install.bat / install.ps1
(plain PowerShell, no Python). This script installs straight from a git checkout,
building everything on the spot. For developers, and for Linux/Mac.

Needs Python 3.8+ and Pillow:
    python install.py                      interactive menu
    python install.py --install            install or update (auto-detects the client)
    python install.py --install --client "D:/Games/PRK-AO-Native/client"
    python install.py --uninstall          put the stock UI back and remove ndGUI
    python install.py --check              only check the client and requirements
    python install.py --pull               copy edited packages from the client back into addons/

Install option:
    --stock-screens   leave the client's own screens stock (Options, login, character select...);
                      ndGUI's windows still get square buttons

Quit the game first: the client reads the skin at start and rewrites prefs on exit.
Every client file the installer changes keeps a backup (*.stock / Client.xml.ndgui-backup-*),
and --uninstall restores them. See INSTALL.md.
"""
import argparse, glob, json, os, re, runpy, shutil, string, subprocess, sys, traceback

VERSION = "0.2.2"
REPO = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(REPO, "addons")
# Generated on the player's machine from their own client (never copied back by --pull).
GENERATED_FILES = [os.path.join("ndgui-lib", "lua", "table.lua")]


def say(text=""):
    print(text, flush=True)


# ---- finding the game ------------------------------------------------------------
def is_client(path):
    return bool(path) and os.path.isdir(os.path.join(path, "UI", "Packages", "Core"))


def normalise(path):
    """Accept the client folder, the launcher folder (holds client/) or PRK.Client.exe itself."""
    if not path:
        return None
    path = os.path.abspath(os.path.expanduser(path.strip().strip('"')))
    if os.path.isfile(path):
        path = os.path.dirname(path)
    for candidate in (path, os.path.join(path, "client")):
        if is_client(candidate):
            return candidate
    settings = os.path.join(path, "LauncherSettings.json")
    if os.path.exists(settings):
        try:
            client = json.load(open(settings, encoding="utf-8")).get("ClientPath")
            if is_client(client):
                return client
        except (OSError, ValueError):
            pass
    return None


def candidates():
    here = REPO
    seen = [os.environ.get("NDGUI_CLIENT")]
    # wherever the installer sits: inside the game folder, or beside it
    folder = here
    for _ in range(4):
        seen += [folder, os.path.join(folder, "PRK-AO-Native")]
        folder = os.path.dirname(folder)
    drives = [f"{d}:\\" for d in string.ascii_uppercase if os.path.exists(f"{d}:\\")] if os.name == "nt" else []
    for drive in drives:
        for sub in (r"Games\PRK-AO-Native", "PRK-AO-Native", r"Program Files\PRK-AO-Native",
                    r"Program Files (x86)\PRK-AO-Native", r"Games\Project Rubi-Ka", "Project Rubi-Ka"):
            seen.append(os.path.join(drive, sub))
    for base in (os.environ.get("LOCALAPPDATA"), os.environ.get("USERPROFILE"), os.path.expanduser("~")):
        if base:
            for sub in ("PRK-AO-Native", os.path.join("Games", "PRK-AO-Native"), os.path.join("Desktop", "PRK-AO-Native"),
                        os.path.join("Downloads", "PRK-AO-Native"), os.path.join("Programs", "PRK-AO-Native")):
                seen.append(os.path.join(base, sub))
    return seen


def find_client(given=None):
    if given:
        client = normalise(given)
        if not client:
            raise SystemExit(f"'{given}' is not the Spiritech client folder (the one with PRK.Client.exe and UI\\ inside).")
        return client
    for path in candidates():
        client = normalise(path)
        if client:
            return client
    return None


def ask_for_client():
    say("I could not find the game by myself.")
    try:
        import tkinter
        from tkinter import filedialog
        root = tkinter.Tk()
        root.withdraw()
        say("Pick the game folder in the window that just opened (the one with PRK.Client.exe)...")
        path = filedialog.askdirectory(title="Pick the Spiritech client folder (has PRK.Client.exe)")
        root.destroy()
        client = normalise(path)
        if client:
            return client
    except Exception:  # no GUI available: fall back to typing
        pass
    while True:
        path = input("Paste the game folder (the one with PRK.Client.exe), or press Enter to cancel: ")
        if not path.strip():
            raise SystemExit("Cancelled.")
        client = normalise(path)
        if client:
            return client
        say("  That folder has no PRK.Client.exe / UI folder. Try again.")


# ---- checks ------------------------------------------------------------------------
def client_running():
    if os.environ.get("NDGUI_ASSUME_CLOSED") == "1":  # developer testing against a copy of the client
        return False
    try:
        if os.name == "nt":
            out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq PRK.Client.exe"], capture_output=True, text=True,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).stdout
            return "PRK.Client.exe" in out
        return subprocess.run(["pgrep", "-f", "PRK.Client"], capture_output=True).returncode == 0
    except OSError:
        return False


def have_pillow():
    try:
        import PIL.Image, PIL.ImageDraw  # noqa: F401,E401
        return True
    except ImportError:
        return False


def check(client):
    say(f"Game folder: {client}")
    ok = True
    if sys.version_info < (3, 8):
        say("  ! Python 3.8 or newer is needed.")
        ok = False
    if not have_pillow():
        say("  ! Pillow is missing (needed for the skin). Install it with:")
        say(f"      \"{sys.executable}\" -m pip install pillow")
        ok = False
    while client_running():
        say("  ! The game (PRK.Client.exe) is running. Quit it first.")
        if not interactive:
            return False
        input("    Quit the game, then press Enter to continue... ")
    return ok


# ---- running the tools ----------------------------------------------------------------
def tool(client, name, *args, optional=False):
    """Run one of addons/ndgui/tools/*.py from the installed copy in the client (the tools
    locate the client relative to their own file)."""
    tools = os.path.join(client, "UI", "Addons", "ndgui", "tools")
    script = os.path.join(tools, name)
    say(f"  > {name} {' '.join(args)}".rstrip())
    saved_argv, saved_cwd = sys.argv, os.getcwd()
    sys.argv = [script, *args]
    os.chdir(os.path.dirname(tools))
    code = 0
    try:
        runpy.run_path(script, run_name="__main__")
    except SystemExit as stop:
        if stop.code not in (None, 0):
            code = stop.code
    except Exception:
        traceback.print_exc()
        code = 1
    finally:
        sys.argv = saved_argv
        os.chdir(saved_cwd)
    if code:
        if isinstance(code, str):
            say(f"    {code}")
        if optional:
            say(f"    ({name} did not finish; skipped)")
            return False
        raise SystemExit(f"{name} failed. Nothing after this step was changed.")
    return True


def ours(folder):
    manifest = os.path.join(folder, "package.xml")
    if not os.path.exists(manifest):
        return False
    return bool(re.search(r'<Package id="notum\.ndgui', open(manifest, encoding="utf-8").read()))


def copy_packages(client):
    addons = os.path.join(client, "UI", "Addons")
    os.makedirs(addons, exist_ok=True)
    names = sorted(n for n in os.listdir(SOURCE) if os.path.isdir(os.path.join(SOURCE, n)))
    for name in names:
        dest = os.path.join(addons, name)
        if os.path.isdir(dest):
            shutil.rmtree(dest)
        shutil.copytree(os.path.join(SOURCE, name), dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    say(f"  copied {len(names)} packages into {addons}")


# ---- actions ---------------------------------------------------------------------------
def install(client, stock_screens=False):
    if not check(client):
        raise SystemExit("\nFix the items above and run the installer again.")
    say("\n[1/5] Copying ndGUI packages")
    copy_packages(client)
    say("\n[2/5] Building the ndGUI windows from your client's own UI")
    tool(client, "fork_windows.py")
    tool(client, "fork_hud.py")
    tool(client, "lib_table.py")
    say("\n[3/5] Square DarkTech buttons")
    if stock_screens:
        tool(client, "square_buttons.py", "--restore")
        tool(client, "square_buttons.py", "--addons-only")
    else:
        tool(client, "square_buttons.py")
    say("\n[4/5] DarkTech skin (button art, slots, tabs, sliders, map markers, steel retint)")
    tool(client, "skin.py")
    say("\n[5/5] Switching the HUD and windows to ndGUI")
    if not tool(client, "select_providers.py", optional=True):
        say("  Pick them by hand in the game: Options > Interface & HUD > UI packages.")
    say("\nDone! Start the game. If something still looks stock, log out to character select and back in once.")
    say("To undo everything: python install.py --uninstall")
    say("Bugs, issues, ideas? Ask 'thedenis' on the Project Rubi-Ka Discord.")


def uninstall(client):
    while client_running():
        if not interactive:
            raise SystemExit("The game (PRK.Client.exe) is running. Quit it first.")
        input("The game is running. Quit it, then press Enter... ")
    addons = os.path.join(client, "UI", "Addons")
    if not os.path.isdir(os.path.join(addons, "ndgui", "tools")):
        shutil.copytree(os.path.join(SOURCE, "ndgui"), os.path.join(addons, "ndgui"),
                        ignore=shutil.ignore_patterns("__pycache__"))
    say("Restoring built-in providers, stock skin and stock layouts")
    tool(client, "select_providers.py", "--reset", optional=True)
    tool(client, "skin.py", "--restore", optional=True)
    tool(client, "square_buttons.py", "--restore", optional=True)
    removed = 0
    for folder in glob.glob(os.path.join(addons, "ndgui*")):
        if os.path.isdir(folder) and ours(folder):
            shutil.rmtree(folder)
            removed += 1
    say(f"Removed {removed} ndGUI packages. The stock UI is back on the next start.")


def pull(client):
    addons = os.path.join(client, "UI", "Addons")
    for name in sorted(n for n in os.listdir(SOURCE) if os.path.isdir(os.path.join(SOURCE, n))):
        src = os.path.join(addons, name)
        if not os.path.isdir(src):
            say(f"  {name}: not installed, kept repo copy")
            continue
        dest = os.path.join(SOURCE, name)
        shutil.rmtree(dest)
        shutil.copytree(src, dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        say(f"  {name}")
    for rel in GENERATED_FILES:
        path = os.path.join(SOURCE, rel)
        if os.path.exists(path):
            os.remove(path)
    say("Pulled the hand-made packages back into addons/. Review with: git status")


interactive = False


def menu(client):
    say(f"ndGUI for Spiritech {VERSION}\n")
    client = client or find_client() or ask_for_client()
    say(f"Game folder: {client}\n")
    say("  1) Install / update ndGUI")
    say("  2) Install, but keep the game's own screens stock (Options, login...)")
    say("  3) Uninstall (back to the stock UI)")
    say("  4) Quit")
    choice = input("\nPick 1-4 [1]: ").strip() or "1"
    say()
    if choice == "1":
        install(client)
    elif choice == "2":
        install(client, stock_screens=True)
    elif choice == "3":
        uninstall(client)


def main():
    global interactive
    parser = argparse.ArgumentParser(description="Install ndGUI for the Spiritech client.")
    parser.add_argument("--client", help="game client folder (the one with PRK.Client.exe and UI/)")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--pull", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--stock-screens", action="store_true")
    args = parser.parse_args()
    actions = args.install or args.uninstall or args.check or args.pull
    if not actions:
        interactive = True
        try:
            menu(find_client(args.client) if args.client else None)
        except SystemExit as stop:
            if stop.code not in (None, 0):
                say(f"\n{stop.code}")
        except Exception:
            traceback.print_exc()
        if sys.stdin.isatty():
            input("\nPress Enter to close.")
        return
    client = find_client(args.client)
    if not client:
        raise SystemExit("Could not find the Spiritech client. Run again with --client \"<folder with PRK.Client.exe>\".")
    if args.check:
        sys.exit(0 if check(client) else 1)
    if args.uninstall:
        uninstall(client)
    elif args.pull:
        pull(client)
    else:
        install(client, stock_screens=args.stock_screens)


if __name__ == "__main__":
    main()
