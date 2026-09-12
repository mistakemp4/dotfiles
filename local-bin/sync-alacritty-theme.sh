#!/usr/bin/env bash
# Alacritty has no Noctalia template of its own, but wezterm's (already
# enabled) has the identical color-role structure, freshly regenerated on
# every theme change. Translate that into Alacritty's TOML color format.
set -euo pipefail

SRC="$HOME/.config/wezterm/colors/Noctalia.toml"
DEST="$HOME/.config/alacritty/colors-noctalia.toml"

[ -f "$SRC" ] || { echo "no wezterm Noctalia.toml found, skipping"; exit 1; }

python3 - "$SRC" "$DEST" <<'PY'
import sys
import tomllib

src, dest = sys.argv[1], sys.argv[2]
with open(src, "rb") as f:
    data = tomllib.load(f)

c = data["colors"]
ansi = c["ansi"]
brights = c["brights"]
names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

out = []
out.append("[colors.primary]")
out.append(f'background = "{c["background"]}"')
out.append(f'foreground = "{c["foreground"]}"')
out.append("")
out.append("[colors.cursor]")
out.append(f'text = "{c.get("cursor_fg", c["background"])}"')
out.append(f'cursor = "{c.get("cursor_bg", c["foreground"])}"')
out.append("")
out.append("[colors.selection]")
out.append(f'text = "{c.get("selection_fg", c["foreground"])}"')
out.append(f'background = "{c.get("selection_bg", c["background"])}"')
out.append("")
out.append("[colors.normal]")
for name, hexval in zip(names, ansi):
    out.append(f'{name} = "{hexval}"')
out.append("")
out.append("[colors.bright]")
for name, hexval in zip(names, brights):
    out.append(f'{name} = "{hexval}"')

with open(dest, "w") as f:
    f.write("\n".join(out) + "\n")

print(f"wrote {dest}")
PY
