#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sudo install -m 0644 "$DOTFILES/system/polkit/50-noctalia-greeter-sync.rules" /etc/polkit-1/rules.d/50-noctalia-greeter-sync.rules
