#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/apps-desktop"

apt_install "$MOD/packages.apt"
snap_install "$MOD/packages.snap"
flatpak_install "$MOD/packages.flatpak"

# Launcher overrides: VS Code Wayland hint, Foxglove GPU flags.
for f in "$MOD"/files/applications/*.desktop; do
    link_file "$f" "$HOME/.local/share/applications/$(basename "$f")"
done
