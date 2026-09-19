#!/usr/bin/env python3
"""Report theme templates and post-hooks that didn't land.

Noctalia only rewrites a template output when its content changed, so staleness
can't be read from mtimes. Instead this re-applies the templates (idempotent,
and the theme-reload hook self-guards on an unchanged palette) and reports every
output that changed as a result -- those were stale. Hook-produced files live
outside the template system, so they're checked against the palette by content.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state"))

SETTINGS = CONFIG / "noctalia/settings.toml"
BUILTIN_TOML = Path("/usr/share/noctalia/assets/templates/builtin.toml")
BUILTIN_DIR = BUILTIN_TOML.parent
COMMUNITY_DIR = STATE / "noctalia/community-templates"
PALETTE = CACHE / "noctalia/bitwarden-colors.json"

# Files written by post-hooks, not by the template engine: the only way to catch
# a hook that failed silently. Each entry names palette keys that must appear.
DOWNSTREAM = [
    ("spotify", Path("/opt/spotify/Apps/xpui/colors.css"), ["primary", "surface"]),
    ("steam", HOME / ".steam/steam/steamui/skins/Material-Theme/css/main/colors/matugen.css",
     ["surface", "on_surface"]),
    ("prismlauncher", DATA / "PrismLauncher/themes/Matugen/theme.json", ["primary", "surface"]),
    ("brave", DATA / "noctalia/brave-theme/manifest.json", ["surface"]),
    ("bitwarden", CACHE / "noctalia/bitwarden-colors.json", ["primary", "surface"]),
    ("gtk3", CONFIG / "gtk-3.0/noctalia.css", ["primary", "surface"]),
    ("gtk4", CONFIG / "gtk-4.0/noctalia.css", ["primary", "surface"]),
    # these hooks INLINE the palette into the app's own config rather than
    # referencing a theme file, so the colours really are the hook's artifact.
    # fastfetch only gets "primary" checked: its hook nudges light channels, so
    # other entries can legitimately come out altered.
    ("fastfetch", CONFIG / "fastfetch/config.jsonc", ["primary"]),
    ("lazygit", CONFIG / "lazygit/config.yml", ["primary", "on_surface"]),
    ("starship", CONFIG / "starship.toml", ["primary", "surface"]),
]

# Hooks whose job is wiring, not colour: they point an app at the noctalia theme.
# Nothing here changes per palette, so a colour check would be meaningless -- the
# failure mode is the app losing the reference entirely.
WIRING = [
    ("bat", CONFIG / "bat/config", "--theme=noctalia"),
    ("micro", CONFIG / "micro/settings.json", "noctalia"),
    ("libreoffice", STATE / "noctalia/community-templates/libreoffice/build/noctalia-theme.oxt", None),
]

UNITS = [
    "wallpaperengine-theme-sync.service",
    "noctalia-state-sync.path",
    "darkreader-colors-server.service",
    "save-package-list.path",
    "noctalia-patched-rebuild.path",
]

HEX = re.compile(r"#([0-9a-fA-F]{6})\b")
RGB_FUNC = re.compile(r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})")
RGB_LIST = re.compile(r"\[\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\]")


class Report:
    def __init__(self):
        self.problems = []
        self.lines = []

    def ok(self, what, detail=""):
        self.lines.append(f"  ok    {what}{'  ' + detail if detail else ''}")

    def skip(self, what, detail=""):
        self.lines.append(f"  skip  {what}{'  ' + detail if detail else ''}")

    def bad(self, what, detail=""):
        self.lines.append(f"  FAIL  {what}{'  ' + detail if detail else ''}")
        self.problems.append(f"{what}{': ' + detail if detail else ''}")


XDG = {
    "XDG_CONFIG_HOME": CONFIG,
    "XDG_CACHE_HOME": CACHE,
    "XDG_DATA_HOME": DATA,
    "XDG_STATE_HOME": STATE,
    "HOME": HOME,
}


def expand(value):
    """Templates use $XDG_* even when the vars are unset in this process."""
    text = str(value)
    for name, target in XDG.items():
        text = text.replace(f"${{{name}}}", str(target)).replace(f"${name}", str(target))
    return Path(os.path.expandvars(os.path.expanduser(text)))


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def load_toml(path):
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError):
        return None


def dynamic_output(command, config_dir):
    """output_path_dynamic: a shell command whose stdout is the real path."""
    rendered = command.replace("{{ config_dir }}", str(config_dir)).replace("{{config_dir}}", str(config_dir))
    result = run(["bash", "-lc", rendered])
    if result.returncode != 0:
        return []
    return [expand(line) for line in result.stdout.split("\n") if line.strip()]


def outputs_of(entry, config_dir):
    raw = entry.get("output_path")
    if raw:
        return [expand(p) for p in (raw if isinstance(raw, list) else [raw])]
    if entry.get("output_path_dynamic"):
        return dynamic_output(entry["output_path_dynamic"], config_dir)
    return []


def collect_templates(settings):
    """Every enabled template as (label, [output paths], requires_path or None)."""
    tpl = settings.get("theme", {}).get("templates", {})
    found = []

    builtin = load_toml(BUILTIN_TOML) or {}
    for tid in tpl.get("builtin_ids", []):
        entry = builtin.get("templates", {}).get(tid)
        if entry is None:
            found.append((f"builtin:{tid}", [], None, "not defined in builtin.toml"))
            continue
        found.append((f"builtin:{tid}", outputs_of(entry, BUILTIN_DIR), entry.get("requires_path"), None))

    for cid in tpl.get("community_ids", []):
        cdir = COMMUNITY_DIR / cid
        manifest = load_toml(cdir / "template.toml")
        if manifest is None:
            found.append((f"community:{cid}", [], None, "template.toml missing or unreadable"))
            continue
        for name, entry in manifest.get("templates", {}).items():
            found.append((f"community:{name}", outputs_of(entry, cdir), entry.get("requires_path"), None))

    for name, entry in tpl.get("user", {}).items():
        found.append((f"user:{name}", outputs_of(entry, CONFIG / "noctalia"), entry.get("requires_path"), None))

    return found


def digest(path):
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def settle(paths, min_wait=8.0, quiet_for=3.0, timeout=90.0):
    """templates-apply returns `ok` a few seconds before it starts writing, so
    hold for min_wait first -- otherwise 'nothing changed yet' reads as done."""
    start = time.monotonic()
    snapshot = {p: digest(p) for p in paths}
    stable_since = start
    while time.monotonic() - start < timeout:
        time.sleep(0.5)
        current = {p: digest(p) for p in paths}
        if current != snapshot:
            snapshot = current
            stable_since = time.monotonic()
            continue
        if time.monotonic() - start >= min_wait and time.monotonic() - stable_since >= quiet_for:
            break
    return snapshot


def colors_in(path):
    """Every colour in a file, as RGB triples -- hex, rgb(), and [r, g, b] all count."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return set()
    found = {tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in HEX.findall(text)}
    for pattern in (RGB_FUNC, RGB_LIST):
        found |= {tuple(int(v) for v in m) for m in pattern.findall(text)}
    return found


