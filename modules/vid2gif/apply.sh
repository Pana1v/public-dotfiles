#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/vid2gif"
REPO="$(conf_get VID2GIF_REPO)"
REPO="${REPO:-https://github.com/Pana1v/vid2gif.git}"
DIR="$HOME/Videos/vid2gif"
PLUGINS="$HOME/.local/share/gstreamer-1.0/plugins"

apt_install "$MOD/packages.apt"

# gtk4paintablesink is packaged from Ubuntu 26.04. 24.04 lacks it, so ship a
# stripped build of gst-plugins-rs gtk4 0.12.11 against noble's GStreamer 1.24.
if [[ "$(apt-cache policy gstreamer1.0-gtk4)" == *"Candidate: "[0-9]* ]]; then
    dpkg -s gstreamer1.0-gtk4 >/dev/null 2>&1 || run sudo apt-get install -y gstreamer1.0-gtk4
elif ! cmp -s "$MOD/files/gstreamer/libgstgtk4.so" "$PLUGINS/libgstgtk4.so"; then
    run install -D -m 755 "$MOD/files/gstreamer/libgstgtk4.so" "$PLUGINS/libgstgtk4.so"
    log "install $PLUGINS/libgstgtk4.so"
fi

if [ ! -d "$DIR/.git" ]; then
    run git clone "$REPO" "$DIR"
fi
run sh "$DIR/install.sh"
