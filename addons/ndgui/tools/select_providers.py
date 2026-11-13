"""Select every installed notum.ndgui-* provider in the client's machine prefs.

Run: python tools/select_providers.py          (select all ndGUI providers)
     python tools/select_providers.py --reset  (remove ndGUI selections -> built-ins)

The client must be closed: it rewrites prefs on exit. Client.xml is backed up first.
Selection key format (observed): UiPackageProvider_<role without "prk.", "-" -> "_">.
"""
import glob, os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.path.join(HERE, "..", ".."))
def prefs_path():
    """Machine prefs: %LOCALAPPDATA%/ProjectRubiKa/prefs on Windows, the same product root
    under ~/.local/share elsewhere. NDGUI_PREFS overrides (full path to Client.xml)."""
    if os.environ.get("NDGUI_PREFS"):
        return os.environ["NDGUI_PREFS"]
    if os.environ.get("LOCALAPPDATA"):
        root = os.environ["LOCALAPPDATA"]
    else:
        root = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(root, "ProjectRubiKa", "prefs", "Client.xml")


PREFS = prefs_path()


def client_running():
    if os.environ.get("NDGUI_ASSUME_CLOSED") == "1":  # developer testing against a copy of the client
        return False
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq PRK.Client.exe"], capture_output=True, text=True).stdout
        return "PRK.Client.exe" in out
    return subprocess.run(["pgrep", "-f", "PRK.Client"], capture_output=True).returncode == 0


def providers():
    found = {}
    for manifest in glob.glob(os.path.join(ADDONS, "ndgui*", "package.xml")):
        text = open(manifest, encoding="utf-8").read()
        pid = re.search(r'<Package id="([^"]+)"', text)
        for role in re.findall(r'<Provides role="([^"]+)"', text):
            found[role] = pid.group(1)
    return found


def key(role):
    assert role.startswith("prk.")
    return "UiPackageProvider_" + role[4:].replace("-", "_")


def main():
    reset = "--reset" in sys.argv
    if client_running():
        raise SystemExit("PRK.Client.exe is running. Quit the game first (it rewrites prefs on exit).")
    if not os.path.exists(PREFS):
        raise SystemExit(f"No client prefs at {PREFS}. Start the client once (or set NDGUI_PREFS), then re-run.")
    xml = open(PREFS, encoding="utf-8").read()
    backup = PREFS + time.strftime(".ndgui-backup-%Y%m%d-%H%M%S")
    shutil.copy2(PREFS, backup)
    chosen = providers()
    for role, pid in sorted(chosen.items()):
        k = key(role)
        xml = re.sub(r'\s*<Value name="%s" value="[^"]*" />' % re.escape(k), "", xml)
        if not reset:
            line = '    <Value name="%s" value="&quot;%s&quot;" />' % (k, pid)
            xml = xml.replace("<Root>", "<Root>\n" + line, 1)
        print(("reset  " if reset else "select ") + f"{role:24s} {'' if reset else pid}")
    open(PREFS, "w", encoding="utf-8", newline="\n").write(xml)
    print(f"\n{len(chosen)} roles. Backup: {backup}")


if __name__ == "__main__":
    main()
