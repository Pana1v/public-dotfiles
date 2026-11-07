#!/usr/bin/env bash
# One skill set for both agents. private/skills/<name>/SKILL.md is the source;
# each skill is symlinked into ~/.claude/skills and ~/.cursor/skills, so an
# edit from either tool lands in the private repo.
#
# Claude Code also syncs skills from claude.ai into ~/.claude/skills/synced/.
# A skill that arrives that way is not linked a second time for Claude (it
# would show up twice); Cursor does not read the synced folder, so it always
# gets the link. ./snapshot.sh copies synced skills back into private/skills.
set -euo pipefail
. "$DOTFILES/lib/common.sh"
SRC="$PRIVATE/skills"

if [ ! -d "$SRC" ] || [ -z "$(ls -A "$SRC" 2>/dev/null)" ]; then
    warn "no skills: private repo not checked out (git submodule update --init private)"
    exit 0
fi

synced() { compgen -G "$HOME/.claude/skills/synced/*/$1/SKILL.md" >/dev/null; }

for dir in "$SRC"/*/; do
    name="$(basename "$dir")"
    [ -f "$dir/SKILL.md" ] || continue
    if synced "$name"; then
        log "synced  ~/.claude/skills/$name (claude.ai sync provides it)"
    else
        link_file "${dir%/}" "$HOME/.claude/skills/$name"
    fi
    link_file "${dir%/}" "$HOME/.cursor/skills/$name"
done
