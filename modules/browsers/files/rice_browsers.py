#!/usr/bin/env python3
"""Rice browsers with the active rice palette.

    rice_browsers.py css <palette> <out.css>
        Start page colours as CSS variables plus the palette wallpaper as its
        background (index.html loads ../palette.css; the image lands next to it).
    rice_browsers.py chromium <user-data-dir> <palette> <start url>
        Every profile of a Chromium-family browser (Chrome, Brave, Chromium,
        Edge, Vivaldi): dark mode, theme colour seeded from the palette accent
        (greyscale for a grey accent), start page as home and startup page.
        New tab background = the palette wallpaper in Chrome, Chromium and
        Brave (Edge and Vivaldi keep their own new tab page).
    rice_browsers.py firefox <profile dir> <palette> <start url>
        A Firefox-family profile: generated chrome/userChrome.css and
        userContent.css (toolbar, tabs, menus, and the new tab page with the
        palette wallpaper behind it), and a marked block in user.js (dark theme,
        stylesheets on, start page as home, no sponsored new tab content).

The wallpaper is the palette's @wallpaper: image:<file> from
modules/rice/files/wallpaper, or color:<hex>, drawn as a small solid PNG.

Run with the browser closed. Chromium rewrites Preferences from memory on
exit, so edits made while it runs are lost. The first run keeps a backup next
to each file it changes (Preferences.pre-rice, user.js.pre-rice).
"""
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WALLPAPERS = ROOT / "modules" / "rice" / "files" / "wallpaper"

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


def setting(path, name):
    for line in open(path):
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0] == "@" + name:
            return parts[1].strip()
    return ""


def solid_png(hexcolour, size=64):
    r, g, b = rgb(hexcolour)
    raw = b"".join(b"\x00" + bytes((r, g, b)) * size for _ in range(size))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def wallpaper(pal_path, pal):
    """(file name, bytes) of the palette wallpaper. The name changes with the
    image, so a browser never shows a cached one after a theme switch."""
    wp = setting(pal_path, "wallpaper")
    if wp.startswith("image:") and (WALLPAPERS / wp[6:]).is_file():
        return "rice-" + wp[6:], (WALLPAPERS / wp[6:]).read_bytes()
    colour = wp[6:] if wp.startswith("color:") else pal["bg"]
    return f"rice-{colour.lstrip('#').lower()}.png", solid_png(colour)


