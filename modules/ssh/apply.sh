#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"

# Host aliases are private (robot IPs, tailnet). Public clones get an example.
CONF="$(private_or ssh/config "$DOTFILES/modules/ssh/files/config.example")"
has_private || warn "private repo not checked out: linking the example ssh config"

# ssh follows the symlink and refuses a group-writable config.
run chmod 600 "$CONF"
run mkdir -p "$HOME/.ssh"
run chmod 700 "$HOME/.ssh"
link_file "$CONF" "$HOME/.ssh/config"
[ -f "$HOME/.ssh/id_ed25519" ] || warn "no ~/.ssh/id_ed25519: copy your key or ssh-keygen -t ed25519"
