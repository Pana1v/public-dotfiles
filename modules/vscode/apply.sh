#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/vscode"
U="$HOME/.config/Code/User"

link_file "$MOD/files/settings.json" "$U/settings.json"
link_file "$MOD/files/mcp.json" "$U/mcp.json"
# Local "Mono Rice", "Tron Rice" and "Ares Rice" colour themes (used by those rice palettes). Symlinked so
# edits land in the repo; VS Code finds it by scanning the extensions folder.
link_file "$MOD/files/mono-rice-theme" "$HOME/.vscode/extensions/local.mono-rice-0.1.0"
link_file "$MOD/files/tron-rice-theme" "$HOME/.vscode/extensions/local.tron-rice-0.1.0"
link_file "$MOD/files/ares-rice-theme" "$HOME/.vscode/extensions/local.ares-rice-0.1.0"

if ! command -v code >/dev/null; then
    warn "code not installed (apps-desktop module); skipping extensions"
    exit 0
fi
installed="$(code --list-extensions)"
# One code call for all missing extensions: each call costs a full CLI startup.
args=()
while read -r ext; do
    grep -qix "$ext" <<< "$installed" && continue
    args+=(--install-extension "$ext")
done < <(read_list "$MOD/extensions.txt")
[ "${#args[@]}" -eq 0 ] && { log "ok      extensions"; exit 0; }
run code "${args[@]}"
