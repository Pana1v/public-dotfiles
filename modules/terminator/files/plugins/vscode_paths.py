"""Make file paths in terminal output ctrl-clickable, opening them in VS Code.

Two shapes cover almost everything ROS emits:

    Python traceback    File "/abs/path.py", line 42
    compiler / linter   /abs/path.cpp:42:7

Both resolve to vscode://file/<path>:<line>[:<col>]. That scheme is registered
system-wide by code-url-handler.desktop, so Terminator's normal open_url path
(Gtk.show_uri -> xdg-open) reaches VS Code with no extra wiring.

A line number is required on purpose. Matching bare paths would make every
word in a log clickable and bury the matches that actually matter.
"""

import re
import terminatorlib.plugin as plugin

AVAILABLE = ['PyTracebackHandler', 'PathLineHandler']

# Swap to 'cursor' to route these to Cursor instead; both are installed.
EDITOR_SCHEME = 'vscode'


def _editor_uri(path, line, col=None):
    location = '%s:%s' % (path, line)

    if col:
        location = '%s:%s' % (location, col)

    return '%s://file%s' % (EDITOR_SCHEME, location)


class PyTracebackHandler(plugin.URLHandler):
    """The `File "/abs/path.py", line 42` frames in a Python traceback."""

    capabilities = ['url_handler']
    handler_name = 'py_traceback_path'
    nameopen = 'Open in VS Code'
    namecopy = 'Copy file path'
    match = r'File "/[^"\n]+", line [0-9]+'

    def callback(self, url):
        found = re.search(r'File "(/[^"]+)", line ([0-9]+)', url)

        if not found:
            return url

        return _editor_uri(found.group(1), found.group(2))


class PathLineHandler(plugin.URLHandler):
    """`/abs/path.ext:42` or `:42:7`, as gcc, colcon and linters emit."""

    capabilities = ['url_handler']
    handler_name = 'path_with_line'
    nameopen = 'Open in VS Code'
    namecopy = 'Copy file path'
    match = r'/[^\s:]+\.[A-Za-z0-9]{1,6}:[0-9]+(:[0-9]+)?'

    def callback(self, url):
        found = re.match(r'(/[^\s:]+):([0-9]+)(?::([0-9]+))?', url)

        if not found:
            return url

        return _editor_uri(found.group(1), found.group(2), found.group(3))
