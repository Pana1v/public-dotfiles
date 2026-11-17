#!/bin/bash
# Restarts the desktop conky widgets whenever monitors are plugged/unplugged.
#
# conky computes its own_window position (alignment = top_right, etc.) once at
# startup and never recomputes it on RANDR changes. If a widget was placed
# relative to an external monitor that then gets unplugged, its window stays
# at the old (now off-screen) coordinates until conky is restarted. Mutter
# emits MonitorsChanged on every hotplug, so we watch that and restart.

# A pattern, not a list: a hardcoded list went stale when the deck widgets
# were added, so the decks kept their old geometry after a hotplug.
# Matches every widget unit, but not conky-feeds or this watcher.
WIDGETS='*-conky.service'

gdbus monitor --session --dest org.gnome.Mutter.DisplayConfig \
    --object-path /org/gnome/Mutter/DisplayConfig 2>/dev/null |
while read -r line; do
    case "$line" in
        *MonitorsChanged*)
            # Debounce: give Mutter/xrandr a moment to settle the new layout
            # before conky re-reads screen geometry on restart.
            sleep 2
            # try-restart: widgets switched off on this machine stay off.
            systemctl --user try-restart "$WIDGETS"
            ;;
    esac
done