def place(directory, name, data):
    """Write the wallpaper into directory, removing older rice-* images."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    for old in directory.glob("rice-*"):
        if old.name != name and old.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp"):
            old.unlink()
    (directory / name).write_bytes(data)


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


def write_css(pal_path, pal, out):
    out = Path(out)
    name, data = wallpaper(pal_path, pal)
    place(out.parent, name, data)
    lines = [f"  --{var}: {pal[role]};" for var, role in CSS_ROLES.items() if role in pal]
    out.write_text(
        "/* Generated from the active rice palette by the browsers module. */\n"
        ":root {\n" + "\n".join(lines) + "\n}\n"
        f'html {{ background: {pal["bg"]} url("{name}") center / cover no-repeat fixed; }}\n'
        "body { background: transparent; }\n")


def set_in(d, path, value):
    *parents, leaf = path.split(".")
    for p in parents:
        d = d.setdefault(p, {})
    d[leaf] = value


def signed_argb(hexcolour):
    r, g, b = rgb(hexcolour)
    argb = 0xFF000000 | r << 16 | g << 8 | b
    return argb - (1 << 32)  # Chromium stores colours as signed 32 bit ints


def chromium_newtab(root, prof, prefs, name, data):
    """Wallpaper as the new tab background. False when this browser has no
    file-based custom background (Edge, Vivaldi)."""
    root = str(root)
    if "BraveSoftware" in root:
        place(prof / "sanitized_background_images", name, data)
        images = [n for n in prefs.get("brave", {}).get("new_tab_page", {})
                  .get("custom_background_image_list", []) if not n.startswith("rice-")]
        set_in(prefs, "brave.new_tab_page.custom_background_image_list", images + [name])
        set_in(prefs, "brave.new_tab_page.background",
               {"type": "custom_image", "selected_value": name, "random": False})
        set_in(prefs, "brave.new_tab_page.custom_background_enabled", True)
        set_in(prefs, "brave.new_tab_page.show_background_image", True)
        set_in(prefs, "brave.new_tab_page.show_branded_background_image", False)
        set_in(prefs, "brave.new_tab_page.show_sponsored_sites", False)
        return True
    if "microsoft-edge" in root or "vivaldi" in root:
        return False
    # Chrome and Chromium read <profile>/background.jpg when this pref is on.
    (prof / "background.jpg").write_bytes(data)
    set_in(prefs, "ntp.custom_background_local_to_device", True)
    set_in(prefs, "ntp.custom_background_inspiration", False)
    prefs.get("ntp", {}).pop("custom_background_dict", None)
    return True


def chromium(root, pal_path, pal, start):
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
    name, data = wallpaper(pal_path, pal)
    for prof in profiles:
        prefs_path = prof / "Preferences"
        prefs = json.loads(prefs_path.read_text())
        backup_once(prefs_path)
        for path, value in wanted.items():
            set_in(prefs, path, value)
        newtab = chromium_newtab(root, prof, prefs, name, data)
        prefs_path.write_text(json.dumps(prefs, separators=(",", ":")))
        print(f"    profile {prof.name}" + ("" if newtab else " (new tab background: not supported here)"))


USER_JS_BEGIN = "// rice:begin (dotfiles browsers module, rewritten on every apply)"
USER_JS_END = "// rice:end"


def firefox(profile, pal_path, pal, start):
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
    chrome = profile / "chrome"
    name, data = wallpaper(pal_path, pal)
    place(chrome, name, data)
    user_content = header + f"""@-moz-document url("about:newtab"), url("about:home") {{
  :root {{
    --newtab-background-color: {c['bg']} !important;
    --newtab-background-color-secondary: {c['card']} !important;
    --newtab-text-primary-color: {c['fg']} !important;
    --newtab-text-secondary-color: {c['dim2']} !important;
    --newtab-element-hover-color: {c['surface']} !important;
    --newtab-element-active-color: {c['select']} !important;
    --newtab-primary-action-background: {c['accent']} !important;
    --newtab-border-color: {c['surface']} !important;
  }}
  body {{
    background: {c['bg']} url("{name}") center / cover no-repeat fixed !important;
    color: {c['fg']} !important;
  }}
  .search-handoff-button, .search-inner-wrapper input, .search-wrapper input {{
    background-color: {c['card']} !important;
    color: {c['fg']} !important;
    border: 1px solid {c['surface']} !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }}
  .top-site-outer .tile, .top-site-outer .top-site-icon {{
    background-color: {c['card']} !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }}
  .top-site-outer:hover .tile {{ background-color: {c['surface']} !important; }}
  .top-site-outer .title {{ color: {c['fg']} !important; text-shadow: 0 1px 2px {c['bg']} !important; }}
}}
@-moz-document url("about:blank"), url("about:privatebrowsing") {{
  html, body {{ background: {c['bg']} !important; color: {c['fg']} !important; }}
}}
"""

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
        # new tab: search and shortcuts over the wallpaper, nothing sponsored
        "browser.newtabpage.activity-stream.showSponsored": False,
        "browser.newtabpage.activity-stream.showSponsoredTopSites": False,
        "browser.newtabpage.activity-stream.feeds.section.topstories": False,
        "browser.newtabpage.activity-stream.feeds.topsites": True,
        "browser.newtabpage.activity-stream.newtabWallpapers.enabled": False,
        "devtools.theme": "dark",
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
        write_css(args[0], palette(args[0]), args[1])
    elif cmd == "chromium":
        chromium(args[0], args[1], palette(args[1]), args[2])
    elif cmd == "firefox":
        firefox(args[0], args[1], palette(args[1]), args[2])
    else:
        sys.exit(__doc__)


main()
