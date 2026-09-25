#!/usr/bin/env python3
import contextlib
import fcntl
import json
import os
import signal
import subprocess
import time
from pathlib import Path

HOME = Path.home()
LOCK = HOME / ".cache/theme-reload/restart.lock"
SIGNATURE = HOME / ".cache/noctalia/theme-reload.txt"
LAST_SIGNATURE = HOME / ".local/state/theme-reload/last"
SPOTIFY_CSS = Path("/opt/spotify/Apps/xpui/colors.css")
BRAVE_THEME = HOME / ".local/share/noctalia/brave-theme"
BRAVE_PREFS = HOME / ".config/BraveSoftware/Brave-Browser/Default/Preferences"
BRAVE_APPLY = HOME / ".local/state/noctalia/community-templates/brave/apply.sh"
DARKREADER = HOME / "src/darkreader-noctalia/build/release/chrome-mv3"
BRAVE_CMD = ["brave", f"--load-extension={BRAVE_THEME},{DARKREADER}"]
GTK3_CSS = HOME / ".config/gtk-3.0/noctalia.css"
PRISM_THEME = HOME / ".local/share/PrismLauncher/themes/Matugen/theme.json"
PRISM_ID = "org.prismlauncher.PrismLauncher"
STEAM_CSS = HOME / ".steam/steam/steamui/skins/Material-Theme/css/main/colors/matugen.css"
LIBREOFFICE_APPLY = HOME / ".local/state/noctalia/community-templates/libreoffice/apply.sh"
LIBREOFFICE_LOCK = HOME / ".cache/theme-reload/libreoffice.lock"
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
    out = subprocess.run(["pgrep", "-u", UID, "-x", name], capture_output=True, text=True).stdout
    for pid in out.split():
        try:
            # chromium rewrites cmdline into one space-joined string
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

def launch(name, args, timeout=20):
    subprocess.run(["niri", "msg", "action", "spawn", "--", *args], check=True)
    if not wait_until(lambda: main_pid(name) is not None, timeout):
        raise RuntimeError(f"{args[0]} didn't start")

def niri_windows(app_id):
    out = subprocess.run(["niri", "msg", "-j", "windows"], capture_output=True, text=True).stdout
    return [w for w in json.loads(out or "[]") if w.get("app_id") == app_id]

def close_windows(windows):
    for w in windows:
        subprocess.run(["niri", "msg", "action", "close-window", "--id", str(w["id"])], capture_output=True)

def descendants(pid):
    children = {}
    for stat in Path("/proc").glob("[0-9]*/stat"):
        with contextlib.suppress(OSError, ValueError, IndexError):
            ppid = int(stat.read_text().rsplit(")", 1)[1].split()[1])
            children.setdefault(ppid, []).append(int(stat.parent.name))
    found, todo = [], [pid]
    while todo:
        kids = children.get(todo.pop(), [])
        found += kids
        todo += kids
    return found

def xfconf(prop, *args):
    return subprocess.run(["xfconf-query", "-c", "thunar", "-p", prop, *args], capture_output=True, text=True)

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

    # spotify ignores SIGTERM; MPRIS Quit is on the root interface
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
        os.kill(pid, signal.SIGTERM)
    if not wait_until(lambda: main_pid("brave") is None, 30):
        log("brave didn't quit within 30s, leaving it running")  # never force-kill: open tabs
        return
    if not wait_until(lambda: not running("brave"), 10):
        log("brave helpers still running after 10s, continuing")
    enable_tab_restore()
    mode = subprocess.run(["noctalia", "msg", "theme-mode-get"], capture_output=True, text=True).stdout.strip()
    subprocess.run(["bash", str(BRAVE_APPLY), mode if mode in ("dark", "light") else "dark"],
                   capture_output=True, check=False)
    launch("brave", BRAVE_CMD)
    log("brave restarted")

