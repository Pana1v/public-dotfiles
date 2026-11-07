#!/usr/bin/env python3
"""Build the "Rice" VS Code / Cursor colour theme from a rice palette.

    vscode-theme.py <palette> <out dir> [<out.vsix>]

The hand-tuned Tron theme (modules/vscode/files/tron-rice-theme) is the
template. Every colour in it is mapped to a role of the Tron palette (exact
match, or the nearest role plus the shade's offset from it), then replaced
with that role's colour in the target palette, offset applied. Alpha suffixes (#rrggbbaa) are kept. So
any palette, current or future, gets the full 591-colour theme.

The out dir is a complete extension (package.json + theme). With a .vsix path
it is also packaged, so `code --install-extension` registers it properly;
later palette switches only rewrite the installed copy (lib/common.sh).
"""
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TEMPLATE = ROOT / "modules/vscode/files/tron-rice-theme/themes/tron-rice-color-theme.json"
TEMPLATE_PALETTE = ROOT / "modules/rice/themes/tron.palette"
HEX = re.compile(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\b")


def palette(path):
    roles = {}
    for line in open(path):
        parts = line.split()
        if len(parts) >= 2 and not parts[0].startswith(("#", "@")) and parts[1].startswith("#"):
            roles[parts[0]] = parts[1].lower()
    return roles


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def nearest_role(hexcolour, roles):
    r, g, b = rgb(hexcolour)
    return min(roles, key=lambda k: sum((x - y) ** 2 for x, y in zip((r, g, b), rgb(roles[k]))))


def write_vsix(ext, vsix, blurb):
    types = ('<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/'
             'package/2006/content-types"><Default Extension=".json" ContentType="application/json"/>'
             '<Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>')
    manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="rice" Version="0.1.0" Publisher="local"/>
    <DisplayName>Rice</DisplayName>
    <Description xml:space="preserve">Generated from the active rice palette. {blurb}</Description>
    <Categories>Themes</Categories>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.60.0"/></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
"""
    with zipfile.ZipFile(vsix, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("extension.vsixmanifest", manifest)
        for f in sorted(ext.rglob("*")):
            if f.is_file():
                z.write(f, "extension/" + f.relative_to(ext).as_posix())


def main():
    target_path, out = Path(sys.argv[1]), Path(sys.argv[2])
    src, dst = palette(TEMPLATE_PALETTE), palette(target_path)
    shared = {k: v for k, v in src.items() if k in dst}
    cache = {}

    def swap(m):
        base = "#" + m.group(1).lower()
        if base in ("#000000", "#ffffff"):   # shadows and opacity masks, not colours
            return m.group(0)
        if base not in cache:
            # Nearest role, plus this shade's offset from it, so in-between
            # shades stay lighter or darker than their role in any palette.
            role = nearest_role(base, shared)
            delta = [x - y for x, y in zip(rgb(base), rgb(shared[role]))]
            out = [max(0, min(255, c + d)) for c, d in zip(rgb(dst[role]), delta)]
            cache[base] = "#%02x%02x%02x" % tuple(out)
        return cache[base] + (m.group(2) or "")

    theme = json.loads(HEX.sub(swap, TEMPLATE.read_text()))
    theme["name"] = "Rice"
    header = open(target_path).readline()
    blurb = re.sub(r"^#\s*role\s+hex\s*", "", header).strip()

    (out / "themes").mkdir(parents=True, exist_ok=True)
    (out / "themes" / "rice-color-theme.json").write_text(json.dumps(theme, indent=2) + "\n")
    (out / "package.json").write_text(json.dumps({
        "name": "rice",
        "displayName": "Rice",
        "description": f"Generated from the active rice palette. {blurb}",
        "version": "0.1.0",
        "publisher": "local",
        "engines": {"vscode": "^1.60.0"},
        "categories": ["Themes"],
        "contributes": {"themes": [{
            "label": "Rice", "uiTheme": "vs-dark", "path": "./themes/rice-color-theme.json"}]},
    }, indent=2) + "\n")
    if len(sys.argv) > 3:
        write_vsix(out, Path(sys.argv[3]), blurb)
    print(f"    vscode  Rice theme from {target_path.name} ({len(cache)} colours mapped)")


main()
