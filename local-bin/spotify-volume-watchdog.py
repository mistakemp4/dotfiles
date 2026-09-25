#!/usr/bin/env python3
import json
import re
import subprocess
import time
from pathlib import Path

STATE = Path.home() / ".local/state/spotify-volume-watchdog/level"
DEFAULT_LEVEL = 0.5
# Anything at/above this is Spotify resetting itself, never a deliberate choice.
# To run louder than this on purpose, write the value into STATE by hand.
SNAP_MIN = 0.90
# A real hand on the slider persists; a Spotify reset does not.
CONFIRM_DELAY = 0.3

def load_level():
    try:
        return float(STATE.read_text())
    except (OSError, ValueError):
        return DEFAULT_LEVEL

def save_level(level):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(f"{level:.2f}\n")

def spotify_nodes():
    out = subprocess.run(["pw-dump"], capture_output=True, text=True).stdout
    nodes = []
    for obj in json.loads(out or "[]"):
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
    for node, channel_volumes in spotify_nodes():
        if not channel_volumes:
            print(f"node {node} has no channel volumes (plays at 100%), setting {level:.2f}", flush=True)
            set_volume(node, level)
            continue
        vol = get_volume(node)
        if vol is None:
            continue
        if vol >= SNAP_MIN and level < SNAP_MIN:
            print(f"node {node} snapped to {vol:.2f}, restoring {level:.2f}", flush=True)
            set_volume(node, level)
        elif abs(vol - level) >= 0.005:
            time.sleep(CONFIRM_DELAY)
            settled = get_volume(node)
            if settled is None or abs(settled - vol) >= 0.005:
                continue
            level = settled
            save_level(level)
            print(f"node {node} set to {level:.2f} by hand, adopting", flush=True)
    return level

def main():
    level = check(load_level())
    events = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE, text=True)
    for line in events.stdout:
        if "on sink-input" in line:
            level = check(level)
    raise SystemExit(events.wait() or 1)

if __name__ == "__main__":
    main()
