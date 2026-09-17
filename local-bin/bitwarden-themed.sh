#!/usr/bin/env bash
set -uo pipefail

PORT=9333

# log to the journal: if the launching terminal closes, bitwarden crashes on EIO
bitwarden-desktop --remote-debugging-port="$PORT" "$@" </dev/null 2>&1 | systemd-cat -t bitwarden-desktop &
BW_PID=$!

for _ in $(seq 1 30); do
    curl -s "http://localhost:$PORT/json" >/dev/null 2>&1 && break
    sleep 0.5
done
sleep 1

python3 "$HOME/.local/bin/theme_bitwarden.py" >/dev/null 2>&1

wait "$BW_PID"
