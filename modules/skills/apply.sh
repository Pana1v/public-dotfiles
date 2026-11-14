#!/usr/bin/env bash
# One skill set for every agent. private/skills/<name>/SKILL.md is the source;
# each skill is symlinked into ~/.claude/skills, ~/.cursor/skills and
# ~/.agents/skills (read by Qwen Code and Happy Agent), so an edit from any
# tool lands in the private repo. Names listed in private/skills/.exclude-agents
# are skipped for ~/.agents/skills.
#
# private/agents/AGENTS.md is the global instruction file for Qwen Code
# (~/.qwen/QWEN.md) and Happy Agent (~/happy/config/AGENTS.md).
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

excluded() { grep -qxF "$1" "$SRC/.exclude-agents" 2>/dev/null; }

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
    if excluded "$name"; then
        log "skip    ~/.agents/skills/$name (.exclude-agents)"
    else
        link_file "${dir%/}" "$HOME/.agents/skills/$name"
    fi
done

AGENTS_MD="$PRIVATE/agents/AGENTS.md"
if [ -f "$AGENTS_MD" ]; then
    link_file "$AGENTS_MD" "$HOME/.qwen/QWEN.md"
    link_file "$AGENTS_MD" "$HOME/happy/config/AGENTS.md"
fi
