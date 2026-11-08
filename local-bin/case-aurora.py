#!/usr/bin/env python3
# case rgb aurora in the noctalia colour, via the openrgb sdk server
import colorsys
import math
import random
import sys
import time
from pathlib import Path

from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

SRC = Path.home() / ".cache/noctalia/f75-lighting.txt"
DEVICE = "ASUS PRIME B850-PLUS WIFI"
ZONE = 2  # header 3: fans, case & cooler
LEDS = 150
FPS = 30
GAMMA = 2.2  # hex is sRGB, leds are linear

# look
SPEED = 1.0  # higher = faster drift
DIM = 0.25  # darkest part of the wave
HUE_SWAY = 0.05  # +- hue around the base colour (0.05 = 18°)
STAGGER = 1.2  # seconds clusters run ahead/behind each other
CLUSTER = 6  # leds per offset cluster

def stagger_offsets():
    # smooth fixed per-led offsets in -1..1, like the keyboard's offset rows
    rng = random.Random(7)
    knots = [rng.uniform(-1, 1) for _ in range(LEDS // CLUSTER + 2)]
    out = []
    for i in range(LEDS):
        k, f = divmod(i / CLUSTER, 1)
        f = (1 - math.cos(math.pi * f)) / 2
        out.append(knots[int(k)] * (1 - f) + knots[int(k) + 1] * f)
    return out

OFFSETS = stagger_offsets()

def read_colour():
    try:
        h = SRC.read_text().strip().splitlines()[0].strip().lstrip("#")
        return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except (OSError, IndexError, ValueError):
        return (0.4, 0.9, 0.45)

def connect():
    while True:
        try:
            c = OpenRGBClient(name="case-aurora")
            dev = next((d for d in c.devices if d.name == DEVICE), None)
            if dev:
                return c, dev
            c.disconnect()
        except (ConnectionError, OSError, TimeoutError):
            pass
        time.sleep(3)  # server still detecting

def frame(t, hsv):
    h0, s0, v0 = hsv
    out = []
    for i in range(LEDS):
        ti = t + STAGGER * OFFSETS[i]
        # two waves drifting opposite ways (in leds), never quite repeating
        w = 0.5 + 0.3 * math.sin(2 * math.pi * (i / 32 - 0.35 * ti)) \
                + 0.2 * math.sin(2 * math.pi * (i / 19 + 0.23 * ti + 1.7))
        level = DIM + (1 - DIM) * max(0.0, min(1.0, w))
        hue = (h0 + HUE_SWAY * math.sin(2 * math.pi * (i / 60 + 0.1 * ti))) % 1
        r, g, b = colorsys.hsv_to_rgb(hue, s0, v0 * level)
        out.append(RGBColor(*(round(c ** GAMMA * 255) for c in (r, g, b))))
    return out

def main():
    client, dev = connect()
    dev.set_mode("direct")
    zone = dev.zones[ZONE]
    if len(zone.leds) != LEDS:
        zone.resize(LEDS)
        dev.update()
    # whole-device updates; this aura ignores zone-only updates
    before = sum(len(z.leds) for z in dev.zones[:ZONE])
    after = len(dev.leds) - before - LEDS
    off = RGBColor(0, 0, 0)
    hsv, mtime = colorsys.rgb_to_hsv(*read_colour()), None
    t0 = time.monotonic()
    while True:
        now = time.monotonic()
        try:
            m = SRC.stat().st_mtime
        except OSError:
            m = None
        if m != mtime:  # wallpaper changed
            mtime, hsv = m, colorsys.rgb_to_hsv(*read_colour())
        try:
            dev.set_colors([off] * before + frame((now - t0) * SPEED, hsv) + [off] * after, fast=True)
        except (ConnectionError, OSError, BrokenPipeError):
            print("lost the openrgb server, reconnecting", file=sys.stderr, flush=True)
            client, dev = connect()
            dev.set_mode("direct")
        time.sleep(max(0.0, 1 / FPS - (time.monotonic() - now)))

if __name__ == "__main__":
    main()
