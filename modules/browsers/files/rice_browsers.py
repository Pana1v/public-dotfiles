#!/usr/bin/env python3
"""Rice browsers with the active rice palette.

    rice_browsers.py css <palette> <out.css>
        Start page colours as CSS variables (index.html loads ../palette.css).
    rice_browsers.py chromium <user-data-dir> <palette> <start url>
        Every profile of a Chromium-family browser (Chrome, Brave, Chromium,
        Edge, Vivaldi): dark mode, theme colour seeded from the palette accent
        (greyscale for a grey accent), start page as home and startup page.
    rice_browsers.py firefox <profile dir> <palette> <start url>
        A Firefox-family profile: generated chrome/userChrome.css and
        userContent.css, and a marked block in user.js (dark theme, stylesheets
        on, start page as home).

Run with the browser closed. Chromium rewrites Preferences from memory on
exit, so edits made while it runs are lost. The first run keeps a backup next
to each file it changes (Preferences.pre-rice, user.js.pre-rice).
"""
import json
import re
import sys
from pathlib import Path

# Start page variable -> palette role.
CSS_ROLES = {
    "bg": "bg", "bg2": "bg2", "cell": "card", "surface": "surface",
    "select": "select", "dim": "dim", "dim2": "dim2", "fg": "fg", "green": "green",
}


def palette(path):
    roles = {}
    for line in open(path):
        parts = line.split()
        if len(parts) >= 2 and not parts[0].startswith(("#", "@")):
            roles[parts[0]] = parts[1].lower()
    return roles


def rgb(hexcolour):
    h = hexcolour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def is_grey(hexcolour):
    r, g, b = rgb(hexcolour)
    return max(r, g, b) - min(r, g, b) < 16


def backup_once(path):
    saved = path.with_name(path.name + ".pre-rice")
    if path.exists() and not saved.exists():
        saved.write_bytes(path.read_bytes())


def write_css(pal, out):
    lines = [f"  --{var}: {pal[role]};" for var, role in CSS_ROLES.items() if role in pal]
    Path(out).write_text(
        "/* Generated from the active rice palette by the browsers module. */\n"
        ":root {\n" + "\n".join(lines) + "\n}\n")


def set_in(d, path, value):
    *parents, leaf = path.split(".")
    for p in parents:
        d = d.setdefault(p, {})
    d[leaf] = value


def signed_argb(hexcolour):
    r, g, b = rgb(hexcolour)
    argb = 0xFF000000 | r << 16 | g << 8 | b
    return argb - (1 << 32)  # Chromium stores colours as signed 32 bit ints


def chromium(root, pal, start):
    accent = pal.get("accent", pal["fg"])
    grey = is_grey(accent)
    seed = pal.get("dim2", accent) if grey else accent
    theme = {
        "color_scheme": 2,                 # dark
        "user_color": signed_argb(seed),
        "is_grayscale": grey,
        "color_variant": 2 if grey else 1,  # neutral for grey, tonal spot for colour
    }
    wanted = {
        "homepage": start,
        "homepage_is_newtabpage": False,
        "browser.show_home_button": True,
        "session.restore_on_startup": 4,
        "session.startup_urls": [start],
        # flat new tab page in Brave: no photo, just clock and stats
        "brave.new_tab_page.show_background_image": False,
        "brave.new_tab_page.show_clock": True,
    }
    for key, value in theme.items():
        # Recent Chrome reads the synced "...2" keys, older forks the plain ones.
        wanted[f"browser.theme.{key}"] = value
        wanted[f"browser.theme.{key}2"] = value

    profiles = [p.parent for p in sorted(Path(root).glob("*/Preferences"))
                if p.parent.name == "Default" or p.parent.name.startswith("Profile ")]
    if not profiles:
        sys.exit(f"no profiles under {root}")
    for prof in profiles:
        prefs_path = prof / "Preferences"
        prefs = json.loads(prefs_path.read_text())
        for path, value in wanted.items():
            set_in(prefs, path, value)
        backup_once(prefs_path)
        prefs_path.write_text(json.dumps(prefs, separators=(",", ":")))
        print(f"    profile {prof.name}")


USER_JS_BEGIN = "// rice:begin (dotfiles browsers module, rewritten on every apply)"
USER_JS_END = "// rice:end"


