#!/usr/bin/env python3
"""Build the player release: dist/ndgui-spiritech-<version>.zip (no Python needed to install it).

    python -m pip install pillow
    python build_release.py [--client "C:/Games/PRK-AO-Native/client"]

Works on a staging copy made from your client's *stock* files (the *.stock backups when
ndGUI is already installed), so your live game is never touched:
  1. copies addons/ (the 9 hand-made packages) into the staging client,
  2. runs the generators: fork_windows.py, fork_hud.py, lib_table.py, square_buttons.py,
  3. renders the DarkTech skin as an overlay (only changed/new graphics, skin.py --overlay),
  4. packs  game/Addons (39 packages), game/Layouts + game/Packages (patched screens),
     game/skin (overlay), install.ps1 + install.bat + docs  into one zip.

Rebuild after a game patch so the shipped windows match the new client version.
"""
import argparse, filecmp, glob, os, shutil, subprocess, sys, zipfile

REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, REPO)
from install import VERSION, find_client  # noqa: E402

DEV_ONLY = ("tools", "tests", "examples", "fixtures")  # not shipped inside the ndgui package


def stock(path):
    return path + ".stock" if os.path.exists(path + ".stock") else path


def stage_client(client, stage):
    ui = os.path.join(stage, "UI")
    shutil.copytree(os.path.join(client, "UI", "Packages"), os.path.join(ui, "Packages"),
                    ignore=shutil.ignore_patterns("*.stock"))
    core_window = os.path.join(client, "UI", "Packages", "Core", "window.xml")
    shutil.copyfile(stock(core_window), os.path.join(ui, "Packages", "Core", "window.xml"))
    os.makedirs(os.path.join(ui, "Layouts"))
    for path in glob.glob(os.path.join(client, "UI", "Layouts", "*.xml")):
        shutil.copyfile(stock(path), os.path.join(ui, "Layouts", os.path.basename(path)))
    skin_src = os.path.join(client, "cd_image", "gui", "Default")
    skin_dst = os.path.join(stage, "cd_image", "gui", "Default")
    os.makedirs(skin_dst)
    for name in ("Graphics.uvgi", "Graphics.uvga", "GUIColors.xml"):
        shutil.copyfile(stock(os.path.join(skin_src, name)), os.path.join(skin_dst, name))
    os.makedirs(os.path.join(ui, "Addons"))
    for name in os.listdir(os.path.join(REPO, "addons")):
        shutil.copytree(os.path.join(REPO, "addons", name), os.path.join(ui, "Addons", name),
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    return ui


def run(ui, *args):
    print("  >", " ".join(args))
    env = dict(os.environ, NDGUI_ASSUME_CLOSED="1")
    subprocess.run([sys.executable, *args], cwd=os.path.join(ui, "Addons", "ndgui"), check=True, env=env,
                   stdout=subprocess.DEVNULL)


def client_version(client):
    parts = []
    for name in ("spiritech.version.txt", "version.txt"):
        path = os.path.join(client, name)
        if os.path.exists(path):
            parts.append(open(path, encoding="utf-8", errors="replace").read().strip())
    return " / ".join(parts) or "unknown"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--client")
    args = parser.parse_args()
    client = find_client(args.client)
    if not client:
        raise SystemExit("client not found; pass --client")
    work = os.path.join(REPO, "build")
    shutil.rmtree(work, ignore_errors=True)
    stage = os.path.join(work, "stage")
    name = f"ndgui-spiritech-{VERSION}"
    out = os.path.join(work, name)
    print(f"Building {name} from {client}")
    ui = stage_client(client, stage)
    run(ui, "tools/fork_windows.py")
    run(ui, "tools/fork_hud.py")
    run(ui, "tools/lib_table.py")
    run(ui, "tools/square_buttons.py")
    game = os.path.join(out, "game")
    run(ui, "tools/skin.py", "--overlay", os.path.join(game, "skin"))

    # packages
    for folder in sorted(glob.glob(os.path.join(ui, "Addons", "ndgui*"))):
        dest = os.path.join(game, "Addons", os.path.basename(folder))
        ignore = shutil.ignore_patterns("__pycache__", "*.pyc", *DEV_ONLY) if os.path.basename(folder) == "ndgui" \
            else shutil.ignore_patterns("__pycache__", "*.pyc")
        shutil.copytree(folder, dest, ignore=ignore)
    # patched game screens: only files that differ from stock
    os.makedirs(os.path.join(game, "Layouts"))
    shipped = 0
    for path in glob.glob(os.path.join(ui, "Layouts", "*.xml")):
        original = stock(os.path.join(client, "UI", "Layouts", os.path.basename(path)))
        if not filecmp.cmp(path, original, shallow=False):
            shutil.copyfile(path, os.path.join(game, "Layouts", os.path.basename(path)))
            shipped += 1
    os.makedirs(os.path.join(game, "Packages", "Core"))
    shutil.copyfile(os.path.join(ui, "Packages", "Core", "window.xml"), os.path.join(game, "Packages", "Core", "window.xml"))
    # installer + docs
    for doc in ("install.ps1", "install.bat", "README.md", "INSTALL.md", "LICENSE", "CHANGELOG.md"):
        shutil.copyfile(os.path.join(REPO, doc), os.path.join(out, doc))
    with open(os.path.join(game, "build-info.txt"), "w", encoding="utf-8", newline="\n") as info:
        info.write(f"version={VERSION}\nclient={client_version(client)}\n")

    packages = len(glob.glob(os.path.join(game, "Addons", "*")))
    graphics = len(glob.glob(os.path.join(game, "skin", "*.png")))
    # release/ is committed: pushing a v<version> tag makes GitLab CI publish this zip as the release
    os.makedirs(os.path.join(REPO, "release"), exist_ok=True)
    for old in glob.glob(os.path.join(REPO, "release", "*.zip")):
        os.remove(old)
    archive = os.path.join(REPO, "release", name + ".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(out):
            for f in files:
                full = os.path.join(root, f)
                zf.write(full, os.path.relpath(full, work))
    shutil.rmtree(stage, ignore_errors=True)
    print(f"\n{packages} packages, {shipped} game screens, {graphics} skin graphics")
    print(f"built {archive} ({os.path.getsize(archive) / 1e6:.1f} MB); unpacked copy in {out}")


if __name__ == "__main__":
    main()
