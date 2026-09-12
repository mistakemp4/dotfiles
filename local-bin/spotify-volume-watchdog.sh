#!/usr/bin/env bash
# Auto-corrects Spotify's PipeWire stream volume if it unexpectedly snaps to
# exactly 100% (a known trigger: Noctalia's audio-visualizer widget reconnecting
# its capture stream on track change), restoring whatever level you'd actually
# last set it to. Event-driven (reacts instantly to the pactl event) rather
# than polling, so the correction lands in milliseconds, not seconds.
last_good=50

pactl subscribe 2>/dev/null | while read -r line; do
    case "$line" in
        *"on sink-input"*) ;;
        *) continue ;;
    esac

    id=$(echo "$line" | grep -oP 'sink-input #\K[0-9]+')
    [ -z "$id" ] && continue

    block=$(pactl list sink-inputs 2>/dev/null | awk -v target="Sink Input #$id" '
        $0 == target {capture=1}
        capture {print}
        capture && /^$/{exit}
    ')
    [ -z "$block" ] && continue
    echo "$block" | grep -q 'application.name = "Spotify"' || continue

    vol=$(echo "$block" | grep -oP 'Volume:.*?\K[0-9]+(?=%)' | head -1)
    [ -z "$vol" ] && continue

    if [ "$vol" -eq 100 ] && [ "$last_good" -ne 100 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') corrected sink-input #$id from 100% back to ${last_good}%"
        pactl set-sink-input-volume "$id" "${last_good}%"
    else
        last_good=$vol
    fi
done
