#!/usr/bin/env bash

DOTFILES=$1
DOTFILES=${DOTFILES:="$HOME/.dotfiles"}

DOTFILES_BACKUP_FOLDER=$2
DOTFILES_BACKUP_FOLDER=${DOTFILES_BACKUP_FOLDER:="$HOME/.backup_$(date +%Y%m%d_%H%M%S)"}

mkdir -p "$DOTFILES_BACKUP_FOLDER"
mkdir -p ~/.config/

# paths relative to config/, linked to the same path under ~/.config
CONFIG_FILES=(
  alacritty
  btop
  fastfetch
  niri
  noctalia
  nvim
  spicetify
  starship.toml
  wireplumber
  'Code - OSS/User/settings.json'
)

for i in "${CONFIG_FILES[@]}"; do
  src="$DOTFILES/config/$i"
  dest="$HOME/.config/$i"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "$i already linked"
    continue
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mkdir -p "$(dirname "$DOTFILES_BACKUP_FOLDER/$i")"
    mv "$dest" "$DOTFILES_BACKUP_FOLDER/$i"
    echo "Backed up current $i configuration to $DOTFILES_BACKUP_FOLDER/$i"
  fi

  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  printf "\nInstalled %s configuration\n\n" "$i"
done
