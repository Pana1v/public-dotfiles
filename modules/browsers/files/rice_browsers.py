#!/usr/bin/env python3
"""Rice browsers with the active rice palette.

    rice_browsers.py css <palette> <out.css>
        Start page colours as CSS variables plus the palette wallpaper as its
        background (index.html loads ../palette.css; the image lands next to it).
    rice_browsers.py theme <palette> <dir>
        The unpacked "Rice" Chromium theme: frame, tabs, toolbar, omnibox and
        new tab colours from the palette, the wallpaper on the new tab page.
        Load it once per profile (chrome://extensions > Developer mode > Load
        unpacked); later runs rewrite it in place for the next browser start.
        The chromium command does that load for Chrome and Edge.
    rice_browsers.py chromium <user-data-dir> <palette> <start url> [theme dir]
        Every profile of a Chromium-family browser (Chrome, Brave, Chromium,
        Edge, Vivaldi): dark mode, theme colour seeded from the palette accent
        (greyscale for a grey accent), start page as home and startup page.
        New tab background = the palette wallpaper in Chrome, Chromium and
        Brave (Edge and Vivaldi keep their own new tab page). Names profiles
        that have not loaded the Rice theme yet.
    rice_browsers.py firefox <profile dir> <palette> <start url>
        A Firefox-family profile: generated chrome/userChrome.css and
        userContent.css (toolbar, tabs, menus, the new tab page with the
        palette wallpaper behind it, selection and scrollbars on every site),
        and a marked block in user.js (dark theme, stylesheets on, start page
        as home, no sponsored new tab content).
    rice_browsers.py thunderbird <profile dir> <palette>
        A Thunderbird profile: userChrome.css over its --layout-* variables
        (folder pane, message list, reader, tabs) and a user.js block (dark
        theme, stylesheets on, dark message bodies).
    rice_browsers.py darkreader <palette> <out.json>
        Dark Reader settings that paint every site in the palette. Import once
        per browser (Dark Reader > Settings > Advanced > Import Settings).
    rice_browsers.py stylus <palette> <out.json>
        Stylus styles for sites whose own colour variables are public (GitHub's
        Primer); Dark Reader skips those sites. Import once per browser (Stylus
        > Manage > Import); a re-import updates the styles by name.

The wallpaper is RICE_WALLPAPER (an image path; apply.sh sets it for the
ember backdrop), else the palette's @wallpaper: image:<file> from
modules/rice/files/wallpaper, or color:<hex>, drawn as a small solid PNG.

Run with the browser closed. Chromium rewrites Preferences from memory on
exit, so edits made while it runs are lost. The first run keeps a backup next
to each file it changes (Preferences.pre-rice, user.js.pre-rice).
"""
import hashlib
import json
import os
import re
import struct
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WALLPAPERS = ROOT / "modules" / "rice" / "files" / "wallpaper"

# Start page variable -> palette role.
CSS_ROLES = {
    "bg": "bg", "bg2": "bg2", "cell": "card", "surface": "surface",
    "select": "select", "dim": "dim", "dim2": "dim2", "fg": "fg", "green": "green",
    "accent": "accent",
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


def rgb_png(width, height, pixel):
    """PNG of pixel(x, y) -> (r, g, b); no Pillow, so this module stays dependency free."""
    raw = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(width))
                   for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def solid_png(hexcolour, size=64):
    colour = rgb(hexcolour)
    return rgb_png(size, size, lambda x, y: colour)


def wallpaper(pal_path, pal, newtab=False):
    """(file name, bytes) of the palette wallpaper. The name changes with the
    image, so a browser never shows a cached one after a theme switch.
    newtab=True prefers the animated rain loop that apply.sh rendered
    (RICE_NEWTAB_IMAGE), for new tab pages that cannot run scripts."""
    loop = os.environ.get("RICE_NEWTAB_IMAGE", "")
    if newtab and loop and Path(loop).is_file():
        return "rice-" + Path(loop).name, Path(loop).read_bytes()
    image = os.environ.get("RICE_WALLPAPER", "")
    if image and Path(image).is_file():
        return "rice-" + Path(image).name, Path(image).read_bytes()
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
        ":root {\n" + "\n".join(lines)
        + f'\n  --ascii: {os.environ.get("RICE_ASCII", "rain")};\n}}\n'
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


FRAME_WIDTH = 512        # a multiple of GRID_CELL: the browser tiles the image sideways
FRAME_HEIGHT = 48
GRID_CELL = 32
HORIZON_ROW = 40         # tab strip is ~40px tall, so the glow sits on its bottom edge
GRID_ALPHA = 0.07
GLOW_ALPHA = 0.22
LINE_ALPHA = 0.35
CHROMIUM_EPOCH = 11644473600  # seconds from 1601 to 1970


