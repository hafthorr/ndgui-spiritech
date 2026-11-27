#!/usr/bin/env python3
"""Build the Spiritech Addons marketplace suite zip.

    python build_marketplace.py
    python build_marketplace.py --from-zip release/ndgui-spiritech-0.4.0.zip
    python build_marketplace.py --addons-dir /path/to/client/UI/Addons
    API_VERSION=0.1.0 python build_marketplace.py --version 0.4.0

Spiritech publishing rules (same as modern-ui):
  - each package in its own top-level folder with a package.xml (nothing else at the top level)
  - folder name == Package id
  - every manifest carries the same version="" and apiVersion=""
  - all required libraries are bundled
  - LICENSE is copied into every package folder
  - tools/ and __pycache__/ are excluded

This zip is packages only (no install.ps1, skin overlay, or Layouts). In-game HUD
Chrome/buttons/compass/maps are marketplace-complete: library:// art and stock
GFX_GUI_* / primitives. Residual -SkinLayouts is optional Login/Options squaring
only. See docs/marketplace-listing.md.
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import shutil
import sys
import tempfile
import zipfile

REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, REPO)
from install import VERSION  # noqa: E402

DEFAULT_API_VERSION = "0.1.0"
PACKAGE_OPEN = re.compile(r"<Package\b[^>]*>")
PACKAGE_ID = re.compile(r'\bid="([^"]+)"')
REQUIRES = re.compile(r'<Requires\s+package="([^"]+)"')
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
DEV_ONLY = ("tools", "tests", "examples", "fixtures", "__pycache__")
# Atlas ids that require skin.py / cd_image merge — forbidden in marketplace packages.
NDGUI_ATLAS = re.compile(
    r"""(?:gfxid_\w+\s*=\s*["']|["'])GFX_(?:GUI_)?NDGUI_[A-Z0-9_]+["']"""
)
SCAN_SUFFIXES = (".xml", ".lua")


def stamp_manifest(text: str, version: str, api_version: str) -> str:
    def replace(match: re.Match[str]) -> str:
        tag = match.group(0)
        tag = re.sub(r'\s+(version|apiVersion)="[^"]*"', "", tag)
        if tag.endswith("/>"):
            return tag[:-2].rstrip() + f' version="{version}" apiVersion="{api_version}" />'
        return tag[:-1].rstrip() + f' version="{version}" apiVersion="{api_version}">'

    stamped, count = PACKAGE_OPEN.subn(replace, text, count=1)
    if count != 1:
        raise SystemExit("package.xml has no <Package ...> element to stamp")
    return stamped


def package_id(manifest_text: str) -> str:
    match = PACKAGE_ID.search(manifest_text)
    if not match:
        raise SystemExit("package.xml has no Package id")
    return match.group(1)


def extract_addons_from_player_zip(archive: str, dest: str) -> None:
    found = False
    with zipfile.ZipFile(archive) as zf:
        for name in zf.namelist():
            parts = name.split("/")
            # ndgui-spiritech-<ver>/game/Addons/<package>/...
            if len(parts) < 5 or parts[1] != "game" or parts[2] != "Addons" or not parts[-1]:
                continue
            if any(part in DEV_ONLY for part in parts[3:]):
                continue
            found = True
            target = os.path.join(dest, *parts[3:])
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with zf.open(name) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
    if not found:
        raise SystemExit(f"no game/Addons packages in {archive}")


def copy_addons_dir(source: str, dest: str) -> None:
    for name in sorted(os.listdir(source)):
        src = os.path.join(source, name)
        if not os.path.isdir(src):
            continue
        if not name.startswith("ndgui") and not name.startswith("notum.ndgui"):
            continue
        shutil.copytree(
            src,
            os.path.join(dest, name),
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", *DEV_ONLY),
        )


# Legacy theme package has no <Provides>.
EXCLUDE_IDS = {"notum.ndgui"}
OBSOLETE_MEMBERS: set[str] = set()


def bundle_hubs_in(addons_dir: str) -> None:
    """Merge related role packages so the suite fits the portal's 32-package cap."""
    tools = os.path.join(REPO, "addons", "ndgui", "tools")
    if tools not in sys.path:
        sys.path.insert(0, tools)
    os.environ["NDGUI_ADDONS"] = addons_dir
    import bundle_hubs  # noqa: WPS433

    bundle_hubs.main()


def stage_suite(addons_src: str, stage: str, version: str, api_version: str, license_path: str) -> list[str]:
    ids: list[str] = []
    for folder in sorted(glob.glob(os.path.join(addons_src, "*"))):
        if not os.path.isdir(folder):
            continue
        manifest_path = os.path.join(folder, "package.xml")
        if not os.path.isfile(manifest_path):
            raise SystemExit(f"missing {manifest_path}")
        text = open(manifest_path, encoding="utf-8").read()
        pkg_id = package_id(text)
        if not pkg_id.startswith("notum.ndgui"):
            raise SystemExit(f"{manifest_path}: expected notum.ndgui* id, got {pkg_id}")
        if pkg_id in EXCLUDE_IDS or os.path.basename(folder) in OBSOLETE_MEMBERS:
            continue
        dest = os.path.join(stage, pkg_id)
        if os.path.exists(dest):
            raise SystemExit(f"duplicate package id {pkg_id}")
        shutil.copytree(folder, dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", *DEV_ONLY))
        stamped = stamp_manifest(open(os.path.join(dest, "package.xml"), encoding="utf-8").read(), version, api_version)
        open(os.path.join(dest, "package.xml"), "w", encoding="utf-8", newline="\n").write(stamped)
        shutil.copyfile(license_path, os.path.join(dest, "LICENSE"))
        ids.append(pkg_id)
    return ids


def reject_ndgui_atlas(stage: str, ids: list[str]) -> None:
    """Fail the build if any staged package still references custom NDGUI atlas ids."""
    hits: list[str] = []
    for pkg_id in ids:
        root = os.path.join(stage, pkg_id)
        for dirpath, dirnames, files in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in DEV_ONLY]
            for name in files:
                if not name.endswith(SCAN_SUFFIXES):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    text = open(path, encoding="utf-8").read()
                except UnicodeDecodeError:
                    continue
                for match in NDGUI_ATLAS.finditer(text):
                    rel = os.path.relpath(path, stage).replace(os.sep, "/")
                    hits.append(f"{rel}: {match.group(0)}")
    if hits:
        print("marketplace packages must not reference NDGUI atlas ids:", file=sys.stderr)
        for line in hits[:40]:
            print(f"  {line}", file=sys.stderr)
        if len(hits) > 40:
            print(f"  ... and {len(hits) - 40} more", file=sys.stderr)
        raise SystemExit(1)


def validate_suite(stage: str, version: str, api_version: str, ids: list[str]) -> None:
    fail = False
    id_set = set(ids)
    for pkg_id in ids:
        folder = os.path.join(stage, pkg_id)
        if os.path.basename(folder) != pkg_id:
            print(f"{folder}: folder name != id {pkg_id}", file=sys.stderr)
            fail = True
        manifest = os.path.join(folder, "package.xml")
        text = open(manifest, encoding="utf-8").read()
        if f'version="{version}"' not in text or f'apiVersion="{api_version}"' not in text:
            print(f"{manifest}: missing stamped version/apiVersion", file=sys.stderr)
            fail = True
        if not os.path.isfile(os.path.join(folder, "LICENSE")):
            print(f"{folder}: missing LICENSE", file=sys.stderr)
            fail = True
        for req in REQUIRES.findall(text):
            if req not in id_set:
                print(f"required package {req} is not bundled", file=sys.stderr)
                fail = True
    if fail:
        raise SystemExit(1)
    reject_ndgui_atlas(stage, ids)


def write_zip(stage: str, archive: str) -> None:
    os.makedirs(os.path.dirname(archive) or ".", exist_ok=True)
    if os.path.exists(archive):
        os.remove(archive)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(stage):
            dirs[:] = [d for d in dirs if d not in DEV_ONLY]
            for name in files:
                full = os.path.join(root, name)
                zf.write(full, os.path.relpath(full, stage).replace(os.sep, "/"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the Spiritech marketplace suite zip for ndGUI.")
    parser.add_argument("--version", default=VERSION, help=f"suite version (default {VERSION})")
    parser.add_argument(
        "--api-version",
        default=os.environ.get("API_VERSION", DEFAULT_API_VERSION),
        help=f"client addon API version (default {DEFAULT_API_VERSION})",
    )
    parser.add_argument(
        "--from-zip",
        help="player release zip to read game/Addons from (default: release/ndgui-spiritech-<version>.zip)",
    )
    parser.add_argument(
        "--addons-dir",
        help="directory of built packages (alternative to --from-zip); folder names may be ndgui-*",
    )
    parser.add_argument(
        "--out",
        help="output zip path (default: release/ndgui-<version>.zip)",
    )
    args = parser.parse_args()
    version = args.version
    api_version = args.api_version
    if not SEMVER.match(version):
        raise SystemExit("version must be MAJOR.MINOR.PATCH")
    if not SEMVER.match(api_version):
        raise SystemExit("api-version must be MAJOR.MINOR.PATCH")

    license_path = os.path.join(REPO, "LICENSE")
    if not os.path.isfile(license_path):
        raise SystemExit("LICENSE missing from repo root")

    work = tempfile.mkdtemp(prefix="ndgui-marketplace-")
    try:
        extracted = os.path.join(work, "addons")
        os.makedirs(extracted)
        if args.addons_dir:
            copy_addons_dir(args.addons_dir, extracted)
        else:
            archive = args.from_zip or os.path.join(REPO, "release", f"ndgui-spiritech-{version}.zip")
            if not os.path.isfile(archive):
                raise SystemExit(
                    f"missing {archive}; run build_release.py first or pass --from-zip / --addons-dir"
                )
            extract_addons_from_player_zip(archive, extracted)

        # Hub bundling is disabled: the embed/deferred-boot approach crashed the client.
        # Mission Hub works because members are real modules that adopt a load-time shell;
        # bundle_hubs.py did not. Do not re-enable until redesigned to that pattern.
        # bundle_hubs_in(extracted)

        stage = os.path.join(work, "stage")
        os.makedirs(stage)
        ids = stage_suite(extracted, stage, version, api_version, license_path)
        if not ids:
            raise SystemExit("no ndGUI packages found to stage")
        validate_suite(stage, version, api_version, ids)
        out = args.out or os.path.join(REPO, "release", f"ndgui-{version}.zip")
        write_zip(stage, out)
        print(f"{len(ids)} packages")
        print(out)
        print(f"{os.path.getsize(out) / 1e6:.1f} MB")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
