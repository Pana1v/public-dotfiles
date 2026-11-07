#!/usr/bin/env bash
# Refuse a public commit that adds a private value. Patterns come from the
# private repo (private/leak-patterns.txt), so the list itself stays private.
#
#   lib/leak-check.sh            check the staged changes (pre-commit hook)
#   lib/leak-check.sh --tree     check every tracked file
set -euo pipefail
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
PATTERNS="$DOTFILES/private/leak-patterns.txt"
[ -f "$PATTERNS" ] || exit 0

re="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PATTERNS" | paste -sd'|')"
[ -n "$re" ] || exit 0

if [ "${1:-}" = --tree ]; then
    hits="$(git -C "$DOTFILES" grep -nIE "$re" -- . ':!private' || true)"
else
    hits="$(git -C "$DOTFILES" diff --cached -U0 --no-color -- . ':!private' |
        grep -E '^\+' | grep -v '^+++' | grep -E "$re" || true)"
fi
if [ -n "$hits" ]; then
    echo "leak-check: private values in the public repo, commit refused:" >&2
    printf '%s\n' "$hits" | head -20 >&2
    echo "move them into private/ (see README, Private layer)" >&2
    exit 1
fi
