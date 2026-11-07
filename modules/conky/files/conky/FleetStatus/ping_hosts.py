#!/usr/bin/env python3
"""Ping sweeper for the fleet-status conky widget.

Runs forever under fleet-ping.service and rewrites a TSV snapshot every
sweep. The widget only reads that file: conky's Lua must never spawn
processes (io.popen segfaults it, ${exec} blocks the draw thread).

Snapshot format, written atomically so a reader never sees a partial file:
    ts<TAB><epoch seconds>
    <label><TAB><addr><TAB>up|down<TAB><latency ms or ->
"""

import os
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor

# label<TAB>address per line, '#' comments allowed. A per-machine list in
# ~/.config/dotfiles wins over the private repo's. Neither: nothing to ping.
HOSTS_FILES = [
    os.path.expanduser("~/.config/dotfiles/fleet-hosts.tsv"),
    os.path.expanduser("~/.config/dotfiles/private/conky/fleet-hosts.tsv"),
]


def load_hosts():
    for path in HOSTS_FILES:
        try:
            with open(path) as f:
                rows = [line.split(None, 1) for line in f
                        if line.strip() and not line.lstrip().startswith("#")]
        except OSError:
            continue
        return [(r[0], r[1].strip()) for r in rows if len(r) == 2]
    return []


HOSTS = load_hosts()

SWEEP_SECONDS = 15
PING_TIMEOUT_SECONDS = 3
SNAPSHOT = os.path.join(os.path.expanduser("~"), ".cache", "conky", "fleet.tsv")

LATENCY_RE = re.compile(r"time=([\d.]+)\s*ms")


def ping_one(label_addr):
    label, addr = label_addr
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", str(PING_TIMEOUT_SECONDS), addr],
            capture_output=True, text=True, timeout=PING_TIMEOUT_SECONDS + 2, check=False,
        )
    except subprocess.TimeoutExpired:
        return f"{label}\t{addr}\tdown\t-"

    if result.returncode != 0:
        return f"{label}\t{addr}\tdown\t-"

    m = LATENCY_RE.search(result.stdout)
    return f"{label}\t{addr}\tup\t{m.group(1) if m else '-'}"


def sweep_once() -> None:
    lines = []
    if HOSTS:
        with ThreadPoolExecutor(max_workers=len(HOSTS)) as pool:
            lines = list(pool.map(ping_one, HOSTS))

    tmp = SNAPSHOT + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"ts\t{int(time.time())}\n")
        f.write("".join(line + "\n" for line in lines))
    os.replace(tmp, SNAPSHOT)


def main() -> None:
    os.makedirs(os.path.dirname(SNAPSHOT), exist_ok=True)
    while True:
        started = time.monotonic()
        sweep_once()
        time.sleep(max(0, SWEEP_SECONDS - (time.monotonic() - started)))


if __name__ == "__main__":
    main()
