"""Merge related ndGUI role packages into multi-Provide hubs (marketplace ≤32 packages).

DO NOT RUN. Deferred load() of member main.lua crashes the client (SIGABRT).
Kept as a record of the approach that failed. A hub has to follow Mission Hub:
load-time shell, real modules, shell.window(). See PROGRESS.md.

Run on an Addons tree (client or staging):
  python tools/bundle_hubs.py
  NDGUI_ADDONS=/path/to/UI/Addons python tools/bundle_hubs.py

Each hub keeps one Options row per role (same as Mission Hub). Member scripts are
embedded and only booted in the VM that receives that role's first callback, because
the client runs one package VM per selected role.

Idempotent: skips hubs that already exist; removes obsolete member folders when merging.
"""
from __future__ import annotations

import glob
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.environ.get("NDGUI_ADDONS") or os.path.join(HERE, "..", ".."))

# hub folder slug (ndgui-<slug>) -> (display name, member folder suffixes under ndgui-/notum.ndgui-)
HUBS = (
    (
        "chat-hub",
        "Notum Dovvetech Chat",
        ("chat", "chat-config", "chat-frame"),
    ),
    (
        "ncu-hub",
        "Notum Dovvetech NCU",
        ("ncu", "target-ncu"),
    ),
    (
        "maps",
        "Notum Dovvetech Maps",
        ("playfield-map", "planet-map"),
    ),
    (
        "raid-hub",
        "Notum Dovvetech Raid",
        ("raid", "raid-bar"),
    ),
    (
        "team-hub",
        "Notum Dovvetech Team",
        ("team", "team-invite"),
    ),
    (
        "hud-indicators",
        "Notum Dovvetech HUD Indicators",
        ("sneak-indicator", "logout-progress", "faction"),
    ),
)

