#!/usr/bin/env python3
"""Build the Noctalia-Cursors theme: Adwaita's cursors recolored with the current Noctalia palette.

Run by Noctalia's cursor-colors template hook. Reads "fill\\noutline" hex colors from
~/.cache/noctalia/cursor-colors.txt, or takes them as two arguments.

niri only reloads cursors when the theme name changes, so niri alternates between two identical
themes via ~/.config/niri/cursor.kdl. Clients that load cursors themselves (XCURSOR_THEME, e.g.
linux-wallpaperengine) use the stable Noctalia-Cursors name and pick up new colors on restart.
"""
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

SOURCE = Path("/usr/share/icons/Adwaita/cursors")
ICONS = Path.home() / ".local/share/icons"
NAMES = ("Noctalia-Cursors", "Noctalia-Cursors-Alt")
COLORS = Path.home() / ".cache/noctalia/cursor-colors.txt"
NIRI_INCLUDE = Path.home() / ".config/niri/cursor.kdl"
XCURSOR_IMAGE = 0xFFFD0002


def parse_hex(text):
    text = text.strip().lstrip("#")
    if len(text) != 6:
        raise ValueError(f"not a #rrggbb color: {text!r}")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def make_recolor(fill, outline):
    cache = {}

    def recolor(pixel):
        if pixel in cache:
            return cache[pixel]
        alpha = pixel >> 24
        out = pixel
        if alpha:
            # xcursor pixels are premultiplied ARGB
            r, g, b = (min(255, ((pixel >> s) & 255) * 255 // alpha) for s in (16, 8, 0))
            lum = (r * 299 + g * 587 + b * 114) / 255000
            shadow = alpha <= 64 and lum < 0.25
            colored = max(r, g, b) - min(r, g, b) > 60  # e.g. the red "not-allowed" sign
            if not shadow and not colored:
                r, g, b = (round(f + (o - f) * lum) * alpha // 255 for f, o in zip(fill, outline))
                out = (alpha << 24) | (r << 16) | (g << 8) | b
        cache[pixel] = out
        return out

    return recolor


def recolor_file(data, recolor):
    magic, header_size, _, count = struct.unpack_from("<4sIII", data)
    if magic != b"Xcur":
        raise ValueError("not an xcursor file")
    out = bytearray(data)
    for i in range(count):
        kind, _, pos = struct.unpack_from("<III", data, header_size + 12 * i)
        if kind != XCURSOR_IMAGE:
            continue
        chunk_size, _, _, _, width, height = struct.unpack_from("<6I", data, pos)
        fmt = f"<{width * height}I"
        pixels = struct.unpack_from(fmt, data, pos + chunk_size)
        struct.pack_into(fmt, out, pos + chunk_size, *map(recolor, pixels))
    return bytes(out)


def write_atomic(path, data):
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def stamp_of(name):
    try:
        return (ICONS / name / ".colors").read_text()
    except FileNotFoundError:
        return None


def build(name, recolor, stamp):
    theme = ICONS / name
    cursors = theme / "cursors"
    cursors.mkdir(parents=True, exist_ok=True)
    for src in sorted(SOURCE.iterdir()):
        dst = cursors / src.name
        if src.is_symlink():
            if not dst.is_symlink():
                dst.symlink_to(os.readlink(src))
            continue
        write_atomic(dst, recolor_file(src.read_bytes(), recolor))
    write_atomic(theme / "index.theme", f"[Icon Theme]\nName={name}\n"
                 "Comment=Adwaita cursors in the Noctalia palette\nInherits=Adwaita\n".encode())
    write_atomic(theme / ".colors", stamp.encode())


def current_name():
    try:
        match = re.search(r'xcursor-theme "([^"]+)"', NIRI_INCLUDE.read_text())
    except FileNotFoundError:
        return None
    return match.group(1) if match else None


def main():
    lines = sys.argv[1:3] if len(sys.argv) == 3 else COLORS.read_text().split()
    fill, outline = parse_hex(lines[0]), parse_hex(lines[1])
    stamp = f"{lines[0].strip()} {lines[1].strip()}\n"
    if all(stamp_of(name) == stamp for name in NAMES):
        return

    active = current_name()
    target = NAMES[1] if active == NAMES[0] else NAMES[0]
    other = NAMES[0] if target == NAMES[1] else NAMES[1]
    recolor = make_recolor(fill, outline)

    # niri watches its includes, so switching names swaps the cursor live; gsettings covers GTK apps
    build(target, recolor, stamp)
    write_atomic(NIRI_INCLUDE, f'// rendered by noctalia-cursors.py\ncursor {{\n    xcursor-theme "{target}"\n}}\n'.encode())
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", target], check=False)
    # keep both copies identical, so XCURSOR_THEME=Noctalia-Cursors is always current
    build(other, recolor, stamp)

    # apps that ignore XCURSOR_THEME (Steam inside pressure-vessel) fall back to the "default" theme
    default_theme = ICONS.parent.parent / ".icons/default"
    default_theme.mkdir(parents=True, exist_ok=True)
    write_atomic(default_theme / "index.theme", f"[Icon Theme]\nName=Default\n"
                 f"Comment=Fallback for apps that ignore XCURSOR_THEME\nInherits={NAMES[0]}\n".encode())


if __name__ == "__main__":
    main()
