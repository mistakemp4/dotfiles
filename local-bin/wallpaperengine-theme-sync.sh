#!/usr/bin/env bash
set -uo pipefail

WORKSHOP_DIR="$HOME/.local/share/Steam/steamapps/workshop/content/431960"
CACHE_DIR="$HOME/.cache/wallpaperengine-theme-sync"
FRAME_DIR="$HOME/Pictures/WallPapers"
STATE_FILE="$CACHE_DIR/last-id"
FALLBACK_PALETTE="motherboard"

mkdir -p "$CACHE_DIR" "$FRAME_DIR"

current_bg_id() {
    pgrep -af linux-wallpaperengine 2>/dev/null | grep -oP -- '--bg\s+\K[0-9]+' | head -1
}

image_width() {
    ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$1" 2>/dev/null
}

capture_scene() {
    local id="$1" out="$2" png="$CACHE_DIR/capture-$1.png" size pid last=""
    size=$(niri msg -j outputs | python3 -c "import json,sys; o=next(iter(json.load(sys.stdin).values())); m=o['modes'][o['current_mode']]; print(f\"{m['width']}x{m['height']}\")")
    linux-wallpaperengine --window "0x0x$size" --silent --screenshot "$png" --screenshot-delay 60 "$id" >/dev/null 2>&1 &
    pid=$!
    for _ in $(seq 1 60); do
        kill -0 "$pid" 2>/dev/null || break
        if [ -s "$png" ]; then
            [ "$(stat -c %s "$png")" = "$last" ] && break
            last=$(stat -c %s "$png")
        fi
        sleep 0.5
    done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [ -s "$png" ] && ffmpeg -y -i "$png" -q:v 2 -update 1 "$out" >/dev/null 2>&1
    rm -f "$png"
}

apply_fallback() {
    noctalia msg color-scheme-set custom "$FALLBACK_PALETTE" >/dev/null 2>&1
    echo "fell back to $FALLBACK_PALETTE palette"
}

sync_theme_for_id() {
    local id="$1"
    local item_dir="$WORKSHOP_DIR/$id"
    local project="$item_dir/project.json"
    local out_image="$FRAME_DIR/we-${id}-hd.jpg" old_image="$FRAME_DIR/we-${id}.jpg"

    [ -f "$project" ] || { echo "no project.json for $id, skipping"; return 1; }

    local width
    width=$(image_width "$out_image")
    if [ ! -s "$out_image" ] || [ "${width:-0}" -lt 1000 ]; then
        : > "$out_image"
        local type file preview
        type=$(python3 -c "import json; print(json.load(open('$project')).get('type','').lower())" 2>/dev/null)
        file=$(python3 -c "import json; print(json.load(open('$project')).get('file',''))" 2>/dev/null)
        preview=$(python3 -c "import json; print(json.load(open('$project')).get('preview',''))" 2>/dev/null)

        if [ "${type,,}" = "video" ] && [ -n "$file" ] && [ -f "$item_dir/$file" ]; then
            ffmpeg -y -ss 5 -i "$item_dir/$file" -frames:v 1 -q:v 2 -update 1 "$out_image" >/dev/null 2>&1
            [ -s "$out_image" ] || ffmpeg -y -ss 0 -i "$item_dir/$file" -frames:v 1 -q:v 2 -update 1 "$out_image" >/dev/null 2>&1
        elif [ "${type,,}" = "scene" ]; then
            capture_scene "$id" "$out_image"
        fi

        if [ ! -s "$out_image" ] && [ -n "$preview" ] && [ -f "$item_dir/$preview" ]; then
            ffmpeg -y -i "$item_dir/$preview" -frames:v 1 -update 1 "$out_image" >/dev/null 2>&1
        fi
    fi

    if [ -s "$out_image" ]; then
        [ -e "$old_image" ] && gio trash "$old_image"
        # 2 = noctalia unreachable: retry, do not fall back
        noctalia msg wallpaper-set "$out_image" >/dev/null 2>&1 || return 2
        noctalia msg color-scheme-set wallpaper vibrant >/dev/null 2>&1 || return 2
        echo "synced theme from wallpaper $id -> $out_image"
        return 0
    else
        echo "failed to derive an image for wallpaper $id"
        return 1
    fi
}

last_id=""
[ -f "$STATE_FILE" ] && last_id=$(cat "$STATE_FILE")
fallback_id=""
ipc_down_id=""

while true; do
    id=$(current_bg_id)
    if [ -n "$id" ] && [ "$id" != "$last_id" ]; then
        sync_theme_for_id "$id"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            last_id="$id"
            fallback_id=""
            echo "$last_id" > "$STATE_FILE"
        elif [ "$rc" -eq 2 ]; then
            [ "$id" = "$ipc_down_id" ] || echo "noctalia IPC unreachable (WAYLAND_DISPLAY='${WAYLAND_DISPLAY:-}'), retrying"
            ipc_down_id="$id"
        elif [ "$id" != "$fallback_id" ]; then
            apply_fallback
            fallback_id="$id"
            last_id=""
            : > "$STATE_FILE"
        fi
    fi
    sleep 5
done
