#!/usr/bin/env bash

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS=$DOTFILES/scripts

DOTFILES_BACKUP_FOLDER="$HOME/.backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DOTFILES_BACKUP_FOLDER"

chmod +x "$SCRIPTS"/install/*.sh

"$SCRIPTS/install/config.sh" "$DOTFILES" "$DOTFILES_BACKUP_FOLDER"

"$SCRIPTS/install/local-extras.sh" "$DOTFILES" "$DOTFILES_BACKUP_FOLDER"

printf "\nSetup finished, enjoy!\n"
