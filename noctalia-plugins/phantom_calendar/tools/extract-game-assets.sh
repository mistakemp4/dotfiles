#!/usr/bin/env bash
# output is Atlus material: never commit it
set -euo pipefail

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME="${P5R_DIR:-$HOME/.local/share/Steam/steamapps/common/P5R}"
OUT="${P5_ASSETS_DIR:-$HOME/.local/share/p5-game-assets}"

[ -f "$GAME/CPK/EN.CPK" ] || { echo "EN.CPK not found under $GAME (set P5R_DIR)" >&2; exit 1; }
command -v dotnet >/dev/null || { echo "needs the .NET SDK (dotnet)" >&2; exit 1; }

build="$(mktemp -d)"
trap 'rm -r "$build"' EXIT
dotnet build "$TOOLS/cpktool/cpktool.csproj" -c Release -o "$build" >/dev/null

mkdir -p "$OUT/EN"
dotnet "$build/cpktool.dll" extract "$GAME/CPK/EN.CPK" "$OUT/EN" '^CALENDAR/(P5_FIELD_DAY|P5_TIME)\.SPD$'

for spd in P5_FIELD_DAY P5_TIME; do
    python3 "$TOOLS/spd_dump.py" "$OUT/EN/CALENDAR/$spd.SPD" "$OUT/dump/$spd"
done
echo "sprites ready in $OUT/dump"