def mix(base, over, alpha):
    return tuple(round(b + (o - b) * alpha) for b, o in zip(base, over))


def frame_png(base_hex, accent_hex, strength=1.0):
    """Tab strip texture: faint grid plus a red horizon glow, like the wallpaper.
         ...........   top: plain base colour
         ...glow....   rising toward the horizon
         ===========   horizon line
         grid floor    below it, dimmer
    strength scales every accent mix (the inactive window is dimmer)."""
    base, accent = rgb(base_hex), rgb(accent_hex)

    def pixel(x, y):
        alpha = GRID_ALPHA if x % GRID_CELL == 0 or y % (GRID_CELL // 2) == 0 else 0
        if y < HORIZON_ROW:
            alpha += GLOW_ALPHA * (y / HORIZON_ROW) ** 3
        elif y == HORIZON_ROW:
            alpha = LINE_ALPHA
        else:
            alpha = alpha * 0.5 + GLOW_ALPHA * 0.25
        return mix(base, accent, min(alpha * strength, 1))

    return rgb_png(FRAME_WIDTH, FRAME_HEIGHT, pixel)


def ext_id(data):
    """Chromium extension id: first 16 bytes of sha256, hex digits shown as a-p."""
    digest = hashlib.sha256(data).hexdigest()[:32]
    return digest.translate(str.maketrans("0123456789abcdef", "abcdefghijklmnop"))


def selfcheck():
    png = solid_png("#102030", 4)
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", png[16:24]) == (4, 4)
    frame = frame_png("#020000", "#ec0b12")
    assert struct.unpack(">II", frame[16:24]) == (FRAME_WIDTH, FRAME_HEIGHT)
    assert frame != frame_png("#020000", "#ec0b12", 0.5)
    # id Edge reported for this path after Load unpacked
    assert ext_id(b"/home/panav/.config/chrome-rice-theme") == "mapllalbidpoghmeobcldlplkmgeejka"
    print("selfcheck ok")


def theme(pal_path, pal, out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    r = {k: list(rgb(v)) for k, v in pal.items()}
    # Every key Chrome themes accept; anything left out falls back to stock grey
    # (inactive tabs, toolbar text, new tab header), which reads as un-riced.
    colors = {
        "frame": r["black"], "frame_inactive": r["bg2"],
        "frame_incognito": r["black"], "frame_incognito_inactive": r["bg2"],
        "background_tab": r["black"], "background_tab_inactive": r["bg2"],
        "background_tab_incognito": r["black"], "background_tab_incognito_inactive": r["bg2"],
        # Active tab = toolbar colour: lighter than the black strip so it stands out.
        "toolbar": r["select"], "toolbar_text": r["fg"], "toolbar_button_icon": r["fg2"],
        "tab_text": r["fg"], "tab_background_text": r["tab_fg"],
        "tab_background_text_inactive": r["tab_fg"],
        "tab_background_text_incognito": r["tab_fg"],
        "tab_background_text_incognito_inactive": r["tab_fg"],
        "bookmark_text": r["fg2"],
        "ntp_background": r["bg"], "ntp_text": r["fg"], "ntp_link": r["accent"],
        "ntp_header": r["accent"], "ntp_section": r["card"],
        "ntp_section_text": r["fg"], "ntp_section_link": r["accent"],
        "button_background": r["surface"],
        "omnibox_background": r["card"], "omnibox_text": r["fg"],
    }
    manifest = {
        "manifest_version": 3, "name": "Rice", "version": "1.0",
        "description": "Matches the desktop rice palette.",
        "theme": {
            "colors": colors,
            "tints": {"buttons": [-1, -1, -1]},
            "properties": {"ntp_logo_alternate": 1, "ntp_background_alignment": "center",
                           "ntp_background_repeat": "no-repeat"},
        },
    }
    images = {}
    for key, base, strength in (("theme_frame", "black", 1.0), ("theme_frame_inactive", "bg2", 0.5)):
        (out / "images").mkdir(exist_ok=True)
        (out / "images" / f"{key}.png").write_bytes(frame_png(pal[base], pal["accent"], strength))
        images[key] = f"images/{key}.png"
        images[key.replace("frame", "frame_incognito")] = f"images/{key}.png"
    manifest["theme"]["images"] = images
    name, data = wallpaper(pal_path, pal)
    # shortcut: themes take PNG only, so a JPEG wallpaper leaves the plain
    # ntp_background colour; convert with Pillow if a JPEG palette wants it.
    if data.startswith(b"\x89PNG"):
        place(out / "images", name, data)
        images["theme_ntp_background"] = "images/" + name
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    # The browser rebuilds the pack from the manifest when this is gone.
    (out / "Cached Theme.pak").unlink(missing_ok=True)


def link_theme(root, prefs, theme_dir):
    """Record the Rice theme as an unpacked extension in Preferences, which is
    what Load unpacked writes, so no manual click is needed. Branded Chrome
    ignores --load-extension and, on Linux, reads External Extensions only from
    root-owned dirs; Preferences it does honour (Linux does not MAC-check them).
    False for browsers where this is untested."""
    if not any(name in str(root) for name in ("google-chrome", "microsoft-edge")):
        return False
    unpacked = ext_id(str(theme_dir).encode())  # Chromium hashes the path of an unpacked extension
    now = str((int(time.time()) + CHROMIUM_EPOCH) * 1000000)  # microseconds
    empty = {"api": [], "explicit_host": [], "manifest_permissions": [], "scriptable_host": []}
    set_in(prefs, f"extensions.settings.{unpacked}", {
        "account_extension_type": 0, "active_permissions": empty, "commands": {},
        "content_settings": [], "creation_flags": 38, "disable_reasons": [], "events": [],
        "first_install_time": now, "from_webstore": False, "granted_permissions": empty,
        "incognito_content_settings": [], "incognito_preferences": {},
        "last_update_time": now, "location": 4, "newAllowFileAccess": True,
        "path": str(theme_dir), "preferences": {}, "regular_only_preferences": {},
        "was_installed_by_default": False, "was_installed_by_oem": False})
    set_in(prefs, "extensions.theme", {"id": unpacked, "pack": str(theme_dir), "system_theme": 0})
    return True


def chromium(root, pal_path, pal, start, theme_dir=""):
    accent = pal.get("accent", pal["fg"])
    grey = is_grey(accent)
    seed = pal.get("dim2", accent) if grey else accent
    theme = {
        "color_scheme": 2,                 # dark
        "user_color": signed_argb(seed),
        "is_grayscale": grey,
        # Chrome derives a Material palette from the seed instead of painting it.
        # Tonal spot (1) cuts the chroma, which turns a deep red into brown;
        # vibrant (3) keeps it. Neutral (2) for a grey accent.
        "color_variant": 2 if grey else 3,
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
    name, data = wallpaper(pal_path, pal, newtab=True)
    for prof in profiles:
        prefs_path = prof / "Preferences"
        prefs = json.loads(prefs_path.read_text())
        backup_once(prefs_path)
        for path, value in wanted.items():
            set_in(prefs, path, value)
        newtab = chromium_newtab(root, prof, prefs, name, data)
        prefs_path.write_text(json.dumps(prefs, separators=(",", ":")))
        print(f"    profile {prof.name}" + ("" if newtab else " (new tab background: not supported here)"))
        if theme_dir and prefs.get("extensions", {}).get("theme", {}).get("pack") != theme_dir:
            if link_theme(root, prefs, theme_dir):
                prefs_path.write_text(json.dumps(prefs, separators=(",", ":")))
                print(f"    profile {prof.name}: Rice theme linked, active on next start")
                continue
            print(f"    profile {prof.name}: load the Rice theme once: chrome://extensions >"
                  f" Developer mode > Load unpacked > {theme_dir}")


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
  --tab-border-radius: 12px !important;
  --toolbarbutton-border-radius: 99px !important;
  --arrowpanel-border-radius: 18px !important;
  --toolbarbutton-active-background: var(--rice-select) !important;
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
#urlbar-background {{ border-radius: 99px !important; }}
#urlbar[open] > #urlbar-background {{ border-radius: 18px !important; }}
.tab-label {{ font-family: "Space Mono", "JetBrains Mono", monospace !important; }}
"""
    chrome = profile / "chrome"
    name, data = wallpaper(pal_path, pal, newtab=True)
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
    border-radius: 99px !important;
    box-shadow: none !important;
  }}
  .top-site-outer .tile, .top-site-outer .top-site-icon {{
    background-color: {c['card']} !important;
    border-radius: 12px !important;
    box-shadow: none !important;
  }}
  .top-site-outer:hover .tile {{ background-color: {c['surface']} !important; }}
  .top-site-outer .title {{ color: {c['fg']} !important; text-shadow: 0 1px 2px {c['bg']} !important; }}
}}
@-moz-document url("about:blank"), url("about:privatebrowsing") {{
  html, body {{ background: {c['bg']} !important; color: {c['fg']} !important; }}
}}
/* Every site: palette selection and thin palette scrollbars. */
::selection {{ background: {c['select']} !important; color: {c['fg']} !important; }}
:root {{ scrollbar-color: {c['surface']} transparent !important; scrollbar-width: thin !important; }}
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
    write_user_js(profile, prefs)


def write_user_js(profile, prefs):
    block = [USER_JS_BEGIN] + [f"user_pref({json.dumps(k)}, {json.dumps(v)});"
                               for k, v in prefs.items()] + [USER_JS_END]
    user_js = profile / "user.js"
    backup_once(user_js)
    text = user_js.read_text() if user_js.exists() else ""
    text = re.sub(re.escape(USER_JS_BEGIN) + r".*?" + re.escape(USER_JS_END) + r"\n?", "",
                  text, flags=re.S)
    user_js.write_text(text.rstrip("\n") + ("\n" if text.strip() else "") + "\n".join(block) + "\n")


def thunderbird(profile, pal_path, pal):
    profile = Path(profile)
    c = pal
    # Thunderbird 115+ paints its panes from --layout-* (layout.css: 0 main
    # content, 1 centre panes, 2 primary sidebar, 3/4 nested blocks) and its
    # selection from --selected-item-color; the --lwt/toolbar/arrowpanel
    # variables are the toolkit ones Firefox uses for popups and the URL fields.
    user_chrome = f"""/* Generated from the active rice palette by the dotfiles browsers module.
   Rewritten on every apply: change the palette, not this file. */
:root, :host {{
  --layout-background-0: {c['bg']} !important;
  --layout-background-1: {c['bg2']} !important;
  --layout-background-2: {c['black']} !important;
  --layout-background-3: {c['card']} !important;
  --layout-background-4: {c['surface']} !important;
  --layout-color-0: {c['fg']} !important;
  --layout-color-1: {c['fg']} !important;
  --layout-color-2: {c['dim2']} !important;
  --layout-color-3: {c['dim']} !important;
  --layout-border-0: {c['surface']} !important;
  --layout-border-1: {c['surface']} !important;
  --layout-border-2: {c['bright_black']} !important;
  --selected-item-color: {c['accent']} !important;
  --selected-item-text-color: {c['fg']} !important;
  --tree-pane-background: {c['bg2']} !important;
  --tree-view-bg: {c['bg']} !important;
  --tree-card-background-current: {c['card']} !important;
  --tree-card-background-selected: {c['select']} !important;
  --tree-card-background-selected-current: {c['select']} !important;
  --listbox-selected-bg: {c['select']} !important;
  --listbox-hover: {c['card']} !important;
  --tabs-toolbar-background-color: {c['black']} !important;
  --lwt-accent-color: {c['black']} !important;
  --lwt-text-color: {c['fg']} !important;
  --toolbar-bgcolor: {c['bg2']} !important;
  --toolbar-color: {c['fg']} !important;
  --toolbar-field-background-color: {c['card']} !important;
  --toolbar-field-color: {c['fg']} !important;
  --toolbar-field-focus-border-color: {c['accent']} !important;
  --arrowpanel-background: {c['bg2']} !important;
  --arrowpanel-color: {c['fg']} !important;
  --arrowpanel-border-color: {c['surface']} !important;
  --focus-outline-color: {c['accent']} !important;
}}
.tabmail-tab[selected] {{ box-shadow: inset 0 -2px 0 {c['accent']} !important; }}
"""
    chrome = profile / "chrome"
    chrome.mkdir(exist_ok=True)
    (chrome / "userChrome.css").write_text(user_chrome)
    write_user_js(profile, {
        "toolkit.legacyUserProfileCustomizations.stylesheets": True,
        "extensions.activeThemeID": "thunderbird-compact-dark@mozilla.org",
        "ui.systemUsesDarkTheme": 1,
        # Darken HTML mail bodies too, not just the chrome around them.
        "mail.dark-reader.enabled": True,
        "devtools.theme": "dark",
    })


# Sites themed by the Stylus styles (or their own palette-fed theme, like
# Linear's custom theme), so Dark Reader keeps its hands off them.
OWN_THEME_SITES = ["github.com", "gist.github.com", "linear.app"]


def darkreader(pal, out):
    theme = {
        "mode": 1, "brightness": 100, "contrast": 100, "grayscale": 0, "sepia": 0,
        "useFont": False, "fontFamily": "Open Sans", "textStroke": 0,
        "engine": "dynamicTheme", "stylesheet": "",
        "darkSchemeBackgroundColor": pal["bg"], "darkSchemeTextColor": pal["fg"],
        "lightSchemeBackgroundColor": pal["fg"], "lightSchemeTextColor": pal["bg"],
        "scrollbarColor": pal["surface"], "selectionColor": pal["select"],
        "styleSystemControls": False, "lightColorScheme": "Default",
        "darkColorScheme": "Default", "immediateModify": False,
    }
    settings = {
        "enabled": True, "fetchNews": False, "theme": theme,
        "enabledByDefault": True, "enabledFor": [], "disabledFor": OWN_THEME_SITES,
        "changeBrowserTheme": False,
        # Off: a synced copy from another browser would undo a palette re-import.
        "syncSettings": False,
        # Off: sites that are already dark get the palette too, not their own grey.
        "detectDarkTheme": False,
        "enableForPDF": True,
    }
    Path(out).write_text(json.dumps(settings, indent=2))


def stylus(pal, out):
    c = pal
    # Primer (GitHub's design system) colour tokens, names taken from
    # github.githubassets.com/assets/dark-*.css. Only the dark mode is
    # overridden: GitHub's "sync with system" follows the desktop's dark mode.
    primer = {
        "bgColor-default": "bg", "bgColor-muted": "bg3", "bgColor-inset": "bg2",
        "bgColor-emphasis": "bright_black", "bgColor-neutral-muted": "surface",
        "bgColor-accent-emphasis": "accent", "bgColor-accent-muted": "select",
        "bgColor-success-emphasis": "teal", "bgColor-danger-emphasis": "red",
        "fgColor-default": "fg", "fgColor-muted": "dim2", "fgColor-accent": "cyan",
        "fgColor-success": "green", "fgColor-danger": "red", "fgColor-attention": "yellow",
        "fgColor-done": "magenta", "fgColor-severe": "orange",
        "borderColor-default": "surface", "borderColor-muted": "card",
        "borderColor-emphasis": "bright_black", "borderColor-accent-emphasis": "accent",
        "borderColor-accent-muted": "select",
        "header-bgColor": "black", "headerSearch-bgColor": "bg2",
        "overlay-bgColor": "bg2", "focus-outlineColor": "accent",
        "underlineNav-borderColor-active": "accent",
        "control-bgColor-rest": "card", "control-bgColor-hover": "surface",
        "control-bgColor-active": "select",
        "button-default-bgColor-rest": "card", "button-default-bgColor-hover": "surface",
        "button-default-bgColor-active": "select", "button-default-borderColor-rest": "surface",
        "button-default-fgColor-rest": "fg",
        "button-primary-bgColor-rest": "accent", "button-primary-bgColor-hover": "red",
        "button-primary-bgColor-active": "teal", "button-primary-fgColor-rest": "fg",
        "diffBlob-additionLine-bgColor": "diff_add", "diffBlob-additionNum-bgColor": "diff_add_word",
        "diffBlob-additionWord-bgColor": "diff_add_word",
        "diffBlob-deletionLine-bgColor": "diff_del", "diffBlob-deletionNum-bgColor": "diff_del_word",
        "diffBlob-deletionWord-bgColor": "diff_del_word",
        "diffBlob-hunkLine-bgColor": "card", "diffBlob-hunkNum-bgColor-rest": "surface",
    }
    lines = "\n".join(f"  --{var}: {c[role]} !important;" for var, role in primer.items())
    github = (":root[data-color-mode=dark], :root[data-color-mode=auto] {\n" + lines
              + '\n  --fontStack-monospace: "JetBrains Mono", monospace !important;\n}\n'
              f"::selection {{ background: {c['select']} !important; color: {c['fg']} !important; }}\n")
    styles = [{
        "name": "Rice: GitHub", "enabled": True,
        "sections": [{"code": github, "domains": ["github.com", "gist.github.com"]}],
    }]
    Path(out).write_text(json.dumps(styles, indent=2))


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "css":
        write_css(args[0], palette(args[0]), args[1])
    elif cmd == "theme":
        theme(args[0], palette(args[0]), args[1])
    elif cmd == "selfcheck":
        selfcheck()
    elif cmd == "chromium":
        chromium(args[0], args[1], palette(args[1]), *args[2:4])
    elif cmd == "firefox":
        firefox(args[0], args[1], palette(args[1]), args[2])
    elif cmd == "thunderbird":
        thunderbird(args[0], args[1], palette(args[1]))
    elif cmd == "darkreader":
        darkreader(palette(args[0]), args[1])
    elif cmd == "stylus":
        stylus(palette(args[0]), args[1])
    else:
        sys.exit(__doc__)


main()
