#!/usr/bin/env bash
# btop has no Noctalia template of its own, so borrow wezterm's (already
# regenerated on every theme change) and translate it into a btop .theme file.
set -euo pipefail

SRC="$HOME/.config/wezterm/colors/Noctalia.toml"
DEST="$HOME/.config/btop/themes/noctalia.theme"

[ -f "$SRC" ] || { echo "no wezterm Noctalia.toml found, skipping"; exit 1; }

mkdir -p "$(dirname "$DEST")"

python3 - "$SRC" "$DEST" <<'PY'
import sys
import tomllib

src, dest = sys.argv[1], sys.argv[2]
with open(src, "rb") as f:
    data = tomllib.load(f)

c = data["colors"]
bg = c["background"]
fg = c["foreground"]
box = c["selection_bg"]
muted = c["selection_fg"]
accent = c["ansi"][2]
gold = c["ansi"][4]
red = c["ansi"][1]
sel_fg = c.get("cursor_fg", bg)

lines = [
    "# Auto-generated from wezterm's Noctalia.toml by sync-btop-theme.sh",
    "# Regenerated on every wallpaper change, do not edit by hand",
    "",
    f'theme[main_bg]="{bg}"',
    f'theme[main_fg]="{fg}"',
    f'theme[title]="{fg}"',
    f'theme[hi_fg]="{accent}"',
    f'theme[selected_bg]="{accent}"',
    f'theme[selected_fg]="{sel_fg}"',
    f'theme[inactive_fg]="{muted}"',
    f'theme[proc_misc]="{gold}"',
    f'theme[cpu_box]="{box}"',
    f'theme[mem_box]="{box}"',
    f'theme[net_box]="{box}"',
    f'theme[proc_box]="{box}"',
    f'theme[div_line]="{box}"',
    f'theme[meter_bg]="{box}"',
    f'theme[graph_text]="{muted}"',
]

for group in ("temp", "cpu", "free", "cached", "available", "used",
              "download", "upload", "process"):
    lines.append(f'theme[{group}_start]="{gold}"')
    lines.append(f'theme[{group}_mid]="{accent}"')
    lines.append(f'theme[{group}_end]="{red}"')

with open(dest, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"wrote {dest}")
PY