def palette():
    try:
        raw = json.loads(PALETTE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    out = {}
    for key, value in raw.items():
        m = HEX.fullmatch(str(value).strip())
        if m:
            h = m.group(1)
            out[key] = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    return out


def check_noctalia(report):
    if run(["pgrep", "-u", str(os.getuid()), "-x", "noctalia"]).returncode != 0:
        report.bad("noctalia", "not running -- nothing else here is meaningful")
        return False
    report.ok("noctalia", "running")
    return True


def check_templates(report, settings):
    templates = collect_templates(settings)
    watched = {p for _, paths, _, _ in templates for p in paths}
    before = {p: digest(p) for p in watched}

    result = run(["noctalia", "msg", "templates-apply"])
    if result.returncode != 0 or result.stdout.strip() != "ok":
        report.bad("templates-apply", (result.stdout + result.stderr).strip()[:120] or "no response")
        return
    after = settle(watched)

    for label, paths, requires, problem in templates:
        if problem:
            report.bad(label, problem)
            continue
        if requires and not expand(requires).exists():
            report.skip(label, f"{requires} not installed")
            continue
        if not paths:
            report.bad(label, "no output path resolved")
            continue
        for path in paths:
            if not path.is_absolute():
                report.skip(label, f"hook-managed target ({path})")
            elif after[path] is None:
                # noctalia creates the theme dir itself, so a missing parent
                # means the target app was never installed here.
                if path.parent.is_dir():
                    report.bad(label, f"never rendered: {path}")
                else:
                    report.skip(label, f"{path.parent} not present")
            elif before[path] != after[path]:
                report.bad(label, f"was stale, re-rendered now: {path}")
            else:
                report.ok(label, str(path))


def check_downstream(report, colors):
    if not colors:
        report.bad("palette", f"cannot read {PALETTE}")
        return
    for name, path, keys in DOWNSTREAM:
        if not path.exists():
            report.skip(f"hook:{name}", f"{path} not present")
            continue
        present = colors_in(path)
        missing = [k for k in keys if k in colors and colors[k] not in present]
        if missing:
            report.bad(f"hook:{name}", f"{path} is missing {', '.join(missing)} -- hook did not run")
        else:
            report.ok(f"hook:{name}", str(path))


def check_hook_log(report, since):
    """Noctalia logs failing post_hooks as [WRN] [hook_runner] with the command.
    Cheap, generic, and catches hooks whose damage isn't visible in any file."""
    log = CACHE / "noctalia/noctalia.log"
    try:
        lines = log.read_text(errors="replace").splitlines()
    except OSError:
        report.skip("hooks:log", f"{log} not readable")
        return
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(since))
    recent = [l for l in lines if "[hook_runner]" in l and "failed" in l and l[:19] >= stamp]
    if recent:
        for line in recent[-4:]:
            report.bad("hooks:log", line.split("[hook_runner]", 1)[-1].strip()[:160])
    else:
        report.ok("hooks:log", "no hook failures during this run")


