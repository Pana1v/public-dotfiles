#!/usr/bin/env python3
"""Feeds the right-column conky widgets (runs under conky-feeds.service).

Each source runs its fetch script on its own interval, in its own thread,
and atomically rewrites ~/.cache/conky/<name>.tsv. The widgets only read
those files: forking from conky (io.popen segfaults, ${exec} from Lua
returns empty on most ticks) is avoided entirely, as with
fleet-ping.

Snapshot format: first line "ts\\t<epoch of last successful fetch>",
then the script's stdout verbatim. Empty output or a failing script
leaves the previous snapshot in place.
"""

import os
import re
import subprocess
import threading
import time

HOME = os.path.expanduser("~")
CONKY = f"{HOME}/.config/conky"
CACHE = f"{HOME}/.cache/conky"

# name: (command, interval seconds)
SOURCES = {
    "weather": (["python3", f"{CONKY}/Weather/fetch_weather.py"], 900),
    "github_prs": (["python3", f"{CONKY}/GithubPRs/fetch_prs.py"], 300),
    "linear": (["python3", f"{CONKY}/LinearWidget/fetch_issues.py"], 300),
    "now_playing": ([f"{CONKY}/NowPlaying/now_playing.sh"], 2),
    "cmf_buds": (["python3", f"{CONKY}/CmfBuds/fetch_buds.py"], 30),
    "audio": (["python3", f"{CONKY}/CmfBuds/fetch_audio.py"], 3),
    "devices": (["python3", f"{CONKY}/Devices/fetch_devices.py"], 10),
    "events": (["python3", f"{CONKY}/Agenda/fetch_events.py"], 120),
    "tasks": (["python3", f"{CONKY}/Tasks/fetch_tasks.py"], 120),
    "sysmon": (["python3", f"{CONKY}/Systems/fetch_system.py"], 2),
}


def profile() -> str:
    """personal (default) or professional, from CONKY_PROFILE or PROFILE= in local.env."""
    env = os.environ.get("CONKY_PROFILE")
    if env:
        return env
    value = "personal"
    try:
        with open(f"{HOME}/.config/dotfiles/local.env") as f:
            for line in f:
                m = re.match(r"\s*PROFILE\s*=\s*[\"']?(\w+)", line)
                if m:
                    value = m.group(1)
    except OSError:
        pass
    return value


# Google Tasks are personal: skip them and delete the cached copy when professional.
if profile() == "professional":
    SOURCES.pop("tasks", None)
    try:
        os.remove(f"{CACHE}/tasks.tsv")
    except OSError:
        pass

RETRY_SECONDS = 30   # after a failed fetch, don't wait a full interval
TIMEOUT_SECONDS = 120   # online calendars and task lists connect slowly


def write_snapshot(name: str, body: str) -> None:
    path = f"{CACHE}/{name}.tsv"
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"ts\t{int(time.time())}\n{body}")
    os.replace(tmp, path)


def run_source(name: str, cmd: list[str], interval: int) -> None:
    while True:
        started = time.monotonic()
        try:
            out = subprocess.run(
                cmd, capture_output=True, text=True, timeout=TIMEOUT_SECONDS, check=False
            ).stdout
        except subprocess.TimeoutExpired:
            out = ""

        if out.strip():
            write_snapshot(name, out)
            wait = interval
        else:
            wait = min(interval, RETRY_SECONDS)
        time.sleep(max(0, wait - (time.monotonic() - started)))


def main() -> None:
    os.makedirs(CACHE, exist_ok=True)
    threads = [
        threading.Thread(target=run_source, args=(name, cmd, interval), daemon=True)
        for name, (cmd, interval) in SOURCES.items()
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