def firefox(profile, pal, start):
    profile = Path(profile)
    c = {k: pal.get(k, pal["fg"]) for k in
         ("bg", "bg2", "card", "surface", "select", "dim", "dim2", "fg", "accent", "red")}
    header = "/* Generated from the active rice palette by the dotfiles browsers module.\n" \
             "   Rewritten on every apply: change the palette, not this file. */\n"
    user_chrome = header + f""":root {{
  --rice-bg: {c['bg']}; --rice-bg2: {c['bg2']}; --rice-card: {c['card']};
  --rice-surface: {c['surface']}; --rice-select: {c['select']}; --rice-dim: {c['dim2']};
  --rice-fg: {c['fg']}; --rice-accent: {c['accent']};

  --lwt-accent-color: var(--rice-bg) !important;
  --lwt-text-color: var(--rice-fg) !important;
  --toolbar-bgcolor: var(--rice-bg2) !important;
  --toolbar-color: var(--rice-fg) !important;
  --toolbarbutton-icon-fill: var(--rice-fg) !important;
  --toolbar-field-background-color: var(--rice-card) !important;
  --toolbar-field-color: var(--rice-fg) !important;
  --toolbar-field-focus-background-color: var(--rice-surface) !important;
  --toolbar-field-focus-color: var(--rice-fg) !important;
  --toolbar-field-focus-border-color: var(--rice-accent) !important;
  --tab-selected-bgcolor: var(--rice-surface) !important;
  --tab-selected-textcolor: var(--rice-fg) !important;
  --tab-border-radius: 0 !important;
  --arrowpanel-background: var(--rice-bg2) !important;
  --arrowpanel-color: var(--rice-fg) !important;
  --arrowpanel-border-color: var(--rice-surface) !important;
  --urlbarView-highlight-background: var(--rice-select) !important;
  --sidebar-background-color: var(--rice-bg2) !important;
  --sidebar-text-color: var(--rice-fg) !important;
  --focus-outline-color: var(--rice-accent) !important;
  --newtab-background-color: var(--rice-bg) !important;
}}

#navigator-toolbox {{
  background: var(--rice-bg) !important;
  border-bottom: 1px solid var(--rice-surface) !important;
}}
.tab-background:is([selected], [multiselected]) {{
  background: var(--rice-surface) !important;
  box-shadow: inset 0 -2px 0 var(--rice-accent) !important;
}}
.tabbrowser-tab:not([selected]) .tab-label {{ color: var(--rice-dim) !important; }}
#urlbar-background {{ border-radius: 0 !important; }}
"""
    user_content = header + f"""@-moz-document url("about:newtab"), url("about:home"), url("about:blank"), url("about:privatebrowsing") {{
  html, body {{ background: {c['bg']} !important; color: {c['fg']} !important; }}
}}
"""
    chrome = profile / "chrome"
    chrome.mkdir(exist_ok=True)
    (chrome / "userChrome.css").write_text(user_chrome)
    (chrome / "userContent.css").write_text(user_content)

    prefs = {
        "toolkit.legacyUserProfileCustomizations.stylesheets": True,
        "extensions.activeThemeID": "firefox-compact-dark@mozilla.org",
        "browser.theme.toolbar-theme": 0,
        "browser.theme.content-theme": 0,
        "layout.css.prefers-color-scheme.content-override": 0,
        "browser.startup.homepage": start,
        "browser.startup.page": 1,
    }
    block = [USER_JS_BEGIN] + [f"user_pref({json.dumps(k)}, {json.dumps(v)});"
                               for k, v in prefs.items()] + [USER_JS_END]
    user_js = profile / "user.js"
    backup_once(user_js)
    text = user_js.read_text() if user_js.exists() else ""
    text = re.sub(re.escape(USER_JS_BEGIN) + r".*?" + re.escape(USER_JS_END) + r"\n?", "",
                  text, flags=re.S)
    user_js.write_text(text.rstrip("\n") + ("\n" if text.strip() else "") + "\n".join(block) + "\n")


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "css":
        write_css(palette(args[0]), args[1])
    elif cmd == "chromium":
        chromium(args[0], palette(args[1]), args[2])
    elif cmd == "firefox":
        firefox(args[0], palette(args[1]), args[2])
    else:
        sys.exit(__doc__)


main()
