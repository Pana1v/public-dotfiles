#!/bin/bash
# Starts Conky on the external DP-1 when connected, internal otherwise.
# Re-run after plugging/unplugging a monitor to reposition.

CONKY_DIR="$HOME/.config/conky/Elysium"
TMP_CONF="/tmp/elysium_active.conf"

# Compute canvas size: card = floor(CARD * SCALE + 0.5), gap = 8
# width  = 2*card + gap
# height = 3*card + 2*gap
if xrandr --query | grep -q "^DP-1 connected"; then
    XINERAMA_HEAD=1
    export CONKY_SCALE=1.4
    MIN_W=384   # floor(134*1.4+0.5)=188 → 188+8+188
    MIN_H=580   # 188+8+188+8+188
else
    XINERAMA_HEAD=0
    export CONKY_SCALE=1.0
    MIN_W=276   # 134+8+134
    MIN_H=418   # 134+8+134+8+134
fi

cat > "$TMP_CONF" << EOF
conky.config = {
    own_window           = true,
    own_window_type      = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value  = 0,
    own_window_hints     = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_class     = 'Conky',
    own_window_title     = 'Elysium',

    alignment     = 'top_left',
    gap_x         = 10,
    gap_y         = 60,
    xinerama_head = ${XINERAMA_HEAD},

    minimum_width  = ${MIN_W},
    minimum_height = ${MIN_H},

    update_interval = 1.0,
    total_run_times  = 0,

    lua_load           = '${CONKY_DIR}/elysium.lua',
    lua_draw_hook_post = 'main',

    background    = false,
    double_buffer = true,
    draw_shades   = false,
    draw_borders  = false,
    draw_outline  = false,

    use_xft       = true,
    font          = 'Roboto:size=1',
    out_to_x      = true,
    extra_newline = false,
}

conky.text = [[]]
EOF

pkill -x conky 2>/dev/null
sleep 0.5
conky -c "$TMP_CONF" &
