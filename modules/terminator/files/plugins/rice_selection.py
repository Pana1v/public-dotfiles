"""Selection colours from the rice palette.

Terminator has no selection colour setting, so VTE falls back to reverse
video. This reads the select and fg roles from ~/.config/rice/palette and
applies them as the VTE highlight colours, so a theme switch follows along
on the next Terminator start. With no palette file nothing changes.
"""

import os
import terminatorlib.plugin as plugin
from terminatorlib.terminal import Terminal
from gi.repository import Gdk

_PALETTE = os.path.expanduser('~/.config/rice/palette')


def _roles():
    roles = {}
    try:
        with open(_PALETTE) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[1].startswith('#'):
                    roles[parts[0]] = parts[1]
    except OSError:
        pass
    return roles


def _rgba(hexcolor):
    color = Gdk.RGBA()
    return color if hexcolor and color.parse(hexcolor) else None


AVAILABLE = ['RiceSelection']


class RiceSelection(plugin.Plugin):
    capabilities = ['rice_selection']

    def __init__(self):
        plugin.Plugin.__init__(self)
        if getattr(Terminal, '_rice_selection', False):
            return
        roles = _roles()
        bg = _rgba(roles.get('select'))
        fg = _rgba(roles.get('fg'))
        if bg is None:
            return
        original = Terminal.set_cursor_color

        # Runs on setup and on every focus change, after set_colors().
        def set_cursor_color(term):
            original(term)
            term.vte.set_color_highlight(bg)
            term.vte.set_color_highlight_foreground(fg)

        Terminal.set_cursor_color = set_cursor_color
        Terminal._rice_selection = True
