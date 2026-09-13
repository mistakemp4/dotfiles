#!/usr/bin/env bash
# Watches for Wallpaper Engine wallpaper changes and re-derives Noctalia's
# wallpaper-adaptive theme (and everything templated off it: Brave, Vesktop,
# terminal, etc.) from whatever's now actually on screen.
# If no image can be derived, falls back to the custom motherboard palette.
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

# bitwarden has no noctalia template, so render its colors ourselves and re-inject.
# args select the palette source: an image + --scheme, or --theme-json <palette>
theme_bitwarden() {
    noctalia theme "$@" --dark \
        -r "$HOME/.config/noctalia/templates/bitwarden.json:$HOME/.cache/noctalia/bitwarden-colors.json" >/dev/null 2>&1
    python3 "$HOME/.local/bin/theme_bitwarden.py" >/dev/null 2>&1
}

apply_fallback() {
    noctalia msg color-scheme-set custom "$FALLBACK_PALETTE" >/dev/null 2>&1
    theme_bitwarden --theme-json "$HOME/.config/noctalia/palettes/$FALLBACK_PALETTE.json"
    echo "fell back to $FALLBACK_PALETTE palette"
}

sync_theme_for_id() {
    local id="$1"
    local item_dir="$WORKSHOP_DIR/$id"
    local project="$item_dir/project.json"
    local out_image="$FRAME_DIR/we-${id}.jpg"

    [ -f "$project" ] || { echo "no project.json for $id, skipping"; return 1; }

    # -s, not -f: an empty frame from a failed ffmpeg run shouldn't block retries
    if [ ! -s "$out_image" ]; then
        local type file preview
        type=$(python3 -c "import json; print(json.load(open('$project')).get('type','').lower())" 2>/dev/null)
        file=$(python3 -c "import json; print(json.load(open('$project')).get('file',''))" 2>/dev/null)
        preview=$(python3 -c "import json; print(json.load(open('$project')).get('preview',''))" 2>/dev/null)

        if [ "${type,,}" = "video" ] && [ -n "$file" ] && [ -f "$item_dir/$file" ]; then
            ffmpeg -y -ss 5 -i "$item_dir/$file" -frames:v 1 -q:v 2 -update 1 "$out_image" >/dev/null 2>&1
            [ -s "$out_image" ] || ffmpeg -y -ss 0 -i "$item_dir/$file" -frames:v 1 -q:v 2 -update 1 "$out_image" >/dev/null 2>&1
        fi

        if [ ! -s "$out_image" ] && [ -n "$preview" ] && [ -f "$item_dir/$preview" ]; then
            ffmpeg -y -i "$item_dir/$preview" -frames:v 1 -update 1 "$out_image" >/dev/null 2>&1
        fi
    fi

    if [ -s "$out_image" ]; then
        noctalia msg wallpaper-set "$out_image" >/dev/null 2>&1
        noctalia msg color-scheme-set wallpaper vibrant >/dev/null 2>&1
        theme_bitwarden "$out_image" --scheme vibrant
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

while true; do
    id=$(current_bg_id)
    if [ -n "$id" ] && [ "$id" != "$last_id" ]; then
        if sync_theme_for_id "$id"; then
            last_id="$id"
            fallback_id=""
            echo "$last_id" > "$STATE_FILE"
        elif [ "$id" != "$fallback_id" ]; then
            # keep retrying the sync, but only switch palettes once per failing wallpaper.
            # forget last_id so switching back to a working wallpaper re-syncs it
            apply_fallback
            fallback_id="$id"
            last_id=""
            : > "$STATE_FILE"
        fi
    fi
    sleep 5
done
