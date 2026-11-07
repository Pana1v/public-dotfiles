#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
DIR="$HOME/.config/secrets"

run mkdir -p "$DIR"
run chmod 700 "$DIR"
for f in "$DOTFILES"/secrets/*.env.example; do
    dst="$DIR/$(basename "$f" .example)"
    if [ -f "$dst" ]; then
        log "ok      $dst"
        continue
    fi
    run install -m 600 "$f" "$dst"
    warn "fill in $dst"
done
