#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/fonts-cursors"

apt_install "$MOD/packages.apt"
for f in "$MOD"/files/fonts/*; do
    link_file "$f" "$HOME/.local/share/fonts/$(basename "$f")"
done
link_file "$MOD/files/icons/oreo-pink-cursors" "$HOME/.local/share/icons/oreo-pink-cursors"
run fc-cache -f
