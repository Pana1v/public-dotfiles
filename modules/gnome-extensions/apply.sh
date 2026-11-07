#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/gnome-extensions"
DST="$HOME/.local/share/gnome-shell/extensions"

# Copied, not linked: the Extension Manager updates extensions in place.
copy_tree "$MOD/files" "$DST"

# Compiled schemas are not versioned; rebuild them.
for s in "$DST"/*/schemas; do
    [ -d "$s" ] && run glib-compile-schemas "$s"
done

# GNOME refuses extensions whose metadata does not list its major version,
# so a newer Ubuntu (newer GNOME) silently drops them. Leave those out and
# name them instead.
SHELL_MAJOR="$(gnome-shell --version 2>/dev/null | grep -o '[0-9]\+' | head -1 || true)"
find_meta() {
    local d
    for d in "$MOD/files" "$DST" /usr/share/gnome-shell/extensions; do
        [ -f "$d/$1/metadata.json" ] && { echo "$d/$1/metadata.json"; return 0; }
    done
    return 1
}
supports_shell() {
    python3 -c 'import json, sys
majors = [v.split(".")[0] for v in json.load(open(sys.argv[1]))["shell-version"]]
sys.exit(sys.argv[2] not in majors)' "$1" "$SHELL_MAJOR"
}

# Zorin UUIDs become their stand-ins elsewhere (zorin-deps.txt).
uuids() {
    local uuid
    while read -r uuid; do
        uuid="$(distro_name ext "$uuid")"
        [ "$uuid" = - ] || echo "$uuid"
    done < <(read_list "$1")
}

enabled=()
while read -r uuid; do
    if ! meta="$(find_meta "$uuid")"; then
        # Installed later by a package (e.g. gsconnect) or not at all.
        warn "$uuid not installed yet, enabling anyway"
    elif [ -n "$SHELL_MAJOR" ] && ! supports_shell "$meta"; then
        warn "$uuid does not list GNOME $SHELL_MAJOR, left disabled"
        continue
    fi
    enabled+=("'$uuid'")
done < <(uuids "$MOD/enabled.txt" | awk '!seen[$0]++')

# System extensions (Ubuntu's are on through the session mode) can only be
# turned off by listing them here.
disabled=()
while read -r uuid; do
    disabled+=("'$uuid'")
done < <(uuids "$MOD/disabled.txt")

run gsettings set org.gnome.shell enabled-extensions "[$(IFS=,; echo "${enabled[*]}")]"
run gsettings set org.gnome.shell disabled-extensions "[$(IFS=,; echo "${disabled[*]}")]"
warn "log out and back in to load new extensions"
