#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/gnome"

if [ -d "$MOD/files/backgrounds" ]; then
    copy_tree "$MOD/files/backgrounds" "$HOME/.local/share/backgrounds"
fi

# pop-shell float rules (Rofi, desktop icons). Seeded once, never overwritten:
# pop-shell owns the file after that and adds rules from its exceptions dialog.
# Loaded only at login.
copy_tree "$MOD/files/pop-shell" "$HOME/.config/pop-shell" --ignore-existing

# Off Zorin, swap Zorin theme and extension names for their stand-ins
# (zorin-deps.txt). Enabled/disabled extensions are left to gnome-extensions,
# which checks each one against this GNOME version first.
DISTRO_SED="$(distro_dconf_sed)"

# dconf load merges: keys absent from the dump keep their current value.
while read -r name path; do
    if [ "$name" = zorin ] && ! is_zorin; then
        log "skip    $path (Zorin only)"
        continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
        log "[dry] dconf load $path < dconf/$name.ini"
        continue
    fi
    # Public dump, then its private sections (paired phone, weather location).
    for f in "$MOD/dconf/$name.ini" "$PRIVATE/gnome/dconf/$name.ini"; do
        [ -f "$f" ] || continue
        sed -e "s#@HOME@#$HOME#g" -e '/^\(enabled\|disabled\)-extensions=/d' "$f" |
            sed -e "${DISTRO_SED:-}" | dconf load "$path"
    done
    log "dconf   $path"
done < <(read_list "$MOD/paths.txt")
