#!/bin/bash
# Restarts the desktop conky widgets whenever monitors are plugged/unplugged.
#
# conky computes its own_window position (alignment = top_right, etc.) once at
# startup and never recomputes it on RANDR changes. If a widget was placed
# relative to an external monitor that then gets unplugged, its window stays
# at the old (now off-screen) coordinates until conky is restarted. Mutter
# emits MonitorsChanged on every hotplug, so we watch that and restart.

SERVICES=(
    fleet-status-conky.service
    elysium-conky.service
    linear-widget-conky.service
    claude-usage-conky.service
    weather-conky.service
    now-playing-conky.service
    calendar-conky.service
    github-prs-conky.service
    cmf-buds-conky.service
    devices-conky.service
    agenda-conky.service
    wing-left-conky.service
    wing-right-conky.service
    clock-conky.service
)

gdbus monitor --session --dest org.gnome.Mutter.DisplayConfig \
    --object-path /org/gnome/Mutter/DisplayConfig 2>/dev/null |
while read -r line; do
    case "$line" in
        *MonitorsChanged*)
            # Debounce: give Mutter/xrandr a moment to settle the new layout
            # before conky re-reads screen geometry on restart.
            sleep 2
            # try-restart: widgets switched off on this machine stay off.
            systemctl --user try-restart "${SERVICES[@]}"
            ;;
    esac
done
