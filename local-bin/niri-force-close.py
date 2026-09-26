#!/usr/bin/env python3
"""Force-kill the focused niri window's process (Mod+Shift+Q)."""
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

GRACE = 2.0


def niri_window(win_id):
    if win_id is None:
        out = subprocess.run(["niri", "msg", "--json", "focused-window"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)
    out = subprocess.run(["niri", "msg", "--json", "windows"],
                         capture_output=True, text=True, check=True).stdout
    return next((w for w in json.loads(out) if w["id"] == win_id), None)


def procs():
    """pid -> (ppid, comm, cmdline)"""
    table = {}
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            stat = (p / "stat").read_text()
            cmd = (p / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            continue
        comm = stat[stat.index("(") + 1:stat.rindex(")")]
        ppid = int(stat[stat.rindex(")") + 2:].split()[1])
        table[int(p.name)] = (ppid, comm, cmd)
    return table


def descendants(table, root):
    kids = {}
    for pid, (ppid, _, _) in table.items():
        kids.setdefault(ppid, []).append(pid)
    out, stack = [], [root]
    while stack:
        for c in kids.get(stack.pop(), []):
            out.append(c)
            stack.append(c)
    return out


def steam_game_pids(table, appid):
    pat = re.compile(rf"\bSteamLaunch AppId={appid}\b")
    reapers = [pid for pid, (_, comm, cmd) in table.items()
               if comm == "reaper" and pat.search(cmd)]
    return [p for r in reapers for p in descendants(table, r)]


def x11_pid(app_id, title):
    from Xlib import X, display

    d = display.Display()
    net_pid = d.intern_atom("_NET_WM_PID")
    net_name = d.intern_atom("_NET_WM_NAME")
    utf8 = d.intern_atom("UTF8_STRING")
    matches = []

    def walk(win):
        try:
            cls = win.get_wm_class() or ()
            if app_id in cls:
                prop = win.get_full_property(net_name, utf8)
                name = prop.value.decode(errors="replace") if prop else win.get_wm_name()
                pid = win.get_full_property(net_pid, X.AnyPropertyType)
                if pid:
                    matches.append((name == title, int(pid.value[0])))
            for c in win.query_tree().children:
                walk(c)
        except Exception:
            pass

    walk(d.screen().root)
    exact = {pid for ok, pid in matches if ok}
    loose = {pid for _, pid in matches}
    pids = exact or loose
    return pids.pop() if len(pids) == 1 else None


def terminate(pids):
    for p in pids:
        try:
            os.kill(p, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + GRACE
    while time.monotonic() < deadline and any(Path(f"/proc/{p}").exists() for p in pids):
        time.sleep(0.1)
    for p in pids:
        try:
            os.kill(p, signal.SIGKILL)
        except ProcessLookupError:
            pass


def notify(msg):
    print(msg, file=sys.stderr)
    subprocess.run(["notify-send", "-a", "niri", "Force close", msg], check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--window", type=int, help="niri window id (default: focused)")
    args = ap.parse_args()

    w = niri_window(args.window)
    if not w:
        return notify("no window")
    table = procs()
    satellites = {pid for pid, (_, comm, _) in table.items() if comm.startswith("xwayland-sate")}
    protected = satellites | {1, os.getpid(), os.getppid()}
    protected |= {pid for pid, (_, comm, _) in table.items() if comm == "niri"}

    if w["pid"] not in satellites:
        targets = [w["pid"]]
    elif m := re.fullmatch(r"steam_app_(\d+)", w["app_id"] or ""):
        targets = steam_game_pids(table, m.group(1))
    else:
        pid = x11_pid(w["app_id"], w["title"])
        targets = [pid] if pid else []

    targets = [p for p in targets if p and p not in protected]
    if not targets:
        return notify(f"couldn't find process for {w['app_id']!r}")

    for p in targets:
        print(p, table.get(p, (0, "?", ""))[1])
    if args.dry_run:
        return

    terminate(targets)


if __name__ == "__main__":
    main()
