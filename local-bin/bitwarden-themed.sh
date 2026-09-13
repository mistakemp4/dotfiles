#!/usr/bin/env bash
# Launches Bitwarden with remote debugging enabled, then injects the
# Noctalia-derived CSS custom-property overrides via CDP once it's up.
set -uo pipefail

PORT=9333

wallpaper=$(noctalia msg wallpaper-get 2>/dev/null)
if [ -f "$wallpaper" ]; then
    noctalia theme "$wallpaper" --scheme vibrant --dark \
        -r "$HOME/.config/noctalia/templates/bitwarden.json:$HOME/.cache/noctalia/bitwarden-colors.json" >/dev/null 2>&1
fi

bitwarden-desktop --remote-debugging-port="$PORT" "$@" &
BW_PID=$!

for _ in $(seq 1 30); do
    curl -s "http://localhost:$PORT/json" >/dev/null 2>&1 && break
    sleep 0.5
done
sleep 1

python3 "$HOME/.local/bin/theme_bitwarden.py" >/dev/null 2>&1

wait "$BW_PID"
