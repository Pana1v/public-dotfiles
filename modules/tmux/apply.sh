#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"

link_file "$DOTFILES/modules/tmux/files/tmux.conf" "$HOME/.tmux.conf"
