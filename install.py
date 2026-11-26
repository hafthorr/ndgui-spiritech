#!/usr/bin/env python3
"""ndGUI for Spiritech: installer / updater / uninstaller.

Players don't need this: they use the release zip and install.bat / install.ps1
(plain PowerShell, no Python). This script installs straight from a git checkout,
building everything on the spot. For developers, and for Linux/Mac.

Needs Python 3.8+ and Pillow:
    python install.py                      interactive menu
    python install.py --install            install or update from this folder (auto-detects the client)
    python install.py --update             get the newest release from GitHub and install it
                                           (git checkout: git pull; otherwise downloads the source)
    python install.py --install --client "D:/Games/PRK-AO-Native/client"
    python install.py --uninstall          put the stock UI back and remove ndGUI
    python install.py --check              only check the client and requirements
    python install.py --pull               copy edited packages from the client back into addons/

Install options:
    --stock-screens    leave the client's own screens stock (Options, login, character select...);
                       ndGUI's windows still get square buttons
    --keep-providers   leave the client's current HUD/window UI package choices alone
                       (do not rewrite Client.xml providers to ndGUI)

Quit the game first: the client reads the skin at start and rewrites prefs on exit.
Every client file the installer changes keeps a backup (*.stock / Client.xml.ndgui-backup-*),
and --uninstall restores them. See INSTALL.md.
"""
import argparse, glob, json, os, re, runpy, shutil, string, subprocess, sys, traceback

VERSION = "0.3.7"
REPO = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(REPO, "addons")
# Generated on the player's machine from their own client (never copied back by --pull).
GENERATED_FILES = [os.path.join("ndgui-lib", "lua", "table.lua")]
PROJECT = "hafthorr/ndgui-spiritech"  # public GitHub repository the updater reads releases from
MARKER = os.path.join("UI", "Addons", "ndgui", "installed-version.txt")  # same file install.ps1 writes


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


# Packages earlier releases installed that a newer one replaced. Left installed they would
# claim those roles again (0.2.7: mission-hub; Intel provides Chat).
OBSOLETE = (
    "ndgui-info",
    "ndgui-missions",
    "ndgui-mission-terminal",
    "ndgui-chat",
    "notum.ndgui-chat",
    "notum.ndgui",  # legacy theme package with no Provides
)


