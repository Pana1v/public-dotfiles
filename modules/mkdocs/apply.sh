#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"

# mkdocs-material runs through uvx on demand (apps-dev installs uv), so nothing else is installed
link_file "$DOTFILES/modules/mkdocs/files/mk-please" "$HOME/.local/bin/mk-please"
