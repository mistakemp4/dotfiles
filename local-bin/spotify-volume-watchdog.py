#!/usr/bin/env python3
"""Keep Spotify's PipeWire stream at the volume you last chose.

Spotify's stream can come up with no per-channel volumes (plays at 100%, while
pactl shows it as 0%), or snap to exactly 100%. Both get reset to the saved
level. Volumes are read from PipeWire (pw-dump/wpctl), not pactl, which can't
see this stream's aux channels. pactl subscribe is only used as the event feed.
"""
import json
import re
import subprocess
from pathlib import Path

STATE = Path.home() / ".local/state/spotify-volume-watchdog/level"
DEFAULT_LEVEL = 0.5


def load_level():
    try:
        return float(STATE.read_text())
    except (OSError, ValueError):
        return DEFAULT_LEVEL


def save_level(level):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(f"{level:.2f}\n")


def spotify_nodes():
    """(node id, channelVolumes) for each Spotify playback stream."""
    out = subprocess.run(["pw-dump"], capture_output=True, text=True).stdout
    nodes = []
    for obj in json.loads(out or "[]"):
        # the Spotify *client* object carries the same props but has no volume
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        info = obj.get("info") or {}
        props = info.get("props") or {}
        if props.get("application.name") != "Spotify" or props.get("media.class") != "Stream/Output/Audio":
            continue
        params = (info.get("params") or {}).get("Props") or [{}]
        nodes.append((obj["id"], params[0].get("channelVolumes")))
    return nodes


def get_volume(node):
    out = subprocess.run(["wpctl", "get-volume", str(node)], capture_output=True, text=True).stdout
    match = re.search(r"Volume: ([0-9.]+)", out)
    return float(match.group(1)) if match else None


def set_volume(node, level):
    subprocess.run(["wpctl", "set-volume", str(node), f"{level:.2f}"], check=False)


def check(level):
    """Fix any bad Spotify stream; returns the (possibly updated) saved level."""
    for node, channel_volumes in spotify_nodes():
        if not channel_volumes:
            print(f"node {node} has no channel volumes (plays at 100%), setting {level:.2f}", flush=True)
            set_volume(node, level)
            continue
        vol = get_volume(node)
        if vol is None:
            continue
        if abs(vol - 1.0) < 0.005 and level < 0.995:
            print(f"node {node} snapped to 100%, restoring {level:.2f}", flush=True)
            set_volume(node, level)
        elif abs(vol - level) >= 0.005:
            level = vol
            save_level(level)
    return level


def main():
    level = check(load_level())
    events = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE, text=True)
    for line in events.stdout:
        if "on sink-input" in line:
            level = check(level)
    # pactl exiting (pipewire restart) ends the service; systemd restarts it
    raise SystemExit(events.wait() or 1)


if __name__ == "__main__":
    main()
