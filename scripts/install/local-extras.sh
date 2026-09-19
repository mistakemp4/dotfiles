#!/usr/bin/env bash

DOTFILES=$1
DOTFILES=${DOTFILES:="$HOME/.dotfiles"}

DOTFILES_BACKUP_FOLDER=$2
DOTFILES_BACKUP_FOLDER=${DOTFILES_BACKUP_FOLDER:="$HOME/.backup_$(date +%Y%m%d_%H%M%S)"}

mkdir -p "$DOTFILES_BACKUP_FOLDER"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.local/share/applications"

for f in "$DOTFILES"/home/.[!.]*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  dest="$HOME/$name"

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$DOTFILES_BACKUP_FOLDER/$name"
    echo "Backed up current $name to $DOTFILES_BACKUP_FOLDER/$name"
  fi

  ln -sf "$f" "$dest"
  printf "\nInstalled %s to ~\n\n" "$name"
done

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

mkdir -p "$HOME/.local/share/noctalia/plugins"
for d in "$DOTFILES"/noctalia-plugins/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  ln -sfn "${d%/}" "$HOME/.local/share/noctalia/plugins/$name"
  printf "\nInstalled noctalia plugin %s\n\n" "$name"
done

if [ -x "$HOME/.spicetify/spicetify" ]; then
  ln -sfn "$HOME/.spicetify/spicetify" "$HOME/.local/bin/spicetify"
  echo "Linked spicetify into ~/.local/bin"
fi

systemctl --user daemon-reload

ff_prefs="$HOME/.config/fontforge/prefs"
if ! grep -q "^ResourceFile:" "$ff_prefs" 2>/dev/null; then
  mkdir -p "$(dirname "$ff_prefs")"
  printf 'ResourceFile:\t%s\n' "$HOME/.config/fontforge/noctalia.resource" >> "$ff_prefs"
  echo "Set fontforge ResourceFile"
fi

state_settings="$HOME/.local/state/noctalia/settings.toml"
if [ ! -e "$state_settings" ] && [ -f "$DOTFILES/config/noctalia/state-settings.toml" ]; then
  mkdir -p "$(dirname "$state_settings")"
  cp "$DOTFILES/config/noctalia/state-settings.toml" "$state_settings"
  echo "Restored noctalia state settings"
fi

for f in "$DOTFILES"/systemd-user/*.service "$DOTFILES"/systemd-user/*.path; do
  [ -e "$f" ] || continue
  grep -q '^\[Install\]' "$f" || continue
  systemctl --user enable --now "$(basename "$f")"
done
