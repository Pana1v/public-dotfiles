#!/usr/bin/env bash
# Push this machine's changes: snapshot, commit, push. Private first, so the
# public repo never points at a private commit that is not on GitHub yet.
#
#   ./sync.sh                     snapshot, show what changed, ask, commit, push
#   ./sync.sh -m "rice: tweak"    same, with your commit message
#   ./sync.sh --no-snapshot       skip snapshot.sh (only commit what is there)
#   ./sync.sh -y                  do not ask
#   ./sync.sh --pull              only pull both repos (other machine pushed)
set -euo pipefail
DOTFILES="$(cd "$(dirname "$0")" && pwd)"
PRIVATE="$DOTFILES/private"
MSG="sync: $(hostname) $(date +%F)"
SNAPSHOT=1
YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        -m)            MSG="$2"; shift ;;
        --no-snapshot) SNAPSHOT=0 ;;
        -y)            YES=1 ;;
        --pull)
            git -C "$DOTFILES" pull --ff-only
            [ -f "$PRIVATE/private.env" ] && git -C "$PRIVATE" pull --ff-only origin main
            git -C "$DOTFILES" submodule update --init private 2>/dev/null || true
            exit 0 ;;
        -h|--help)     sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
        *)             echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

[ "$SNAPSHOT" = 1 ] && "$DOTFILES/snapshot.sh"

has_changes() { [ -n "$(git -C "$1" status --porcelain)" ]; }

show() {
    printf '\n\033[1m%s\033[0m\n' "$1"
    git -C "$2" status --short | head -40
}

private_dirty=0 public_dirty=0
if [ -f "$PRIVATE/private.env" ] && has_changes "$PRIVATE"; then
    private_dirty=1
    show "private (Pana1v/dotfiles-private)" "$PRIVATE"
fi
has_changes "$DOTFILES" && { public_dirty=1; show "public (Pana1v/public-dotfiles)" "$DOTFILES"; }
[ "$private_dirty$public_dirty" = 00 ] && { echo "nothing to sync"; exit 0; }

if [ "$YES" = 0 ]; then
    printf '\ncommit as "%s" and push? [y/N] ' "$MSG"
    read -r ok
    [ "$ok" = y ] || [ "$ok" = Y ] || { echo "stopped, nothing committed"; exit 1; }
fi

if [ "$private_dirty" = 1 ]; then
    # The submodule checkout is detached by default; commit on main.
    git -C "$PRIVATE" checkout -q main 2>/dev/null || git -C "$PRIVATE" checkout -q -b main
    git -C "$PRIVATE" add -A
    git -C "$PRIVATE" commit -q -m "$MSG"
    git -C "$PRIVATE" push -q origin main
    echo "pushed private"
fi

# Re-check: a private commit moves the submodule pointer in the public repo.
if has_changes "$DOTFILES"; then
    git -C "$DOTFILES" add -A
    "$DOTFILES/lib/leak-check.sh" || { git -C "$DOTFILES" reset -q; exit 1; }
    git -C "$DOTFILES" commit -q -m "$MSG"
    git -C "$DOTFILES" push -q
    echo "pushed public"
fi
