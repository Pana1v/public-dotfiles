#!/usr/bin/env python3
"""Machine metrics for the conky wings, tab-separated, one row per line:

  cpu   <percent>  <temp C or ->
  gpu   <percent>  <temp C or ->  <active|sleep|none>
  igpu  <percent>  <temp C or ->  <present|none>
  npu   <percent>  <active|suspended|none>
  mem   <percent>  <used KiB>  <total KiB>
  swap  <percent>  <used KiB>  <total KiB>
  net   <down bytes/s>  <up bytes/s>  <interface>
  disk  <percent>  <used GiB>  <total GiB>
  batt  <percent>  <status>

CPU load and network rates are deltas, so the counters from the previous run
live in ~/.cache/conky/.sysmon.json. The NVIDIA GPU is only queried while its
runtime power state is "active": calling nvidia-smi every few seconds would
keep a sleeping laptop dGPU awake and cost battery.

The AMD integrated GPU reports a real busy percentage. The AMD NPU (amdxdna)
exposes no load counter, only how long it has been powered on, so its figure
is the share of the last interval it spent awake, not compute load.
"""

import glob
import json
import os
import subprocess
import time

HOME = os.path.expanduser("~")
STATE = f"{HOME}/.cache/conky/.sysmon.json"


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def cpu_counters():
    parts = [int(x) for x in read("/proc/stat").split("\n")[0].split()[1:]]
    idle = parts[3] + parts[4]
    return idle, sum(parts)


def default_iface():
    for line in read("/proc/net/route").split("\n")[1:]:
        f = line.split()
        if len(f) > 1 and f[1] == "00000000":
            return f[0]
    return ""


def net_counters(iface):
    for line in read("/proc/net/dev").split("\n")[2:]:
        name, _, data = line.partition(":")
        if name.strip() == iface:
            f = data.split()
            return int(f[0]), int(f[8])
    return 0, 0


def cpu_temp():
    for hw in glob.glob("/sys/class/hwmon/hwmon*"):
        if read(f"{hw}/name") in ("k10temp", "coretemp", "zenpower"):
            raw = read(f"{hw}/temp1_input")
            if raw:
                return round(int(raw) / 1000)
    return None


def gpu():
    for dev in glob.glob("/sys/bus/pci/devices/*"):
        if read(f"{dev}/vendor") == "0x10de" and read(f"{dev}/class").startswith("0x03"):
            if read(f"{dev}/power/runtime_status") != "active":
                return 0, None, "sleep"
            out = subprocess.run(
                ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"],
                capture_output=True, text=True, check=False, timeout=5).stdout.strip()
            try:
                util, temp = (int(x) for x in out.split(","))
                return util, temp, "active"
            except ValueError:
                return 0, None, "active"
    return 0, None, "none"


def igpu():
    """AMD integrated GPU: (busy percent, temp C or None, 'present'/'none')."""
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]")):
        dev = f"{card}/device"
        if read(f"{dev}/vendor") != "0x1002":
            continue
        busy = read(f"{dev}/gpu_busy_percent")
        if not busy:
            continue
        temp = None
        for t in glob.glob(f"{dev}/hwmon/hwmon*/temp1_input"):
            raw = read(t)
            if raw:
                temp = round(int(raw) / 1000)
        return int(busy), temp, "present"
    return 0, None, "none"


def npu_active_ms():
    """(milliseconds powered on so far, current status) or None without an NPU."""
    dev = "/sys/class/accel/accel0/device"
    if not os.path.isdir(dev):
        return None
    try:
        return int(read(f"{dev}/power/runtime_active_time", "0")), read(f"{dev}/power/runtime_status", "unknown")
    except ValueError:
        return None


def meminfo():
    m = {}
    for line in read("/proc/meminfo").split("\n"):
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) if v.split() else 0
    return m


def main():
    now = time.time()
    iface = default_iface()
    idle, total = cpu_counters()
    rx, tx = net_counters(iface)
    try:
        prev = json.load(open(STATE))
    except (OSError, ValueError):
        prev = None
    if not prev or now - prev["t"] > 30 or prev.get("iface") != iface:
        time.sleep(0.25)   # no usable history: take a quick second sample
        prev = {"t": now, "cpu": [idle, total], "net": [rx, tx], "iface": iface}
        idle, total = cpu_counters()
        rx, tx = net_counters(iface)
        now = time.time()
    npu = npu_active_ms()
    prev_npu = prev.get("npu")
    dt = max(now - prev["t"], 0.1)
    d_total = total - prev["cpu"][1]
    cpu = 100 * (1 - (idle - prev["cpu"][0]) / d_total) if d_total > 0 else 0
    down, up = max(rx - prev["net"][0], 0) / dt, max(tx - prev["net"][1], 0) / dt
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump({"t": now, "cpu": [idle, total], "net": [rx, tx], "iface": iface,
               "npu": [npu[0], now] if npu else None}, open(STATE, "w"))

    temp = cpu_temp()
    print(f"cpu\t{cpu:.0f}\t{temp if temp is not None else '-'}")
    g, gt, gs = gpu()
    print(f"gpu\t{g}\t{gt if gt is not None else '-'}\t{gs}")
    ig, igt, igs = igpu()
    print(f"igpu\t{ig}\t{igt if igt is not None else '-'}\t{igs}")
    if npu is None:
        print("npu\t0\tnone")
    else:
        if prev_npu and npu[0] >= prev_npu[0] and now > prev_npu[1]:
            share = 100 * (npu[0] - prev_npu[0]) / 1000 / (now - prev_npu[1])
        else:
            share = 100 if npu[1] == "active" else 0
        print(f"npu\t{max(0, min(round(share), 100))}\t{npu[1]}")
    m = meminfo()
    used = m["MemTotal"] - m["MemAvailable"]
    print(f"mem\t{100 * used / m['MemTotal']:.0f}\t{used}\t{m['MemTotal']}")
    swap_used = m["SwapTotal"] - m["SwapFree"]
    swap_pct = 100 * swap_used / m["SwapTotal"] if m["SwapTotal"] else 0
    print(f"swap\t{swap_pct:.0f}\t{swap_used}\t{m['SwapTotal']}")
    print(f"net\t{down:.0f}\t{up:.0f}\t{iface or '-'}")
    st = os.statvfs("/")
    size, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
    print(f"disk\t{100 * (size - free) / size:.0f}\t{(size - free) / 2**30:.0f}\t{size / 2**30:.0f}")
    bat = "/sys/class/power_supply/BAT0"
    if os.path.isdir(bat):
        print(f"batt\t{read(bat + '/capacity', '0')}\t{read(bat + '/status', 'Unknown').lower()}")


if __name__ == "__main__":
    main()
