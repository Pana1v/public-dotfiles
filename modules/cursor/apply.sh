#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/cursor"
F="$MOD/files"

link_file "$F/settings.json" "$HOME/.config/Cursor/User/settings.json"
link_file "$F/mcp.json" "$HOME/.cursor/mcp.json"
link_file "$F/cli-config.json" "$HOME/.cursor/cli-config.json"
# Same generated "Rice" colour theme as VS Code.
rice_vscode_theme cursor "$HOME/.cursor/extensions"
for f in "$F"/rules/*.mdc; do
    link_file "$f" "$HOME/.cursor/rules/$(basename "$f")"
done

if ! command -v cursor >/dev/null; then
    warn "cursor not installed (apps-desktop module); skipping extensions"
    exit 0
fi
installed="$(cursor --list-extensions)"
# One cursor call for all missing extensions: each call costs a full CLI startup.
args=()
while read -r ext; do
    grep -qix "$ext" <<< "$installed" && continue
    args+=(--install-extension "$ext")
done < <(read_list "$MOD/extensions.txt")
[ "${#args[@]}" -eq 0 ] && { log "ok      extensions"; exit 0; }
run cursor "${args[@]}"
