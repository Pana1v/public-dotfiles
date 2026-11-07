#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
F="$DOTFILES/modules/terminator/files"

command -v terminator >/dev/null || run sudo apt-get install -y terminator
link_file "$F/config" "$HOME/.config/terminator/config"
for f in "$F"/plugins/*.py; do
    link_file "$f" "$HOME/.config/terminator/plugins/$(basename "$f")"
done

# Default terminal for Ctrl+Alt+T, Files' "Open in Terminal" and .desktop
# Terminal=true apps: GNOME launches them through xdg-terminal-exec, which
# takes the first entry of this list (the user's list beats the distro's).
link_file "$F/xdg-terminals.list" "$HOME/.config/xdg-terminals.list"
# x-terminal-emulator, for scripts that still call it.
if [ "$(readlink -f /etc/alternatives/x-terminal-emulator)" != /usr/bin/terminator ]; then
    run sudo update-alternatives --set x-terminal-emulator /usr/bin/terminator
fi

