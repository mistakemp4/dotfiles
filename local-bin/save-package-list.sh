#!/usr/bin/env bash
set -euo pipefail

OUT="$(dirname "$(readlink -f "$0")")/../packages"

# the .path unit fires mid-transaction
for _ in $(seq 1 600); do
    [ -e /var/lib/pacman/db.lck ] || break
    sleep 1
done

mkdir -p "$OUT"
pacman -Qqen > "$OUT/.pacman.txt.tmp" && mv "$OUT/.pacman.txt.tmp" "$OUT/pacman.txt"
pacman -Qqem > "$OUT/.aur.txt.tmp" && mv "$OUT/.aur.txt.tmp" "$OUT/aur.txt"
