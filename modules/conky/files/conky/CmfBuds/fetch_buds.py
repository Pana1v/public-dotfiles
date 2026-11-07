#!/usr/bin/env python3
"""CMF Buds 2 snapshot for the conky widget, tab-separated:

  state     connected | disconnected
  battery   <left|right|case>  <percent>  <1 if charging>
  anc       <mode>
  eq        <preset>
  bass      <on|off>  <level>
  spatial   <on|off>

Always prints a state row: empty output would make feeds.py keep the
previous snapshot, freezing stale battery numbers on screen.
"""

from importlib.machinery import SourceFileLoader
from pathlib import Path

cmfbuds = SourceFileLoader("cmfbuds", str(Path(__file__).with_name("cmfbuds"))).load_module()


def snapshot(buds) -> list[str]:
    rows = ["state\tconnected"]
    for slot, value in cmfbuds.read_battery(buds).items():
        percent = value.split("%")[0]
        charging = int("charging" in value)
        rows.append(f"battery\t{slot}\t{percent}\t{charging}")

    bass_on, bass_level = cmfbuds.read_bass(buds)
    rows += [
        f"anc\t{cmfbuds.read_anc(buds)}",
        f"eq\t{cmfbuds.read_eq(buds)}",
        f"bass\t{cmfbuds.on_off(bass_on)}\t{bass_level}",
        f"spatial\t{cmfbuds.on_off(cmfbuds.read_flag(buds, cmfbuds.Cmd.SPATIAL_GET))}",
    ]
    return rows


def main():
    # cmfbuds exits via SystemExit on "not connected", timeouts and drops.
    try:
        buds = cmfbuds.connect(cmfbuds.find_address())
    except (SystemExit, OSError):
        print("state\tdisconnected")
        return

    try:
        print("\n".join(snapshot(buds)))
    except (SystemExit, OSError):
        print("state\tdisconnected")
    finally:
        buds.close()


if __name__ == "__main__":
    main()