SKIP_COPY = {"package.xml", "LICENSE"}
LOAD = re.compile(
    r"""(?:ui\.(?P<call>load|shared_layout)\(\s*(?P<q1>["'])(?P<name1>[^"']+\.xml)(?P=q1)\s*\)"""
    r"""|template\s*=\s*(?P<q2>["'])(?P<name2>[^"']+\.xml)(?P=q2))"""
)
FUNC = re.compile(r"^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
PACKAGE_ID = re.compile(r'<Package\b[^>]*\bid="([^"]+)"')
PROVIDES = re.compile(r'<Provides\s+role="([^"]+)"\s*/>')
REQUIRES = re.compile(r'<Requires\s+package="([^"]+)"\s*/>')
OPTIONS = re.compile(r"<Options\b.*?</Options>", re.S)
SCRIPTS = re.compile(r'<(Script|InteractionScript)\s+src="([^"]+)"\s*/>')


def resolve_member(addons: str, suffix: str) -> str | None:
    for prefix in ("notum.ndgui-", "ndgui-"):
        path = os.path.join(addons, prefix + suffix)
        if os.path.isdir(path) and os.path.isfile(os.path.join(path, "package.xml")):
            return path
    return None


def rewrite_loads(text: str, rename: dict[str, str]) -> str:
    def repl(match: re.Match[str]) -> str:
        if match.group("call"):
            name = match.group("name1")
            if name.startswith("library://") or name.startswith("gfx://"):
                return match.group(0)
            new = rename.get(name, name)
            q = match.group("q1")
            return f"ui.{match.group('call')}({q}{new}{q})"
        name = match.group("name2")
        if name.startswith("library://") or name.startswith("gfx://"):
            return match.group(0)
        new = rename.get(name, name)
        q = match.group("q2")
        return f"template = {q}{new}{q}"

    return LOAD.sub(repl, text)


def member_slug(suffix: str) -> str:
    return suffix.replace("-", "_")


def collect_member(path: str, suffix: str) -> dict:
    manifest = open(os.path.join(path, "package.xml"), encoding="utf-8").read()
    roles = PROVIDES.findall(manifest)
    requires = REQUIRES.findall(manifest)
    options = OPTIONS.findall(manifest)
    scripts = SCRIPTS.findall(manifest)
    rename: dict[str, str] = {}
    raw: dict[str, bytes] = {}
    slug = member_slug(suffix)
    for name in os.listdir(path):
        if name in SKIP_COPY or name.startswith("."):
            continue
        src = os.path.join(path, name)
        if not os.path.isfile(src):
            continue
        dest_name = f"{slug}_{name}"
        rename[name] = dest_name
        raw[dest_name] = open(src, "rb").read()
    files: dict[str, bytes] = {}
    for dest_name, data in raw.items():
        if dest_name.endswith((".lua", ".xml")):
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                files[dest_name] = data
            else:
                files[dest_name] = rewrite_loads(text, rename).encode("utf-8")
        else:
            files[dest_name] = data
    callbacks: list[str] = []
    for kind, src in scripts:
        prefixed = rename.get(src)
        if not prefixed or not prefixed.endswith(".lua"):
            continue
        body = files[prefixed].decode("utf-8")
        for name in FUNC.findall(body):
            if name not in callbacks:
                callbacks.append(name)
    return {
        "suffix": suffix,
        "slug": slug,
        "roles": roles,
        "requires": requires,
        "options": options,
        "scripts": [(kind, rename[src]) for kind, src in scripts if src in rename],
        "files": files,
        "callbacks": callbacks,
        "rename": rename,
    }


def embed_module(slug: str, member: dict) -> str:
    """One ui.define module that boots this member's scripts into _G once."""
    chunks: list[str] = []
    for kind, src in member["scripts"]:
        if kind != "Script" or not src.endswith(".lua"):
            continue
        body = member["files"][src].decode("utf-8")
        chunks.append(body)
    # InteractionScript files also need to run for raid/team/etc.
    for kind, src in member["scripts"]:
        if kind != "InteractionScript" or not src.endswith(".lua"):
            continue
        body = member["files"][src].decode("utf-8")
        chunks.append(body)
    if not chunks:
        raise SystemExit(f"hub member {member['suffix']} has no scripts to embed")
    # Long-bracket payload; bump equals if the source contains the closer.
    eq = 0
    payload = "\n".join(chunks)
    while True:
        open_b = "[" + ("=" * eq) + "["
        close_b = "]" + ("=" * eq) + "]"
        if close_b not in payload:
            break
        eq += 1
    mod = f"ndgui.hub_{slug}_{member['slug']}"
    return (
        f"ui.define({mod!r}, function()\n"
        f"\tlocal src = {open_b}{payload}{close_b}\n"
        f"\treturn {{\n"
        f"\t\tboot = function()\n"
        f"\t\t\tassert(load(src, \"={member['suffix']}\", \"t\", _G))()\n"
        f"\t\tend,\n"
        f"\t}}\n"
        f"end)\n"
    )


def hub_main(hub_slug: str, members: list[dict]) -> str:
    # After boot, capture real callbacks into impl (stubs would recurse if called by name).
    # shell.mount: client requires a root widget while scripts load (same as mission-hub).
    lines = [
        f"-- ndGUI hub ({hub_slug}): one package VM per selected role; boot only that member.",
        'ui.require("notum.ndgui-lib/grid")',
        'ui.require("notum.ndgui-lib/shell").mount()',
        "local kind",
        "local impl = {}",
        "local function ensure(role, mod)",
        "\tif kind and kind ~= role then",
        "\t\treturn false",
        "\tend",
        "\tif not kind then",
        "\t\tkind = role",
        "\t\tui.require(mod).boot()",
        "\t\tfor name, fn in pairs(_G) do",
        "\t\t\tif type(fn) == \"function\" and name ~= \"ensure\" then",
        "\t\t\t\timpl[name] = fn",
        "\t\t\tend",
        "\t\tend",
        "\tend",
        "\treturn true",
        "end",
        "",
    ]
    for member in members:
        mod = f"ndgui.hub_{hub_slug.replace('-', '_')}_{member['slug']}"
        role_key = member["suffix"]
        for cb in member["callbacks"]:
            lines.append(f"function {cb}(...)")
            lines.append(f'\tif not ensure("{role_key}", "{mod}") then')
            lines.append("\t\treturn")
            lines.append("\tend")
            lines.append(f"\tlocal fn = impl[{cb!r}]")
            lines.append("\tif fn then")
            lines.append("\t\treturn fn(...)")
            lines.append("\tend")
            lines.append("end")
            lines.append("")
    return "\n".join(lines)


def write_manifest(hub_id: str, title: str, members: list[dict], module_scripts: list[str]) -> str:
    requires = []
    for member in members:
        for req in member["requires"]:
            if req not in requires and req != hub_id:
                requires.append(req)
    if "notum.ndgui-lib" not in requires:
        requires.insert(0, "notum.ndgui-lib")
    lines = [f'<Package id="{hub_id}" name="{title}">']
    for req in requires:
        lines.append(f'  <Requires package="{req}" />')
    for member in members:
        for role in member["roles"]:
            lines.append(f'  <Provides role="{role}" />')
    for member in members:
        for block in member["options"]:
            for line in block.splitlines():
                lines.append("  " + line if not line.startswith("  ") else line)
    for src in module_scripts:
        lines.append(f'  <Script src="{src}" />')
    lines.append('  <Script src="main.lua" />')
    # InteractionScript: stock expects these registered; embed already runs them in boot.
    lines.append("</Package>\n")
    return "\n".join(lines)


def merge_hub(addons: str, slug: str, title: str, suffixes: tuple[str, ...]) -> str | None:
    hub_names = (f"notum.ndgui-{slug}", f"ndgui-{slug}")
    existing = next((os.path.join(addons, n) for n in hub_names if os.path.isdir(os.path.join(addons, n))), None)
    members_paths = []
    for suffix in suffixes:
        path = resolve_member(addons, suffix)
        if path:
            members_paths.append((suffix, path))
    if existing and not members_paths:
        return None  # already merged
    if len(members_paths) < 2:
        missing = [s for s in suffixes if not resolve_member(addons, s)]
        if existing:
            return None
        print(f"skip {slug}: need members, missing {missing}", file=sys.stderr)
        return None

    hub_id = f"notum.ndgui-{slug}"
    dest = os.path.join(addons, hub_id)
    # Prefer replacing notum.* name; remove ndgui-* alias if present.
    if existing and existing != dest:
        shutil.rmtree(existing)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)

    members = [collect_member(path, suffix) for suffix, path in members_paths]
    module_scripts: list[str] = []
    hub_key = slug.replace("-", "_")
    for member in members:
        for name, data in member["files"].items():
            # lua scripts are embedded; still keep xml/assets on disk for ui.load
            if name.endswith(".lua") and any(name == src for _, src in member["scripts"]):
                continue
            open(os.path.join(dest, name), "wb").write(data)
        mod_file = f"hub_{member['slug']}.lua"
        open(os.path.join(dest, mod_file), "w", encoding="utf-8", newline="\n").write(
            embed_module(hub_key, member)
        )
        module_scripts.append(mod_file)

    open(os.path.join(dest, "main.lua"), "w", encoding="utf-8", newline="\n").write(hub_main(slug, members))
    open(os.path.join(dest, "package.xml"), "w", encoding="utf-8", newline="\n").write(
        write_manifest(hub_id, title, members, module_scripts)
    )

    for suffix, path in members_paths:
        shutil.rmtree(path)
        # also remove alternate prefix if both somehow exist
        other = resolve_member(addons, suffix)
        if other:
            shutil.rmtree(other)

    roles = [r for m in members for r in m["roles"]]
    print(f"{hub_id}: {len(members_paths)} members -> roles {roles}")
    return hub_id


def main() -> None:
    if not os.path.isdir(ADDONS):
        raise SystemExit(f"addons dir not found: {ADDONS}")
    print(f"bundling hubs in {ADDONS}")
    for slug, title, suffixes in HUBS:
        merge_hub(ADDONS, slug, title, suffixes)
    # Drop legacy non-role package from trees that still have it (marketplace exclude).
    for name in ("notum.ndgui", "ndgui"):
        # only the bare theme package (has theme.lua / no Provides)
        path = os.path.join(ADDONS, name)
        if not os.path.isdir(path):
            continue
        manifest = os.path.join(path, "package.xml")
        if not os.path.isfile(manifest):
            continue
        text = open(manifest, encoding="utf-8").read()
        if 'id="notum.ndgui"' in text or 'id="ndgui"' in text:
            if not PROVIDES.search(text):
                print(f"remove legacy {name}")
                shutil.rmtree(path)


if __name__ == "__main__":
    main()
