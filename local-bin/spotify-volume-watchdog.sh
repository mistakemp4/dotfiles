#!/usr/bin/env bash
# Auto-corrects Spotify's PipeWire stream volume if it unexpectedly snaps to
# exactly 100% (the known-buggy reset value), restoring whatever level you'd
# actually last set it to instead of a fixed number.
last_good=50

while true; do
    block=$(pactl list sink-inputs 2>/dev/null | awk '/Sink Input #/{block=""} {block=block"\n"$0} /application\.name = "Spotify"/{print block; exit}')
    if [ -n "$block" ]; then
        id=$(echo "$block" | grep -oP 'Sink Input #\K[0-9]+')
        vol=$(echo "$block" | grep -oP 'Volume:.*?\K[0-9]+(?=%)' | head -1)
        if [ -n "$id" ] && [ -n "$vol" ]; then
            if [ "$vol" -eq 100 ] && [ "$last_good" -ne 100 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') corrected sink-input #$id from 100% back to ${last_good}%"
                pactl set-sink-input-volume "$id" "${last_good}%"
            else
                last_good=$vol
            fi
        fi
    fi
    sleep 2
done
