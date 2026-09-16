#!/usr/bin/env python3
"""Build the Noctalia-patched Dark Reader for Brave.

Chromium registers an MV3 service worker per extension *version*, so rebuilding
without bumping it leaves the old background worker running against the new
files. Stamp a unique build number after every build.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

SRC = Path.home() / "src/darkreader-noctalia"
MANIFEST = SRC / "build/release/chrome-mv3/manifest.json"


def main():
    subprocess.run(["node", "tasks/cli.js", "build", "--release", "--chrome-mv3"],
                   cwd=SRC, check=True)
    manifest = json.loads(MANIFEST.read_text())
    base = ".".join(manifest["version"].split(".")[:3])
    manifest["version"] = f"{base}.{int(time.time()) % 100000}"
    MANIFEST.write_text(json.dumps(manifest, indent=4))
    print(f"stamped version {manifest['version']} -- restart brave to load it")


if __name__ == "__main__":
    sys.exit(main())
