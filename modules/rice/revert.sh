#!/usr/bin/env bash
# Restore the pre-rice look. Values captured 2026-10-02.
set -euo pipefail
DOTFILES="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../lib/common.sh
. "$DOTFILES/lib/common.sh"
# ZorinBlue-Dark on Zorin, its stand-in elsewhere (zorin-deps.txt).
OLD_THEME="$(distro_name theme ZorinBlue-Dark)"
gsettings set org.gnome.desktop.interface gtk-theme "$OLD_THEME"
gsettings set org.gnome.desktop.interface icon-theme "$OLD_THEME"
gsettings set org.gnome.shell.extensions.user-theme name "$OLD_THEME"
gsettings set org.gnome.desktop.background picture-uri "file://$HOME/Pictures/elvis-bekmanis-g9qwoPiS0nY-unsplash.jpg"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/Pictures/elvis-bekmanis-g9qwoPiS0nY-unsplash.jpg"
rm -f "$HOME/.config/gtk-4.0/gtk.css" "$HOME/.config/rofi/config.rasi" "$HOME/.config/rofi/rice.rasi" "$HOME/.config/rofi/scripts"
rm -rf "$HOME/.config/kdeglobals" "$HOME/.config/qt5ct" "$HOME/.config/environment.d/qt-theme.conf" "$HOME/.local/share/applications/org.kde.dolphin.desktop"
sed -i 's/"workbench.colorTheme": "[^"]*"/"workbench.colorTheme": "GitHub Dark"/' "$HOME/.config/Code/User/settings.json"
echo "Manual: Claude theme back to custom:matrix in ~/.claude/settings.json; Obsidian appearance.json; bashrc starship/fzf lines; tmux.conf source line"
TB=org.gnome.shell.extensions.zorin-taskbar
if gsettings list-keys $TB >/dev/null 2>&1; then
    gsettings set $TB panel-margin 4
    gsettings set $TB global-border-radius 3
    gsettings set $TB trans-use-custom-opacity false
    gsettings set $TB trans-use-dynamic-opacity false
    gsettings set $TB trans-use-border false
    gsettings set $TB trans-border-use-custom-color false
fi
sed -i 's/^color_theme = .*/color_theme = "Default"/; s/^theme_background = .*/theme_background = True/' "$HOME/.config/btop/btop.conf"
