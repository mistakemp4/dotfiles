#!/usr/bin/env python3
"""Detect linux-wallpaperengine's surface shrinking into the top-left corner.

The engine occasionally ends up with an EGL window smaller than the output and
never corrects itself -- seen once at 2400x1268 on a 2560x1440 screen, pinned at
0,0, with niri's backdrop filling the remaining L-shape. The trigger was never
reproduced (vrr, scale and mode changes were all survived), so this detects the
end state instead of preventing it.

Detection: with an unobstructed desktop, a healthy screen has no strong straight
discontinuity in its bottom or right half -- only the bar and desktop widgets,
which sit near the top. A shrunken surface puts a hard full-width edge in the
bottom half and a hard full-height edge in the right half, where its buffer ends.
Thresholds are calibrated against a real broken/healthy screenshot pair; see
--selftest.

The check is skipped whenever a window is visible, because the wallpaper has to
actually be on screen to be measured. That makes this a periodic opportunistic
check, not a guarantee.
"""

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

# Calibrated on the 2026-09-17 broken/healthy pair (see --selftest):
#   broken  row 75.1 col 38.5      healthy fixture  row 18.6 col 22.5
#   healthy live 13.5/15.0
# The ROW score is the real discriminator. The COL score is NOT reliable on its
# own -- a healthy empty desktop was measured at col 74 on a different wallpaper,
# because the P5 art has hard vertical edges. Detection requires BOTH, which is
# what keeps art from tripping it. A false positive costs one engine restart.
ROW_THRESHOLD = 50.0
COL_THRESHOLD = 30.0
ENGINE_MATCH = "linux-wallpaperengine --screen-root"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def visible_windows():
    """Windows on the active workspace.

    Don't use layout.tile_pos_in_workspace_view for this -- it is null even for
    windows that are plainly on screen, which made an earlier version measure an
    obstructed desktop and report a false positive.
    """
    try:
        spaces = json.loads(run(["niri", "msg", "-j", "workspaces"]).stdout)
        wins = json.loads(run(["niri", "msg", "-j", "windows"]).stdout)
    except json.JSONDecodeError:
        return None
    active = {s["id"] for s in spaces if s.get("is_active")}
    return [w for w in wins if w.get("workspace_id") in active]


def output_info():
    out = run(["niri", "msg", "-j", "outputs"]).stdout
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return None, None
    for name, info in data.items():
        mode = (info.get("modes") or [None] * (info.get("current_mode", -1) + 1))[info.get("current_mode", 0)]
        if mode:
            return name, (mode["width"], mode["height"])
    return None, None


def edge_scores(png):
    """(strongest row edge in the bottom half, strongest col edge in the right half)."""
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        sys.exit("needs python-pillow and python-numpy")
    a = np.asarray(Image.open(png).convert("RGB")).astype(int)
    h, w, _ = a.shape
    rows = np.abs(a[1:, :, :] - a[:-1, :, :]).mean(axis=(1, 2))
    cols = np.abs(a[:, 1:, :] - a[:, :-1, :]).mean(axis=(0, 2))
    # ignore a margin at the screen edge: window borders and the dock sit there
    # and an earlier version tripped on a window edge 10px from the bottom
    margin = 24
    r0, r1 = h // 2, h - margin
    c0, c1 = w // 2, w - margin
    ri = int(np.argmax(rows[r0:r1])) + r0
    ci = int(np.argmax(cols[c0:c1])) + c0
    return (float(rows[ri]), ri + 1), (float(cols[ci]), ci + 1), (w, h)


def verdict(png):
    (rscore, ry), (cscore, cx), (w, h) = edge_scores(png)
    broken = rscore >= ROW_THRESHOLD and cscore >= COL_THRESHOLD
    return broken, f"row edge {rscore:.1f}@y={ry}, col edge {cscore:.1f}@x={cx}, output {w}x{h}"


def restart_engine():
    procs = run(["pgrep", "-af", ENGINE_MATCH]).stdout.strip().splitlines()
    if not procs:
        return "engine not running; nothing to restart"
    cmd = procs[0].split(None, 1)[1].split()
    run(["pkill", "-f", ENGINE_MATCH])
    unit = "linux-wallpaperengine-watchdog"
    run(["systemctl", "--user", "reset-failed", f"{unit}.service"])
    r = run(["systemd-run", "--user", "--collect", f"--unit={unit}", *cmd])
    return "engine restarted" if r.returncode == 0 else f"restart failed: {r.stderr.strip()}"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--fix", action="store_true", help="restart the engine when a shrunken surface is found")
    p.add_argument("--selftest", nargs=2, metavar=("BROKEN_PNG", "HEALTHY_PNG"),
                   help="verify the thresholds against a known pair and exit")
    p.add_argument("--shot", type=Path, help="score this image instead of grabbing the screen")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args()

    if args.selftest:
        bad, good = args.selftest
        b_broken, b_why = verdict(bad)
        g_broken, g_why = verdict(good)
        print(f"broken fixture -> {'DETECTED' if b_broken else 'MISSED'}   ({b_why})")
        print(f"healthy fixture -> {'false alarm' if g_broken else 'clean'}   ({g_why})")
        return 0 if (b_broken and not g_broken) else 1

    if args.shot:
        broken, why = verdict(args.shot)
        print(f"{'SHRUNKEN SURFACE' if broken else 'looks fine'}  ({why})")
        return 1 if broken else 0

    if not run(["pgrep", "-f", ENGINE_MATCH]).stdout.strip():
        if not args.quiet:
            print("linux-wallpaperengine is not running")
        return 0

    wins = visible_windows()
    if wins is None:
        if not args.quiet:
            print("could not read niri windows; skipping")
        return 0
    if wins:
        if not args.quiet:
            print(f"skipped: {len(wins)} window(s) on screen, wallpaper not measurable")
        return 0

    name, _ = output_info()
    if not name:
        if not args.quiet:
            print("could not read the output; skipping")
        return 0

    with tempfile.NamedTemporaryFile(suffix=".png", delete=True) as tmp:
        if run(["grim", "-o", name, tmp.name]).returncode != 0:
            if not args.quiet:
                print("grim failed; skipping")
            return 0
        broken, why = verdict(tmp.name)

    if not broken:
        if not args.quiet:
            print(f"wallpaper covers the output ({why})")
        return 0

    msg = f"shrunken wallpaper surface detected ({why})"
    action = restart_engine() if args.fix else "not restarting (pass --fix)"
    print(f"{msg}; {action}")
    subprocess.run(["notify-send", "-a", "Wallpaper", "Wallpaper surface was stuck", action],
                   capture_output=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())
