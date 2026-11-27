#!/usr/bin/env bash
# Rofi script mode: world clock. Empty query shows now in IST, Amsterdam (robot
# site) and UTC. Type "14:30" (read in the local zone), "14:30 cet", or just a
# zone ("tokyo", "America/New_York") to add it. Enter on a row copies it.

ZONES=(Asia/Kolkata Europe/Amsterdam UTC)
ROW_FORMAT='+%a %d %b  %H:%M  %Z'
TIME_RE='^[0-9]{1,2}:[0-9]{2}$'

# Abbreviations that are not IANA names.
alias_zone() {
    case "${1,,}" in
        ist) echo Asia/Kolkata ;;
        cet|cest) echo Europe/Amsterdam ;;
        utc) echo UTC ;;
    esac
}

# zone <word>: IANA name from an alias, an exact name or a partial match.
# Output only ever comes from the zone list, so it is safe inside date -d.
zone() {
    alias_zone "$1" | grep . && return
    timedatectl list-timezones | grep -iF -m1 -- "$1"
}

# epoch <HH:MM> <zone>: that wall-clock time today, in that zone.
epoch() { date -d "TZ=\"$2\" $1" +%s; }

row() {
    local text
    text="$(printf '%-17s %s' "${1##*/}" "$(TZ=$1 date -d "@$2" "$ROW_FORMAT")")"
    printf '%s\0icon\x1fpreferences-system-time\x1finfo\x1f%s\n' "$text" "$text"
}

selftest() {
    [ "$(zone ist)" = Asia/Kolkata ] || { echo zone ist; exit 1; }
    [ "$(zone tokyo)" = Asia/Tokyo ] || { echo zone tokyo; exit 1; }
    local e
    e="$(epoch 12:00 UTC)"
    [ "$(TZ=Asia/Kolkata date -d "@$e" +%H:%M)" = 17:30 ] || { echo epoch UTC to IST; exit 1; }
    [ "$(TZ=Asia/Tokyo date -d "@$e" +%H:%M)" = 21:00 ] || { echo epoch UTC to JST; exit 1; }
    echo ok
}

[ -n "${SELFTEST:-}" ] && { selftest; exit; }

printf '\0prompt\x1fTIME\n'
printf '\0markup-rows\x1ffalse\n'

if [ -n "${ROFI_INFO:-}" ]; then
    printf '%s' "$ROFI_INFO" | xclip -selection clipboard
    exit 0
fi

at="" source="" extra=()
for word in ${1:-}; do
    if [[ $word =~ $TIME_RE ]]; then
        at="$word"
        continue
    fi
    z="$(zone "$word")"
    if [ -z "$z" ]; then
        printf '\0message\x1funknown zone: %s\n' "$word"
        exit 0
    fi
    source="$z"
    [[ " ${ZONES[*]} " == *" $z "* ]] || extra+=("$z")
done

# A time without a zone means the machine's own zone.
source="${source:-$(timedatectl show -p Timezone --value)}"
when="$(date +%s)"
label="now"
[ -n "$at" ] && { when="$(epoch "$at" "$source")"; label="$at $source"; }

printf '\0message\x1f%s\n' "$label"
for z in "${ZONES[@]}" "${extra[@]}"; do
    row "$z" "$when"
done
