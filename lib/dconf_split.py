#!/usr/bin/env python3
"""Split a dconf dump into its public and private sections.

    dconf_split.py <patterns file> <dump> <public out> <private out>

A section whose name matches a pattern goes to the private file, every other
section to the public one. The private file is removed when nothing matched.
"""
import os
import re
import sys

patterns_path, dump_path, public_path, private_path = sys.argv[1:5]
patterns = [
    re.compile(line.strip())
    for line in open(patterns_path)
    if line.strip() and not line.lstrip().startswith("#")
]

blocks, current = [], []
for line in open(dump_path).read().splitlines():
    if line.startswith("[") and current:
        blocks.append(current)
        current = []
    current.append(line)
if current:
    blocks.append(current)

public, private = [], []
for block in blocks:
    name = block[0][1:-1] if block[0].startswith("[") else ""
    target = private if any(p.search(name) for p in patterns) else public
    while block and block[-1] == "":
        block.pop()
    target.append("\n".join(block))

with open(public_path, "w") as f:
    f.write("\n\n".join(public) + "\n")
if private:
    os.makedirs(os.path.dirname(private_path), exist_ok=True)
    with open(private_path, "w") as f:
        f.write("\n\n".join(private) + "\n")
elif os.path.exists(private_path):
    os.remove(private_path)
