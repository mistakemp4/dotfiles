#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sudo pacman -S --needed - < "$DOTFILES/packages/pacman.txt"
command -v paru >/dev/null || sudo pacman -S --needed paru
paru -S --needed - < "$DOTFILES/packages/aur.txt"