def copy_packages(client):
    addons = os.path.join(client, "UI", "Addons")
    os.makedirs(addons, exist_ok=True)
    for name in OBSOLETE:
        folder = os.path.join(addons, name)
        if os.path.isdir(folder) and ours(folder):
            shutil.rmtree(folder)
    names = sorted(n for n in os.listdir(SOURCE) if os.path.isdir(os.path.join(SOURCE, n)))
    for name in names:
        dest = os.path.join(addons, name)
        if os.path.isdir(dest):
            shutil.rmtree(dest)
        shutil.copytree(os.path.join(SOURCE, name), dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    say(f"  copied {len(names)} packages into {addons}")


# ---- snap-to-grid size (ndgui-lib/lua/grid.lua) ------------------------------------------
GRID_FILE = os.path.join("UI", "Addons", "ndgui-lib", "lua", "grid.lua")
GRID_RE = re.compile(r"^local SIZE = (\d+)", re.M)


def read_grid(client):
    path = os.path.join(client, GRID_FILE)
    if not os.path.exists(path):
        return None
    m = GRID_RE.search(open(path, encoding="utf-8").read())
    return int(m.group(1)) if m else None


def write_grid(client, size):
    path = os.path.join(client, GRID_FILE)
    code = open(path, encoding="utf-8").read()
    if not GRID_RE.search(code):
        raise SystemExit("ndgui-lib/lua/grid.lua has no 'local SIZE = ' line; reinstall ndGUI.")
    code = GRID_RE.sub(f"local SIZE = {size}", code, count=1)
    open(path, "w", encoding="utf-8", newline="\n").write(code)
    say(f"  snap grid: {size} px" if size >= 2 else "  snap grid: off")


def grid_size(text):
    size = int(text)
    if not 0 <= size <= 200:
        raise ValueError("grid size must be 0-200")
    return size


def grid_label(size):
    if size is None:
        return "not installed"
    return f"{size} px" if size >= 2 else "off"


def ask_grid(client):
    current = read_grid(client)
    if current is None:
        raise SystemExit("ndGUI is not installed in this folder yet; install it first.")
    say("Windows and HUD pieces snap to this grid while you move or resize them, when the game's")
    say("snapping is on (Options > Interface & HUD > Windows and HUD > magnetism above 0).")
    say(f"Now: {grid_label(current)}")
    answer = input("\nGrid size in pixels, e.g. 5, 10, 20, 25, 50 (0 = off) [keep]: ").strip()
    if not answer:
        return
    try:
        size = grid_size(answer)
    except ValueError:
        raise SystemExit("Give a whole number from 0 to 200.")
    write_grid(client, size)
    say("Restart the game to use it.")


# ---- actions ---------------------------------------------------------------------------
def install(client, stock_screens=False, grid=None, keep_providers=False):
    if not check(client):
        raise SystemExit("\nFix the items above and run the installer again.")
    say("\n[1/5] Copying ndGUI packages")
    kept_grid = read_grid(client)  # the copy replaces grid.lua; keep the player's grid size
    copy_packages(client)
    if grid is not None or (kept_grid is not None and kept_grid != read_grid(client)):
        write_grid(client, grid if grid is not None else kept_grid)
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
    if keep_providers:
        say("\n[5/5] Keeping current HUD/window providers (as asked)")
    else:
        say("\n[5/5] Switching the HUD and windows to ndGUI")
        if not tool(client, "select_providers.py", optional=True):
            say("  Pick them by hand in the game: Options > Interface & HUD > UI packages.")
    with open(os.path.join(client, MARKER), "w", encoding="utf-8", newline="\n") as marker:
        marker.write(VERSION)
    say("\nDone! Start the game. If something still looks stock, log out to character select and back in once.")
    say("To undo everything: python install.py --uninstall")
    say("Bugs, issues, ideas? Ask 'thedenis' on the Project Rubi-Ka Discord.")


def installed_version(client):
    path = os.path.join(client, MARKER)
    if os.path.exists(path):
        return open(path, encoding="utf-8").read().strip()
    if os.path.isdir(os.path.join(client, "UI", "Addons", "ndgui")):
        return "an older version"
    return None


def version_key(text):
    return tuple(int(part) for part in re.findall(r"\d+", text)[:3])


def latest_release():
    import urllib.request
    url = f"https://api.github.com/repos/{PROJECT}/releases/latest"
    request = urllib.request.Request(url, headers={"User-Agent": "ndgui-installer"})
    try:
        with urllib.request.urlopen(request, timeout=30) as reply:
            return json.load(reply)["tag_name"]
    except Exception as error:
        raise SystemExit(f"Could not reach GitHub ({error}). Check your connection, or get it by hand: "
                         f"https://github.com/{PROJECT}/releases")


def run_installer(folder, client, keep_providers=False):
    """Run the install.py of the new copy: this process still has the old code loaded."""
    command = [sys.executable, os.path.join(folder, "install.py"), "--install", "--client", client]
    if keep_providers:
        command.append("--keep-providers")
    if subprocess.run(command).returncode != 0:
        raise SystemExit("Installing the new version failed (see above).")


def download_source(tag):
    import tarfile, tempfile, urllib.request
    work = os.path.join(tempfile.gettempdir(), f"ndgui-spiritech-update-{tag}")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    url = f"https://github.com/{PROJECT}/archive/refs/tags/{tag}.tar.gz"
    archive = os.path.join(work, "source.tar.gz")
    say(f"Downloading ndGUI {tag} (source)...")
    request = urllib.request.Request(url, headers={"User-Agent": "ndgui-installer"})
    with urllib.request.urlopen(request, timeout=120) as reply, open(archive, "wb") as out:
        shutil.copyfileobj(reply, out)
    with tarfile.open(archive) as tar:
        root = os.path.realpath(work)
        for member in tar.getmembers():
            target = os.path.realpath(os.path.join(work, member.name))
            if not target.startswith(root + os.sep) or member.issym() or member.islnk():
                raise SystemExit(f"Refusing a suspicious path in the download: {member.name}")
        if sys.version_info >= (3, 12):
            tar.extractall(work, filter="data")
        else:
            tar.extractall(work)
    found = glob.glob(os.path.join(work, "*", "install.py"))
    if not found:
        raise SystemExit("The download has no install.py.")
    return os.path.dirname(found[0])


def update(client, keep_providers=False):
    installed = installed_version(client)
    say(f"Installed: {installed or 'nothing yet'}")
    say("Checking GitHub for the newest release...")
    tag = latest_release()
    latest = tag.lstrip("v")
    say(f"Newest:    {latest}")
    if installed and re.match(r"\d", installed) and version_key(latest) <= version_key(installed):
        say(f"\nYou already have the newest ndGUI ({installed}).")
        again = interactive and input("Reinstall it anyway (e.g. after a game patch)? [y/N]: ").strip().lower() == "y"
        if not again:
            return
    while client_running():
        if not interactive:
            raise SystemExit("The game (PRK.Client.exe) is running. Quit it first.")
        input("The game is running. Quit it, then press Enter... ")
    if os.path.isdir(os.path.join(REPO, ".git")) and shutil.which("git"):
        say("\nThis is a git checkout: updating it with git pull...")
        pulled = subprocess.run(["git", "-C", REPO, "pull", "--ff-only"])
        if pulled.returncode != 0:
            raise SystemExit("git pull failed (local changes?). Fix the checkout, then run: python install.py --install")
        run_installer(REPO, client, keep_providers=keep_providers)
    else:
        folder = download_source(tag)
        run_installer(folder, client, keep_providers=keep_providers)
        say(f"\nThe {latest} files are in: {folder}")
        say("Use that folder (or a fresh download) for future installs and uninstalls.")


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
    for pattern in ("ndgui*", "notum.ndgui*"):
        for folder in glob.glob(os.path.join(addons, pattern)):
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


def menu(client, keep_providers=False):
    say(f"ndGUI for Spiritech {VERSION}\n")
    client = client or find_client() or ask_for_client()
    say(f"Game folder: {client}\n")
    installed = installed_version(client)
    if installed:
        say(f"Installed: ndGUI {installed}\n")
    if keep_providers:
        say("  (--keep-providers: install/update will leave current HUD/window providers alone)\n")
    say(f"  1) Install / update to {VERSION} (this folder)")
    say("  2) Update to the newest version (from GitHub)")
    say(f"  3) Install {VERSION}, but keep the game's own screens stock (Options, login...)")
    say("  4) Uninstall (back to the stock UI)")
    say(f"  5) Snap-to-grid size (now: {grid_label(read_grid(client))})")
    say("  6) Quit")
    choice = input("\nPick 1-6 [1]: ").strip() or "1"
    say()
    if choice == "1":
        install(client, keep_providers=keep_providers)
    elif choice == "2":
        update(client, keep_providers=keep_providers)
    elif choice == "3":
        install(client, stock_screens=True, keep_providers=keep_providers)
    elif choice == "4":
        uninstall(client)
    elif choice == "5":
        ask_grid(client)


def main():
    global interactive
    parser = argparse.ArgumentParser(description="Install ndGUI for the Spiritech client.")
    parser.add_argument("--client", help="game client folder (the one with PRK.Client.exe and UI/)")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--update", action="store_true", help="install the newest GitHub release")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--pull", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--stock-screens", action="store_true")
    parser.add_argument("--keep-providers", action="store_true",
                        help="leave current HUD/window UI package choices alone")
    parser.add_argument("--grid", type=grid_size, metavar="PX",
                        help="snap-to-grid size in pixels, 0 = off (default: keep; 10 on a first install)")
    args = parser.parse_args()
    actions = args.install or args.uninstall or args.check or args.pull or args.update
    if args.grid is not None and not actions:
        client = find_client(args.client)
        if not client or read_grid(client) is None:
            raise SystemExit("ndGUI is not installed in that client yet; install it first.")
        write_grid(client, args.grid)
        return
    if not actions:
        interactive = True
        try:
            menu(find_client(args.client) if args.client else None,
                 keep_providers=args.keep_providers)
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
    if args.update:
        update(client, keep_providers=args.keep_providers)
    elif args.uninstall:
        uninstall(client)
    elif args.pull:
        pull(client)
    else:
        install(client, stock_screens=args.stock_screens, grid=args.grid,
                keep_providers=args.keep_providers)


if __name__ == "__main__":
    main()
