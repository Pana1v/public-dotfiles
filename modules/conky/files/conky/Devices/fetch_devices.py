#!/usr/bin/env python3
"""Peripheral batteries for the conky devices panel, tab-separated:

  dev  <kind: headset|mouse|keyboard|...>  <model>  <percent>  <state>

state is charging, full or discharging. Devices come from UPower, which
sees Bluetooth batteries (through BlueZ) and Logitech/HID++ receivers. The
laptop's own battery ("power supply: yes") is left to the Elysium card.
Prints "none" when nothing is connected, so the snapshot still refreshes.
"""

import re
import subprocess


def run(*cmd: str) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout


# upower -i prints the device kind as a bare indented word, e.g. "  mouse".
def device_rows() -> list[str]:
    rows = []
    for path in run("upower", "-e").split():
        info = run("upower", "-i", path)
        if "power supply:         no" not in info:
            continue
        kind = re.search(r"^  (\w[\w-]*)$", info, re.M)
        model = re.search(r"model:\s+(.*)", info)
        percent = re.search(r"percentage:\s+([\d.]+)%", info)
        if not (kind and percent):
            continue
        state = re.search(r"state:\s+(\S+)", info)
        state = state.group(1) if state else "unknown"
        state = {"fully-charged": "full", "pending-charge": "charging"}.get(state, state)
        name = model.group(1).strip() if model else kind.group(1)
        rows.append(f"dev\t{kind.group(1)}\t{name}\t{float(percent.group(1)):.0f}\t{state}")
    return rows


def main():
    rows = device_rows()
    print("\n".join(rows) if rows else "none")


if __name__ == "__main__":
    main()
