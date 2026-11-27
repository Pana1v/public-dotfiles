#!/usr/bin/env python3
"""Rofi script mode: colour picker and screenshot, both to the clipboard.

GNOME Wayland: gnome-screenshot hangs on a portal permission from a script, so
both go through xdg-desktop-portal in interactive mode, which GNOME answers
with its own picker / screenshot UI. A wait that outlives GRAB_TIMEOUT closes
the request instead of hanging.
"""
import os
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse

from gi.repository import Gio, GLib

PORTAL = 'org.freedesktop.portal.Desktop'
PORTAL_PATH = '/org/freedesktop/portal/desktop'
REQUEST_IFACE = 'org.freedesktop.portal.Request'
TIMEOUT_SECONDS = int(os.environ.get('GRAB_TIMEOUT', '120'))
# Rofi has to be gone before the screen is captured or it ends up in the shot.
ROFI_CLOSE_SECONDS = 0.4

COLOR = 'color'
SHOT = 'shot'
ROWS = [
    ('Pick colour', 'color-select-symbolic', COLOR),
    ('Screenshot to clipboard', 'applets-screenshooter', SHOT),
]


def hex_of(rgb):
    return '#' + ''.join(f'{round(c * 255):02X}' for c in rgb)


def portal_call(iface, method, args, token):
    """Run an interactive portal request, return its results or None if dismissed."""
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    sender = bus.get_unique_name()[1:].replace('.', '_')
    request = f'{PORTAL_PATH}/request/{sender}/{token}'
    loop = GLib.MainLoop()
    out = {}

    def on_response(_bus, _sender, _path, _iface, _signal, params):
        code, results = params.unpack()
        out['results'] = results if code == 0 else None
        GLib.source_remove(out['timer'])
        loop.quit()

    # Subscribe before calling, or a fast answer is missed.
    bus.signal_subscribe(PORTAL, REQUEST_IFACE, 'Response', request, None,
                         Gio.DBusSignalFlags.NONE, on_response)

    def close_request():
        bus.call_sync(PORTAL, request, REQUEST_IFACE, 'Close', None, None,
                      Gio.DBusCallFlags.NONE, -1, None)
        out['results'] = None
        loop.quit()
        return False

    options = {'handle_token': GLib.Variant('s', token), 'interactive': GLib.Variant('b', True)}
    variant = GLib.Variant('(sa{sv})', ('', options))
    bus.call_sync(PORTAL, PORTAL_PATH, iface, method, variant, None, Gio.DBusCallFlags.NONE, -1, None)
    out['timer'] = GLib.timeout_add_seconds(TIMEOUT_SECONDS, close_request)
    loop.run()
    return out['results']


def clip(data, mime='text/plain'):
    subprocess.run(['xclip', '-selection', 'clipboard', '-t', mime], input=data, check=True)


def pick_color():
    results = portal_call('org.freedesktop.portal.Screenshot', 'PickColor', None, 'rofi_color')
    if results:
        clip(hex_of(results['color']).encode())


def take_shot():
    results = portal_call('org.freedesktop.portal.Screenshot', 'Screenshot', None, 'rofi_shot')
    if not results:
        return
    path = unquote(urlparse(results['uri']).path)
    with open(path, 'rb') as f:
        clip(f.read(), 'image/png')
    # The clipboard holds the pixels now; the portal's copy is clutter.
    os.remove(path)


def selftest():
    assert hex_of((1.0, 0.0, 0.5)) == '#FF0080'
    assert hex_of((0.0, 0.0, 0.0)) == '#000000'
    print('ok')


def list_rows():
    print('\0prompt\x1fGRAB')
    print('\0no-custom\x1ftrue')
    for text, icon, info in ROWS:
        print(f'{text}\0icon\x1f{icon}\x1finfo\x1f{info}')


ACTIONS = {COLOR: pick_color, SHOT: take_shot}

if os.environ.get('SELFTEST'):
    selftest()
elif len(sys.argv) > 2 and sys.argv[1] == 'run':
    time.sleep(ROFI_CLOSE_SECONDS)
    ACTIONS[sys.argv[2]]()
elif os.environ.get('ROFI_INFO'):
    # Detached so the picker outlives rofi, which exits once this script returns.
    subprocess.Popen([sys.argv[0], 'run', os.environ['ROFI_INFO']], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
else:
    list_rows()
