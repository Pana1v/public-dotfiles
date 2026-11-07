#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/conky"
UNITS="$HOME/.config/systemd/user"

apt_install "$MOD/packages.apt"
link_file "$MOD/files/conky" "$HOME/.config/conky"

# Units are copied: systemd treats symlinked unit files as "linked" units,
# which enable/disable handle differently.
run mkdir -p "$UNITS"
names=()
for f in "$MOD"/files/systemd/*.service; do
    names+=("$(basename "$f")")
    if cmp -s "$f" "$UNITS/$(basename "$f")"; then
        log "ok      $UNITS/$(basename "$f")"
        continue
    fi
    run install -m 644 "$f" "$UNITS/"
    log "install $UNITS/$(basename "$f")"
done

if ! systemctl --user show-environment >/dev/null 2>&1; then
    warn "no user systemd session; enable later: systemctl --user enable --now ${names[*]}"
    exit 0
fi
run systemctl --user daemon-reload

# Which widgets run is a per-machine choice, kept outside the repo in
# ~/.config/dotfiles/local.env, e.g. CONKY_WIDGETS="elysium" on a personal
# desktop. Unset means the wings plus the ops deck (fleet strip above the
# clock, Linear strip below it). The old single-card widgets draw in the same
# screen spots, so running them with the wings overlaps.
: "${LOCAL_ENV:=$HOME/.config/dotfiles/local.env}"
# shellcheck disable=SC1090
[ -f "$LOCAL_ENV" ] && . "$LOCAL_ENV"
ALL_WIDGETS="elysium claude fleet linear calendar weather nowplaying audio devices agenda github wings deck"
WIDGETS="${CONKY_WIDGETS:-wings deck}"

widget_units() {
    case "$1" in
        elysium)    echo elysium-conky.service ;;
        claude)     echo claude-usage-conky.service ;;
        fleet)      echo fleet-status-conky.service fleet-ping.service ;;
        linear)     echo linear-widget-conky.service ;;
        calendar)   echo calendar-conky.service ;;
        weather)    echo weather-conky.service ;;
        nowplaying) echo now-playing-conky.service ;;
        audio)      echo cmf-buds-conky.service ;;
        devices)    echo devices-conky.service ;;
        agenda)     echo agenda-conky.service ;;
        wings)      echo wing-left-conky.service wing-right-conky.service clock-conky.service ;;
        deck)       echo deck-top-conky.service deck-bottom-conky.service fleet-ping.service ;;
        github)     echo github-prs-conky.service ;;
    esac
}

on=(conky-monitor-watch.service) off=()
for w in $ALL_WIDGETS; do
    # shellcheck disable=SC2207
    if [[ " $WIDGETS " == *" $w "* ]]; then on+=($(widget_units "$w")); else off+=($(widget_units "$w")); fi
done
# A unit shared by an enabled widget (fleet-ping: fleet card and deck) stays on.
keep=()
for u in "${off[@]}"; do [[ " ${on[*]} " == *" $u "* ]] || keep+=("$u"); done
off=("${keep[@]}")
# These widgets only read snapshots that conky-feeds writes to ~/.cache/conky.
if [[ " $WIDGETS " =~ \ (weather|nowplaying|audio|devices|agenda|github|wings|deck)\  ]]; then on+=(conky-feeds.service); else off+=(conky-feeds.service); fi
log "widgets $WIDGETS"
run systemctl --user enable --now "${on[@]}"
# Windows read the widget list and PROFILE only at start, so running ones restart.
run systemctl --user try-restart conky-feeds.service deck-top-conky.service deck-bottom-conky.service wing-left-conky.service wing-right-conky.service clock-conky.service
[ "${#off[@]}" -eq 0 ] || run systemctl --user disable --now "${off[@]}"
