#!/bin/bash
# One line per MPRIS player, tab-separated:
#   status, player, artist, title, position_us, length_us
# Kept out of the conky ${exec} line because conky would end the
# variable at the first "}" of playerctl's {{...}} format tokens.

if ! command -v playerctl >/dev/null; then
    echo "MISSING"
    exit 0
fi

# Empty output would make the widget keep showing the last track.
out=$(playerctl -a metadata --format \
    $'{{status}}\t{{playerName}}\t{{artist}}\t{{title}}\t{{position}}\t{{mpris:length}}' 2>/dev/null)
echo "${out:-NONE}"
