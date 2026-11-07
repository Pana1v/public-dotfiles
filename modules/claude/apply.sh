#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
REPO="$(conf_get CLAUDE_CONFIG_REPO)"
DIR="$HOME/Documents/claude-config"

# Optional extra config repo (CLAUDE_CONFIG_REPO in private.env or local.env).
# Skipped when unset or unreachable; skills come from the skills module.
if [ -z "$REPO" ]; then
    log "skip    claude-config (CLAUDE_CONFIG_REPO not set)"
elif [ -d "$DIR/.git" ] || run git clone "$REPO" "$DIR"; then
    # --minimal: Claude files only. conky lives in this repo's conky module.
    [ -f "$DIR/install.sh" ] && run bash "$DIR/install.sh" --link --minimal
else
    warn "could not clone $REPO (log in to gh as its owner); skipped"
fi

# install.sh silently skips MCP servers and plugins without the CLI.
command -v claude >/dev/null || warn "claude CLI missing: apply apps-dev, then rerun this module"

# Status line script: also writes ~/.claude/rate-cache.json for the conky Claude panel.
# Needs "statusLine": {"type": "command", "command": "~/.claude/statusline.sh"} in settings.json.
link_file "$DOTFILES/modules/claude/files/statusline.sh" "$HOME/.claude/statusline.sh"
