#!/usr/bin/env python3
# case rgb (asus aura headers) follows the noctalia colour, same source as the F75
import subprocess
import sys
from pathlib import Path

SRC = Path.home() / ".cache/noctalia/f75-lighting.txt"
DEVICE = "ASUS PRIME B850-PLUS WIFI"  # never omit: openrgb hits every device otherwise
ZONE = 2  # header 3: fans, case & cooler are all chained here
LEDS = 150  # aura can't report counts, extra leds are ignored
GAMMA = 2.2  # hex is sRGB, leds are linear

def read_colour(path):
    line = path.read_text().strip().splitlines()[0].strip().lstrip("#")
    return tuple(int(line[i:i + 2], 16) for i in (0, 2, 4))

def correct(rgb):
    return tuple(round((v / 255) ** GAMMA * 255) for v in rgb)

def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    rgb = correct(read_colour(src))
    hexc = "".join(f"{v:02X}" for v in rgb)
    cmd = ["openrgb", "--noautoconnect", "-d", DEVICE, "-m", "direct",
           "-z", str(ZONE), "-sz", str(LEDS), "-c", hexc]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    print(f"case lighting #{hexc}" + ("" if r.returncode == 0 else f" failed: {r.stderr.strip()[-300:]}"))
    sys.exit(r.returncode)

if __name__ == "__main__":
    main()
