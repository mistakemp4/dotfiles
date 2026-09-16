#!/usr/bin/env python3
"""Restart Spotify and Brave so they pick up a new Noctalia theme.

Both only load their theme at startup. For each running app: wait for its
template hook to finish, quit it cleanly, relaunch it through niri (so it isn't
tied to the sync service), then restore playback / tabs.

usage: restart-themed-apps.py <since-epoch> [spotify] [brave]
"""
import contextlib
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
LOCK = HOME / ".cache/wallpaperengine-theme-sync/restart.lock"
SPOTIFY_CSS = Path("/opt/spotify/Apps/xpui/colors.css")
BRAVE_THEME = HOME / ".local/share/noctalia/brave-theme"
BRAVE_PREFS = HOME / ".config/BraveSoftware/Brave-Browser/Default/Preferences"
BRAVE_APPLY = HOME / ".local/state/noctalia/community-templates/brave/apply.sh"
# same as niri's Mod+B bind
DARKREADER = HOME / "src/darkreader-noctalia/build/release/chrome-mv3"
BRAVE_CMD = ["brave", f"--load-extension={BRAVE_THEME},{DARKREADER}"]
PLAYER_BUS = ["org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2"]
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
UID = str(os.getuid())


def log(msg):
    print(f"restart-themed-apps: {msg}", flush=True)


def wait_until(check, timeout, step=0.5):
    deadline = time.monotonic() + timeout
    while not check():
        if time.monotonic() >= deadline:
            return False
        time.sleep(step)
    return True


def running(name):
    return subprocess.run(["pgrep", "-u", UID, "-x", name], capture_output=True).returncode == 0


def main_pid(name):
    """PID of the app's main process: the one without --type=.

    Chromium apps rewrite /proc/<pid>/cmdline into one space-joined string, so
    split on spaces as well as NULs.
    """
    out = subprocess.run(["pgrep", "-u", UID, "-x", name], capture_output=True, text=True).stdout
    for pid in out.split():
        try:
            tokens = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").split()
        except OSError:
            continue
        if tokens and not any(t.startswith(b"--type=") for t in tokens):
            return int(pid)
    return None


def rendered_since(path, since):
    def check():
        try:
            return path.stat().st_mtime >= since
        except OSError:
            return False
    return check


def launch(name, args):
    # via niri so the app gets its own scope instead of living in this service's cgroup.
    # niri doesn't report exec failures, so confirm the process actually appears
    subprocess.run(["niri", "msg", "action", "spawn", "--", *args], check=True)
    if not wait_until(lambda: main_pid(name) is not None, 20):
        raise RuntimeError(f"{args[0]} didn't start")


def player_get(prop):
    r = subprocess.run(["busctl", "--user", "--json=short", "get-property", *PLAYER_BUS, PLAYER_IFACE, prop],
                       capture_output=True, text=True)
    return json.loads(r.stdout)["data"] if r.returncode == 0 else None


def player_call(method, *args, interface=PLAYER_IFACE):
    subprocess.run(["busctl", "--user", "call", *PLAYER_BUS, interface, method, *map(str, args)],
                   capture_output=True, check=False)


def current_track():
    meta = player_get("Metadata") or {}
    return (meta.get("mpris:trackid") or {}).get("data")


def restart_spotify(since):
    pid = main_pid("spotify")
    if pid is None:
        return
    if not wait_until(rendered_since(SPOTIFY_CSS, since), 60):
        log("spotify colors weren't re-applied, leaving spotify alone")
        return
    playing = player_get("PlaybackStatus") == "Playing"
    track, position = current_track(), player_get("Position")

    # spotify ignores SIGTERM but quits cleanly via MPRIS (Quit is on the root interface)
    player_call("Quit", interface="org.mpris.MediaPlayer2")
    if not wait_until(lambda: main_pid("spotify") is None, 15):
        log("spotify didn't quit, killing it")
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, signal.SIGKILL)
        wait_until(lambda: main_pid("spotify") is None, 5)
    launch("spotify", ["spotify"])
    log("spotify restarted")

    if not playing:
        return
    if not wait_until(lambda: current_track() is not None, 30):
        log("spotify came back without a track, not resuming")
        return
    player_call("Play")
    if track and position and current_track() == track:
        player_call("SetPosition", "ox", track, position)
    log(f"spotify resumed {track} at {(position or 0) // 1_000_000}s")


def enable_tab_restore():
    """Set 'Continue where you left off' so restarts keep open tabs. Brave must be stopped."""
    data = json.loads(BRAVE_PREFS.read_text())
    session = data.setdefault("session", {})
    if session.get("restore_on_startup") == 1:
        return
    session["restore_on_startup"] = 1
    tmp = BRAVE_PREFS.with_name("Preferences.restart-tmp")
    tmp.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False))
    os.chmod(tmp, BRAVE_PREFS.stat().st_mode & 0o7777)
    tmp.replace(BRAVE_PREFS)
    log("enabled brave tab restore")


def restart_brave(since):
    pid = main_pid("brave")
    if pid is None:
        return
    if not wait_until(rendered_since(BRAVE_THEME / "manifest.json", since), 60):
        log("brave theme wasn't re-applied, leaving brave alone")
        return

    with contextlib.suppress(ProcessLookupError):
        os.kill(pid, signal.SIGTERM)  # clean shutdown, session saved
    if not wait_until(lambda: main_pid("brave") is None, 30):
        log("brave didn't quit within 30s, leaving it running")  # never force-kill: open tabs
        return
    if not wait_until(lambda: not running("brave"), 10):
        log("brave helpers still running after 10s, continuing")
    enable_tab_restore()
    # with brave stopped, the hook can also write color_scheme + accent into Preferences
    mode = subprocess.run(["noctalia", "msg", "theme-mode-get"], capture_output=True, text=True).stdout.strip()
    subprocess.run(["bash", str(BRAVE_APPLY), mode if mode in ("dark", "light") else "dark"],
                   capture_output=True, check=False)
    launch("brave", BRAVE_CMD)
    log("brave restarted")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    since = float(sys.argv[1])
    apps = sys.argv[2:] or ["spotify", "brave"]
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # one restart round at a time
        for name, restart in (("spotify", restart_spotify), ("brave", restart_brave)):
            if name not in apps:
                continue
            try:
                restart(since)
            except Exception as e:  # one app failing shouldn't block the other
                log(f"{name} restart failed: {e}")


if __name__ == "__main__":
    main()
