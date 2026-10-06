#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sudo install -m 0755 "$DOTFILES/system/f75-lighting/f75-lighting-apply" /usr/local/bin/f75-lighting-apply
sudo install -m 0644 "$DOTFILES/system/f75-lighting/f75-lighting.service" /etc/systemd/system/f75-lighting.service
sudo install -m 0644 "$DOTFILES/system/f75-lighting/f75-lighting.path" /etc/systemd/system/f75-lighting.path
sudo install -m 0644 "$DOTFILES/system/udev-rules/70-aula-f75.rules" /etc/udev/rules.d/70-aula-f75.rules
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemctl enable --now f75-lighting.path
sudo systemctl start f75-lighting.service
