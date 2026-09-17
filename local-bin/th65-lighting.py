#!/usr/bin/env python3
"""Set the Epomaker TH65's key lighting, by default from the current Noctalia palette.

Only the key zone is host-controllable. The side and front strips are cycled by
firmware actions bound to Fn keys (Fn+.> / Fn+/? and Fn+PgUp / Fn+PgDn) and have
no host command at all, so they can't follow the wallpaper -- set them by hand.

Protocol (SONiX 0c45:8011, vendor interface 3, usage page 0xff68/usage 0x61):
  packet = aa <cmd> <len> <off_lo> <off_hi> 00 <last> 00 + payload, padded to 64
  hidraw wants a leading 0x00 report-ID byte, so 65 bytes go out
  cmd 0x23 writes the 16-byte lighting struct:
      <mode> <R> <G> <B> ff 00 00 00 <dir> <speed> <brightness> 00 00 00 aa 55
  cmd 0x33 reads back the 128-LED framebuffer -- the only trustworthy check, as
  cmd 0x13 can return a stale struct right after a write.
"""

import argparse
import glob
import json
import os
import re
import sys
import time
from pathlib import Path

VENDOR, PRODUCT, IFACE = "0c45", "8011", "03"
PALETTE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "noctalia/bitwarden-colors.json"

MODE_STATIC = 0x01
DEFAULT_SPEED = 0x05
DEFAULT_BRIGHTNESS = 0x03
HEX = re.compile(r"#?([0-9a-fA-F]{6})$")


def find_device():
    """The vendor config interface, by USB ids -- hidraw numbering isn't stable."""
    for dev in sorted(glob.glob("/sys/bus/hid/devices/*")):
        usb = Path(dev).resolve().parent
        try:
            if (usb.parent / "idVendor").read_text().strip() != VENDOR:
                continue
            if (usb.parent / "idProduct").read_text().strip() != PRODUCT:
                continue
            if (usb / "bInterfaceNumber").read_text().strip() != IFACE:
                continue
        except OSError:
            continue
        nodes = list((Path(dev) / "hidraw").glob("hidraw*"))
        if nodes:
            return f"/dev/{nodes[0].name}"
    return None


def packet(cmd, payload, offset=0, last=1):
    head = bytes([0xAA, cmd, len(payload), offset & 0xFF, (offset >> 8) & 0xFF, 0, last, 0])
    return (head + bytes(payload)).ljust(64, b"\x00")


class Keyboard:
    def __init__(self, path):
        self.fd = os.open(path, os.O_RDWR)

    def close(self):
        os.close(self.fd)

    def _drain(self):
        os.set_blocking(self.fd, False)
        while True:
            try:
                os.read(self.fd, 64)
            except (BlockingIOError, OSError):
                return

    def xfer(self, pkt, tries=30):
        self._drain()
        os.set_blocking(self.fd, True)
        os.write(self.fd, b"\x00" + pkt)          # leading report id, reports are unnumbered
        os.set_blocking(self.fd, False)
        for _ in range(tries):
            try:
                return os.read(self.fd, 64)
            except BlockingIOError:
                time.sleep(0.03)
        return None

    def set_colour(self, rgb, mode, speed, brightness, direction=0):
        body = bytes([mode, *rgb, 0xFF, 0, 0, 0, direction, speed, brightness, 0, 0, 0, 0xAA, 0x55])
        return self.xfer(packet(0x23, body, last=1))

    def read_leds(self):
        leds = {}
        off = 0
        while off < 0x200:
            ln = min(0x38, 0x200 - off)
            body = bytearray(56)
            for i in range(0, ln, 4):
                body[i] = (off + i) // 4
            r = self.xfer(packet(0x33, body[:ln], offset=off, last=1 if off + ln >= 0x200 else 0))
            if r and len(r) > 8 and r[1] == 0x33:
                for i in range(0, r[2], 4):
                    e = r[8 + i:12 + i]
                    if len(e) == 4:
                        leds[e[0]] = tuple(e[1:])
            off += ln
        return leds


def palette_colour(key):
    try:
        raw = json.loads(PALETTE.read_text())
    except (OSError, json.JSONDecodeError) as e:
        sys.exit(f"cannot read the palette at {PALETTE}: {e}")
    if key not in raw:
        sys.exit(f"palette has no '{key}' (have: {', '.join(sorted(raw))})")
    m = HEX.match(str(raw[key]).strip())
    if not m:
        sys.exit(f"palette entry '{key}' is not a hex colour: {raw[key]!r}")
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--colour", "--color", dest="colour", help="RRGGBB instead of the palette colour")
    p.add_argument("--file", type=Path,
                   help="read the colour from this file's first line; as a Noctalia post_hook this is "
                        "the template's own freshly-rendered output, so there's no ordering dependency "
                        "on other templates")
    p.add_argument("--key", default="primary", help="palette entry to use (default: primary)")
    p.add_argument("--mode", type=lambda v: int(v, 0), default=MODE_STATIC,
                   help="lighting mode; only a static mode shows a fixed colour (default: 1)")
    p.add_argument("--speed", type=lambda v: int(v, 0), default=DEFAULT_SPEED)
    p.add_argument("--brightness", type=lambda v: int(v, 0), default=DEFAULT_BRIGHTNESS)
    p.add_argument("--verify", action="store_true", help="read the framebuffer back and report")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args()

    if args.colour:
        source = args.colour.strip()
    elif args.file:
        try:
            source = args.file.read_text().strip().splitlines()[0].strip()
        except (OSError, IndexError) as e:
            sys.exit(f"cannot read a colour from {args.file}: {e}")
    else:
        source = None

    if source is not None:
        m = HEX.match(source)
        if not m:
            sys.exit(f"expected RRGGBB, got {source!r}")
        h = m.group(1)
        rgb = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    else:
        rgb = palette_colour(args.key)

    path = find_device()
    if not path:
        sys.exit(f"no TH65 vendor interface found ({VENDOR}:{PRODUCT} iface {IFACE}); is it plugged in?")

    try:
        kb = Keyboard(path)
    except PermissionError:
        sys.exit(f"{path} is not writable -- install system/udev-rules/70-epomaker-th65.rules")

    try:
        echo = kb.set_colour(rgb, args.mode, args.speed, args.brightness)
        ok = bool(echo) and len(echo) > 12 and echo[1] == 0x23 and tuple(echo[9:12]) == rgb
        if not args.quiet:
            print(f"{path}: set #{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x} mode={args.mode} "
                  f"({'acked' if ok else 'NO ACK'})")
        if args.verify:
            time.sleep(0.5)
            leds = kb.read_leds()
            lit = [c for c in leds.values() if any(c)]
            from collections import Counter
            top = Counter(lit).most_common(1)
            if top:
                c, n = top[0]
                # the board applies brightness as a scale, so expect a proportional match
                print(f"   framebuffer: {n} LEDs at {c[0]:02x} {c[1]:02x} {c[2]:02x}")
        return 0 if ok else 1
    finally:
        kb.close()


if __name__ == "__main__":
    sys.exit(main())
