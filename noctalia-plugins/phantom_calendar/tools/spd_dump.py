import io
import json
import struct
import subprocess
import sys
from pathlib import Path

from PIL import Image

HEADER = struct.Struct("<5i2h2i")
TEXTURE = struct.Struct("<8i16s")
SPRITE = struct.Struct("<28I48s")
SPD_MAGIC = 0x30525053

def load_dds(data: bytes, scratch: Path) -> Image.Image:
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
        return img.convert("RGBA")
    except Exception:
        src = scratch.with_suffix(".dds")
        dst = scratch.with_suffix(".magick.png")
        src.write_bytes(data)
        subprocess.run(["magick", str(src), str(dst)], check=True)
        return Image.open(dst).convert("RGBA")

def cstr(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("ascii", "replace")

def dump(spd_path: Path, out_dir: Path) -> None:
    data = spd_path.read_bytes()
    magic, _, _, _, _, tex_count, spr_count, tex_off, spr_off = HEADER.unpack_from(data, 0)
    if magic != SPD_MAGIC:
        raise SystemExit(f"{spd_path}: not an SPD (magic {magic:#x})")

    out_dir.mkdir(parents=True, exist_ok=True)
    textures = {}
    index = {"textures": [], "sprites": []}

    for i in range(tex_count):
        tid, _, off, size, w, h, _, _, desc = TEXTURE.unpack_from(data, tex_off + i * TEXTURE.size)
        img = load_dds(data[off:off + size], out_dir / f"tex_{tid}")
        img.save(out_dir / f"tex_{tid}.png")
        textures[tid] = img
        index["textures"].append({"id": tid, "width": w, "height": h, "decoded": img.size, "name": cstr(desc)})

    for i in range(spr_count):
        f = SPRITE.unpack_from(data, spr_off + i * SPRITE.size)
        sid, tid, x, y, w, h, name = f[0], f[1], f[8], f[9], f[10], f[11], cstr(f[28])
        entry = {"id": sid, "texture": tid, "x": x, "y": y, "w": w, "h": h, "name": name}
        tex = textures.get(tid)
        if tex is not None and w > 0 and h > 0:
            tex.crop((x, y, x + w, y + h)).save(out_dir / f"spr_{sid:03d}.png")
        else:
            entry["skipped"] = True
        index["sprites"].append(entry)

    (out_dir / "index.json").write_text(json.dumps(index, indent=1))
    print(f"{spd_path.name}: {tex_count} textures, {spr_count} sprites -> {out_dir}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: spd_dump.py <file.spd> <out_dir>")
    dump(Path(sys.argv[1]), Path(sys.argv[2]))
