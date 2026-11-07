"""Make Linear issue keys in terminal output ctrl-clickable.

Turns NAV-743 into https://linear.app/<workspace>/issue/NAV-743, so issue keys
in git branch names, commit messages and log output open directly.

Workspace and team keys come from LINEAR_WORKSPACE and LINEAR_TEAMS (space
separated) in ~/.config/dotfiles/local.env, else in the private repo's
private.env. With no workspace set the handler stays off.

The team list is deliberately narrow. A generic [A-Z]+-[0-9]+ pattern would also
swallow UTF-8, ISO-8601 and USB-3, so only real team keys belong here.
"""

import os
import re
import terminatorlib.plugin as plugin

_CONF = os.path.expanduser('~/.config/dotfiles')


def _setting(key, default=''):
    for name in ('local.env', 'private/private.env'):
        try:
            with open(os.path.join(_CONF, name)) as f:
                for line in f:
                    m = re.match(r'^\s*%s=["\']?([^"\'#]*)' % key, line)
                    if m:
                        return m.group(1).strip()
        except OSError:
            pass
    return default


WORKSPACE = _setting('LINEAR_WORKSPACE')
PREFIXES = tuple(_setting('LINEAR_TEAMS', 'NAV').split()) or ('NAV',)
AVAILABLE = ['LinearIssueHandler'] if WORKSPACE else []

_KEY = '(?:%s)-[0-9]+' % '|'.join(PREFIXES)


class LinearIssueHandler(plugin.URLHandler):
    capabilities = ['url_handler']
    handler_name = 'linear_issue'
    nameopen = 'Open Linear issue'
    namecopy = 'Copy Linear URL'
    match = r'\b%s\b' % _KEY

    def callback(self, url):
        found = re.search('(%s)' % _KEY, url)

        if not found:
            return url

        return 'https://linear.app/%s/issue/%s' % (WORKSPACE, found.group(1))
