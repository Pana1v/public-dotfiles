#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
F="$DOTFILES/modules/shell/files"

for f in bashrc bash_aliases profile inputrc; do
    link_file "$F/$f" "$HOME/.$f"
done
link_file "$F/banner.py" "$HOME/.config/bash/banner.py"
