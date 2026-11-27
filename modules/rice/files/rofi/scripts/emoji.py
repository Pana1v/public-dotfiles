#!/usr/bin/env python3
"""Rofi script mode: emoji picker, copies the pick to the clipboard.

Names and search keywords come from Unicode CLDR (apt: unicode-cldr-core), so
there is no list to maintain and no pip package.
"""
import os
import subprocess
import xml.etree.ElementTree as ET

CLDR_DIR = os.environ.get('CLDR_DIR', '/usr/share/unicode/cldr/common')
# Derived holds skin tones, flags and sequences the base file leaves out.
ANNOTATION_FILES = ['annotations/en.xml', 'annotationsDerived/en.xml']


def parse(root):
    """{emoji: (name, keywords)} from a CLDR annotations tree, file order."""
    found = {}
    for node in root.iter('annotation'):
        name, keywords = found.get(node.get('cp'), ('', ''))
        if node.get('type') == 'tts':
            name = node.text
        else:
            keywords = node.text.replace(' | ', ' ')
        found[node.get('cp')] = (name, keywords)
    return found


def row(text, **opts):
    extras = '\x1f'.join(f'{k}\x1f{v}' for k, v in opts.items())
    print(f'{text}\0{extras}' if extras else text)


def list_emoji():
    print('\0prompt\x1fEMOJI')
    print('\0no-custom\x1ftrue')

    for rel in ANNOTATION_FILES:
        path = os.path.join(CLDR_DIR, rel)
        if not os.path.exists(path):
            print('\0message\x1fcldr missing: sudo apt install unicode-cldr-core')
            return
        for emoji, (name, keywords) in parse(ET.parse(path).getroot()).items():
            row(f'{emoji}  {name}', info=emoji, meta=keywords)


def selftest():
    xml = ('<r><annotation cp="A">x | y</annotation>'
           '<annotation cp="A" type="tts">letter a</annotation></r>')
    assert parse(ET.fromstring(xml)) == {'A': ('letter a', 'x y')}
    print('ok')


if os.environ.get('SELFTEST'):
    selftest()
elif os.environ.get('ROFI_INFO'):
    # xclip forks to keep the selection after this script exits.
    subprocess.run(['xclip', '-selection', 'clipboard'], input=os.environ['ROFI_INFO'].encode(), check=True)
else:
    list_emoji()
