#!/bin/bash
# Starts a conky widget scaled to the monitor it lands on.
#   usage: start-widget.sh <path to base .conf>
#
# Without xinerama_head, conky aligns windows on head 0, the first entry of
# `xrandr --listmonitors` (the primary). Scale follows that monitor's height:
# 2160p -> 1.4 (Elysium's tuned 4K value), <= 1543p -> 1.0.
# Window geometry is scaled here, since conky reads it once at startup;
# drawing is scaled in Lua via CONKY_SCALE.
#
# The base conf is written at scale 1.0. gap_x / gap_y are measured from
# EDGE_X / TOP_Y (screen margin, panel clearance), which stay unscaled.

set -euo pipefail

BASE_CONF="$1"
EDGE_X=10
TOP_Y=60
REF_HEIGHT=1543

# Monitor lines look like: " 0: +*DP-1 3840/700x2160/390+1920+0  DP-1".
MON_HEIGHT=$(xrandr --listmonitors | awk 'NR == 2 { split($3, a, /[\/x+]/); print a[3] }')

export CONKY_SCALE=$(awk -v h="$MON_HEIGHT" -v r="$REF_HEIGHT" \
    'BEGIN { s = h / r; if (s < 1) s = 1; printf "%.2f", s }')

scale() {
    awk -v v="$1" -v s="$CONKY_SCALE" 'BEGIN { printf "%d", v * s + 0.5 }'
}

W=$(sed -n 's/^\s*minimum_width\s*=\s*\([0-9]*\).*/\1/p' "$BASE_CONF")
H=$(sed -n 's/^\s*minimum_height\s*=\s*\([0-9]*\).*/\1/p' "$BASE_CONF")
GAP_X=$(sed -n 's/^\s*gap_x\s*=\s*\([0-9]*\).*/\1/p' "$BASE_CONF")
GAP_Y=$(sed -n 's/^\s*gap_y\s*=\s*\([0-9]*\).*/\1/p' "$BASE_CONF")

OUT_DIR="${XDG_RUNTIME_DIR:-/tmp}/conky"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(basename "$BASE_CONF")"

# Default geometry: the base conf scaled as a whole.
PX_W=$(scale "$W") PX_H=$(scale "$H")
PX_X=$((EDGE_X + $(scale $((GAP_X - EDGE_X)))))
PX_Y=$((TOP_Y + $(scale $((GAP_Y - TOP_Y)))))

# Wings + deck + clock fill the screen, so their geometry comes from the
# monitor size instead (any resolution or aspect):
#   wings     full height, WING_W wide at each edge
#   decks     the gap between the wings; top under the panel, bottom above the dock
#   clock     centred between the decks, shrunk (own CONKY_SCALE) if the gap is short
# Dock clearance differs per dock size: CONKY_DOCK_CLEAR in local.env overrides.
LOCAL_ENV="$HOME/.config/dotfiles/local.env"
DOCK_CLEAR=$(sed -n 's/^\s*CONKY_DOCK_CLEAR\s*=\s*["'"'"']\?\([0-9]*\).*/\1/p' "$LOCAL_ENV" 2>/dev/null | tail -1)
DOCK_CLEAR=${DOCK_CLEAR:-$(scale 92)}
MON_WIDTH=$(xrandr --listmonitors | awk 'NR == 2 { split($3, a, /[\/x+]/); print a[1] }')
WING_TOP=46 WING_BOTTOM=24
WING_W=$(scale 500) DECK_H=$(scale 150) SIDE_GAP=$(scale 12)
case "$(basename "$BASE_CONF")" in
    wing_left.conf|wing_right.conf)
        PX_H=$((MON_HEIGHT - WING_TOP - WING_BOTTOM)) PX_Y=$WING_TOP ;;
    deck_top.conf|deck_bottom.conf)
        PX_W=$((MON_WIDTH - 2 * WING_W - 2 * SIDE_GAP)) PX_H=$DECK_H PX_X=0
        if [ "$(basename "$BASE_CONF")" = deck_top.conf ]; then
            PX_Y=$TOP_Y
        else
            PX_Y=$((MON_HEIGHT - DOCK_CLEAR - DECK_H))
        fi ;;
    clock.conf)
        GAP_TOP=$((TOP_Y + DECK_H)) GAP_BOTTOM=$((MON_HEIGHT - DOCK_CLEAR - DECK_H))
        AVAIL=$((GAP_BOTTOM - GAP_TOP))
        SIZE=$(( $(scale "$H") < AVAIL - 10 ? $(scale "$H") : AVAIL - 10 ))
        export CONKY_SCALE=$(awk -v s="$SIZE" -v h="$H" 'BEGIN { printf "%.3f", s / h }')
        PX_W=$SIZE PX_H=$SIZE PX_X=0 PX_Y=$((GAP_TOP + (AVAIL - SIZE) / 2)) ;;
esac

# conky 1.22 (Ubuntu 26.04) no longer expands ~ in lua_load, so the widget
# loads no script and draws nothing. Spell out $HOME instead.
sed -e "s#'~/#'$HOME/#g" \
    -e "s/^\(\s*minimum_width\s*=\s*\)[0-9]*/\1$PX_W/" \
    -e "s/^\(\s*minimum_height\s*=\s*\)[0-9]*/\1$PX_H/" \
    -e "s/^\(\s*gap_x\s*=\s*\)[0-9]*/\1$PX_X/" \
    -e "s/^\(\s*gap_y\s*=\s*\)[0-9]*/\1$PX_Y/" \
    "$BASE_CONF" > "$OUT"

exec /usr/bin/conky -c "$OUT"
