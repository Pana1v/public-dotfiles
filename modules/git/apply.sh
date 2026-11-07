#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
F="$DOTFILES/modules/git/files"

link_file "$F/gitconfig" "$HOME/.gitconfig"
link_file "$F/gitignore_global" "$HOME/.config/git/ignore"

# Identity (name, email) is private. Public clones get an editable copy of the
# example, never overwritten once it exists.
ID="$HOME/.config/git/identity.gitconfig"
if has_private; then
    link_file "$PRIVATE/git/identity.gitconfig" "$ID"
elif [ -e "$ID" ]; then
    log "ok      $ID"
else
    run install -D -m 644 "$F/identity.example.gitconfig" "$ID"
    warn "set your name and email in $ID"
fi
