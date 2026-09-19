#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sudo install -m 0755 "$DOTFILES/system/vtcolors/vtcolors-apply" /usr/local/bin/vtcolors-apply
sudo install -m 0644 "$DOTFILES/system/vtcolors/vtcolors.service" /etc/systemd/system/vtcolors.service
sudo install -m 0644 "$DOTFILES/system/vtcolors/vtcolors.path" /etc/systemd/system/vtcolors.path
sudo systemctl daemon-reload
sudo systemctl enable --now vtcolors.path
sudo systemctl start vtcolors.service
sudo systemctl enable vtcolors.service