def restart_thunar(since, skipped):
    if not running("thunar"):
        return
    windows = niri_windows("thunar")
    main = [w for w in windows if (w.get("title") or "").endswith(" - Thunar")]
    if len(main) != len(windows) or len(main) > 1:
        skipped.append("Thunar (a dialog or several windows are open)")
        return
    if not wait_until(rendered_since(GTK3_CSS, since), 60):
        log("gtk colors weren't re-applied, leaving thunar alone")
        return
    daemon = subprocess.run(["pgrep", "-u", UID, "-f", "thunar --daemon"], capture_output=True).returncode == 0
    prev = xfconf("/last-restore-tabs")
    xfconf("/last-restore-tabs", "-n", "-t", "bool", "-s", "true")
    try:
        close_windows(main)
        wait_until(lambda: not niri_windows("thunar"), 10)
        subprocess.run(["thunar", "-q"], capture_output=True)
        if not wait_until(lambda: not running("thunar"), 10):
            skipped.append("Thunar (didn't quit)")
            return
        if main:
            launch("thunar", ["thunar"])
            wait_until(lambda: niri_windows("thunar"), 10)
        elif daemon:
            launch("thunar", ["thunar", "--daemon"])
        log("thunar restarted")
    finally:
        if prev.returncode == 0:
            xfconf("/last-restore-tabs", "-s", prev.stdout.strip())
        else:
            xfconf("/last-restore-tabs", "-r")

def restart_prism(since, skipped):
    pid = main_pid("prismlauncher")
    if pid is None:
        return
    if descendants(pid):
        skipped.append("PrismLauncher (a game is running)")
        return
    if not wait_until(rendered_since(PRISM_THEME, since), 60):
        log("prism theme wasn't re-applied, leaving prism alone")
        return
    close_windows(niri_windows(PRISM_ID))
    if not wait_until(lambda: main_pid("prismlauncher") is None, 15):
        skipped.append("PrismLauncher (didn't quit)")
        return
    launch("prismlauncher", ["prismlauncher"])
    log("prism restarted")

def restart_steam(since, skipped):
    if not running("steam"):
        return
    if subprocess.run(["pgrep", "-u", UID, "-f", "SteamLaunch AppId="], capture_output=True).returncode == 0:
        skipped.append("Steam (a game is running)")
        return
    if not wait_until(rendered_since(STEAM_CSS, since), 60):
        log("steam colors weren't re-applied, leaving steam alone")
        return
    had_window = bool(niri_windows("steam"))
    subprocess.run(["steam", "-shutdown"], capture_output=True, timeout=60)
    if not wait_until(lambda: not running("steam"), 90, step=1):
        skipped.append("Steam (didn't shut down)")
        return
    launch("steam", ["steam"] if had_window else ["steam", "-silent"], timeout=60)
    log("steam restarted")

def update_libreoffice(skipped):
    if not running("soffice.bin"):
        return
    skipped.append("LibreOffice (updates once you close it)")
    subprocess.Popen(["setsid", "-f", "flock", "-n", str(LIBREOFFICE_LOCK), "bash", "-c",
                      'while pgrep -u "$UID" -x soffice.bin >/dev/null; do sleep 5; done; bash "$1"',
                      "_", str(LIBREOFFICE_APPLY)])

def palette_changed():
    current = SIGNATURE.read_text()
    try:
        last = LAST_SIGNATURE.read_text()
    except FileNotFoundError:
        last = None
    LAST_SIGNATURE.parent.mkdir(parents=True, exist_ok=True)
    LAST_SIGNATURE.write_text(current)
    return last is not None and last != current

def main():
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not palette_changed():
            return
        since = SIGNATURE.stat().st_mtime - 30
        skipped = []
        for name, restart in (("spotify", restart_spotify), ("brave", restart_brave)):
            try:
                restart(since)
            except Exception as e:
                log(f"{name} restart failed: {e}")
        for name, restart in (("thunar", restart_thunar), ("prism", restart_prism), ("steam", restart_steam)):
            try:
                restart(since, skipped)
            except Exception as e:
                log(f"{name} restart failed: {e}")
                skipped.append(f"{name} (restart failed)")
        update_libreoffice(skipped)
        if skipped:
            log("skipped: " + ", ".join(skipped))
            subprocess.run(["notify-send", "-a", "Theme", "Some apps still have the old colors", "\n".join(skipped)],
                           capture_output=True)

if __name__ == "__main__":
    main()
