#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/obsidian"
REPO="$(conf_get OBSIDIAN_REPO)"
VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/ObsidianNotes}"

command -v flatpak >/dev/null || run sudo apt-get install -y flatpak
flatpak_install "$MOD/packages.flatpak"

# The vault itself is a private repo (OBSIDIAN_REPO in private.env or
# local.env). Without one, an empty vault folder gets the config below.
if [ ! -d "$VAULT/.git" ] && [ -n "$REPO" ]; then
    run git clone "$REPO" "$VAULT" || warn "could not clone $REPO; using an empty vault"
fi
run mkdir -p "$VAULT"

# The vault repo also tracks .obsidian, so it wins: only fill what is missing.
# Plugin data.json (settings, some with API keys) is never shipped; each
# plugin starts on defaults until configured.
copy_tree "$MOD/files/obsidian" "$VAULT/.obsidian" --ignore-existing
