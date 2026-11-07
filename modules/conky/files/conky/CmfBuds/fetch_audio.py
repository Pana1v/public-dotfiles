#!/usr/bin/env python3
"""Default audio devices for the conky audio panel, tab-separated:

  out   <description>  <volume 0..1.5>  <1 if muted>  <api: bluez5|alsa|...>
  in    <description>  <volume>         <1 if muted>  <api>

A device row is skipped when WirePlumber has no default of that kind.
Peripheral batteries are the devices panel's (Devices/fetch_devices.py).
"""

import re
import subprocess

DEVICES = {"out": "@DEFAULT_AUDIO_SINK@", "in": "@DEFAULT_AUDIO_SOURCE@"}


def wpctl(*args: str) -> str:
    return run("wpctl", *args)


def prop(inspect: str, key: str) -> str:
    match = re.search(rf'{re.escape(key)} = "([^"]*)"', inspect)
    return match.group(1) if match else ""


def row(kind: str, target: str) -> str | None:
    inspect = wpctl("inspect", target)
    volume_line = wpctl("get-volume", target)
    volume = re.search(r"Volume: ([\d.]+)", volume_line)
    if not inspect or not volume:
        return None

    name = prop(inspect, "node.description") or prop(inspect, "node.name")
    muted = int("[MUTED]" in volume_line)
    return f"{kind}\t{name}\t{volume.group(1)}\t{muted}\t{prop(inspect, 'device.api')}"


def run(*cmd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    return result.stdout if result.returncode == 0 else ""


def main():
    rows = [r for kind, target in DEVICES.items() if (r := row(kind, target))]
    print("\n".join(rows) if rows else "none")


if __name__ == "__main__":
    main()
