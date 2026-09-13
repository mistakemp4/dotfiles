#!/usr/bin/env bash

DOTFILES=$1
DOTFILES=${DOTFILES:="$HOME/.dotfiles"}

DOTFILES_BACKUP_FOLDER=$2
DOTFILES_BACKUP_FOLDER=${DOTFILES_BACKUP_FOLDER:="$HOME/.backup_$(date +%Y%m%d_%H%M%S)"}

mkdir -p "$DOTFILES_BACKUP_FOLDER"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.local/share/applications"

# ~/.local/bin scripts
for f in "$DOTFILES"/local-bin/*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  dest="$HOME/.local/bin/$name"

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$DOTFILES_BACKUP_FOLDER/$name"
    echo "Backed up current $name to $DOTFILES_BACKUP_FOLDER/$name"
  fi

  chmod +x "$f"
  ln -sf "$f" "$dest"
  printf "\nInstalled %s to ~/.local/bin\n\n" "$name"
done

# systemd --user unit drop-ins, preserving directory structure (e.g. wireplumber.service.d/foo.conf)
while IFS= read -r -d '' src; do
  rel="${src#"$DOTFILES"/systemd-user/}"
  dest="$HOME/.config/systemd/user/$rel"
  mkdir -p "$(dirname "$dest")"

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mkdir -p "$(dirname "$DOTFILES_BACKUP_FOLDER/systemd-user/$rel")"
    mv "$dest" "$DOTFILES_BACKUP_FOLDER/systemd-user/$rel"
    echo "Backed up current $rel to $DOTFILES_BACKUP_FOLDER/systemd-user/$rel"
  fi

  ln -sf "$src" "$dest"
  printf "\nInstalled systemd unit %s\n\n" "$rel"
done < <(find "$DOTFILES/systemd-user" -type f -print0 2>/dev/null)

# ~/.local/share/applications desktop-file overrides
for f in "$DOTFILES"/local-share-applications/*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  dest="$HOME/.local/share/applications/$name"

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$DOTFILES_BACKUP_FOLDER/$name"
    echo "Backed up current $name to $DOTFILES_BACKUP_FOLDER/$name"
  fi

  ln -sf "$f" "$dest"
  printf "\nInstalled desktop override %s\n\n" "$name"
done
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

systemctl --user daemon-reload

# noctalia replaces its gui-saved settings on every save, so it's copied rather than linked
state_settings="$HOME/.local/state/noctalia/settings.toml"
if [ ! -e "$state_settings" ] && [ -f "$DOTFILES/config/noctalia/state-settings.toml" ]; then
  mkdir -p "$(dirname "$state_settings")"
  cp "$DOTFILES/config/noctalia/state-settings.toml" "$state_settings"
  echo "Restored noctalia state settings"
fi

# linking a unit doesn't enable it; skip units without [Install] (they're triggered by others)
for f in "$DOTFILES"/systemd-user/*.service "$DOTFILES"/systemd-user/*.path; do
  [ -e "$f" ] || continue
  grep -q '^\[Install\]' "$f" || continue
  systemctl --user enable --now "$(basename "$f")"
done
