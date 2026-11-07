#!/usr/bin/env python3
"""Rofi script mode: switch to any open window.

Rofi's built-in window mode reads the X11 client list, so under Wayland it
misses every native window. The rofi-focus extension lists them over D-Bus.
"""
import os
from html import escape

from gi.repository import Gio, GLib

BUS_NAME = 'org.gnome.Shell'
OBJECT_PATH = '/org/gnome/Shell/Extensions/RofiFocus'
INTERFACE = 'org.gnome.Shell.Extensions.RofiFocus'


def call(method, args=None):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    return bus.call_sync(BUS_NAME, OBJECT_PATH, INTERFACE, method, args,
                         None, Gio.DBusCallFlags.NONE, -1, None).unpack()


def row(text, **opts):
    extras = '\x1f'.join(f'{k}\x1f{v}' for k, v in opts.items())
    print(f'{text}\0{extras}' if extras else text)


def list_windows():
    print('\0markup-rows\x1ftrue')
    print('\0no-custom\x1ftrue')

    (windows,) = call('ListWindows')
    for win_id, app, icon, title, workspace in windows:
        # Title first; app and workspace dimmed after it, e.g. "main.py  Code · ws 2"
        where = 'all' if workspace == 0 else f'ws {workspace}'
        meta = ' · '.join(filter(None, [escape(app), where]))
        text = f'{escape(title or app)}  <span alpha="45%">{meta}</span>'
        row(text, icon=icon, info=win_id, meta=f'{app} {where}')


selected = os.environ.get('ROFI_INFO')
if selected:
    # Printing nothing makes rofi exit; the focus change would close it anyway.
    call('Activate', GLib.Variant('(t)', (int(selected),)))
else:
    list_windows()