def check_wiring(report):
    for name, path, needle in WIRING:
        if not path.exists():
            report.bad(f"wiring:{name}", f"{path} is missing -- the hook never wired it up")
            continue
        if needle is None:
            report.ok(f"wiring:{name}", str(path))
            continue
        try:
            if needle in path.read_text(errors="replace"):
                report.ok(f"wiring:{name}", str(path))
            else:
                report.bad(f"wiring:{name}", f"{path} no longer references {needle!r}")
        except OSError as e:
            report.bad(f"wiring:{name}", f"{path}: {e}")


def check_units(report):
    for unit in UNITS:
        state = run(["systemctl", "--user", "is-active", unit]).stdout.strip()
        if state in ("active", "listening", "waiting"):
            report.ok(f"unit:{unit}", state)
        else:
            failed = run(["systemctl", "--user", "is-failed", unit]).stdout.strip()
            report.bad(f"unit:{unit}", failed if failed == "failed" else state or "unknown")


def check_wallpaper(report):
    """Surface-size drift isn't visible over IPC, so this only covers what is."""
    procs = run(["pgrep", "-u", str(os.getuid()), "-af", "linux-wallpaperengine --screen-root"]).stdout
    if not procs.strip():
        report.bad("wallpaper", "linux-wallpaperengine is not running")
        return
    report.ok("wallpaper", "engine running")

    running_ids = set(re.findall(r"--bg\s+(\d+)", procs))
    try:
        synced = (CACHE / "wallpaperengine-theme-sync/last-id").read_text().strip()
    except OSError:
        synced = ""
    if not synced:
        report.bad("wallpaper:theme", "theme-sync has no wallpaper recorded")
    elif synced not in running_ids:
        report.bad("wallpaper:theme",
                   f"palette came from {synced}, engine is showing {', '.join(sorted(running_ids)) or 'nothing'}")
    else:
        report.ok("wallpaper:theme", f"palette matches wallpaper {synced}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notify", action="store_true", help="send a desktop notification on failure")
    parser.add_argument("--quiet", action="store_true", help="print only failures")
    args = parser.parse_args()

    report = Report()
    started = time.time()
    if check_noctalia(report):
        settings = load_toml(SETTINGS)
        if settings is None:
            report.bad("settings", f"cannot read {SETTINGS}")
        else:
            check_templates(report, settings)
            check_downstream(report, palette())
            check_wiring(report)
            check_hook_log(report, started)
    check_units(report)
    check_wallpaper(report)

    if not args.quiet:
        print("theme healthcheck")
        print("\n".join(report.lines))
    if report.problems:
        print(f"\n{len(report.problems)} problem(s):")
        for problem in report.problems:
            print(f"  - {problem}")
        if args.notify:
            subprocess.run(
                ["notify-send", "-u", "critical", "-a", "Theme",
                 f"{len(report.problems)} theme problem(s)", "\n".join(report.problems[:6])],
                capture_output=True)
        return 1
    if not args.quiet:
        print("\nall good")
    return 0


if __name__ == "__main__":
    sys.exit(main())
