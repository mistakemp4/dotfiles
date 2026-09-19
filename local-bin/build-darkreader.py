import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = "https://github.com/darkreader/darkreader"
TAG = "v4.9.132"
SRC = Path(os.environ.get("DARKREADER_SRC", Path.home() / "src/darkreader-noctalia"))
PATCHES = Path(__file__).resolve().parents[1] / "patches/darkreader"
MANIFEST = SRC / "build/release/chrome-mv3/manifest.json"

def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)

def bootstrap():
    partial = SRC.with_name(f".{SRC.name}.partial")
    if partial.exists():
        run("gio", "trash", str(partial))
    run("git", "clone", "--quiet", "--depth", "1", "--branch", TAG, REPO, str(partial))
    for patch in sorted(PATCHES.glob("*.patch")):
        run("git", "apply", str(patch), cwd=partial)
    partial.rename(SRC)

def main():
    if not SRC.exists():
        bootstrap()
    if not (SRC / "node_modules").exists():
        run("npm", "ci", cwd=SRC)
    run("node", "tasks/cli.js", "build", "--release", "--chrome-mv3", cwd=SRC)
    manifest = json.loads(MANIFEST.read_text())
    # chromium keeps the old MV3 worker unless the version changes
    base = ".".join(manifest["version"].split(".")[:3])
    manifest["version"] = f"{base}.{int(time.time()) % 100000}"
    MANIFEST.write_text(json.dumps(manifest, indent=4))
    print(f"stamped version {manifest['version']} -- restart brave to load it")

if __name__ == "__main__":
    sys.exit(main())
