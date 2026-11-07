#!/usr/bin/env python3
"""Startup HUD: short matrix rain, then braille gauges, sparklines and bars.

Env: BANNER_NO_RAIN=1 skips the rain, NO_COLOR disables color.
Stdlib only. Must never raise: this runs on every interactive shell.
"""
import atexit, glob, math, os, platform, random, shutil, signal, subprocess
import sys, threading, time

OUT = sys.stdout
TTY = OUT.isatty()
W, H = shutil.get_terminal_size((80, 24))
COLOR = TTY and not os.environ.get("NO_COLOR") and os.environ.get("TERM") != "dumb"
TRUE = COLOR and os.environ.get("COLORTERM") in ("truecolor", "24bit")

# palette: (rgb, xterm-256 fallback). One muted green accent like the desktop HUD.
ACCENT = ((125, 174, 110), 108)
DIM = ((61, 90, 61), 65)
TRACK = ((42, 47, 42), 238)
TEXT = ((154, 165, 154), 247)
BRIGHT = ((205, 215, 200), 252)
WARN = ((226, 168, 70), 214)
CRIT = ((224, 108, 96), 203)

RST = "\033[0m" if COLOR else ""


def fg(c):
    if not COLOR:
        return ""
    if TRUE:
        r, g, b = c[0]
        return f"\033[38;2;{r};{g};{b}m"
    return f"\033[38;5;{c[1]}m"


def paint(c, s):
    return fg(c) + s + RST if COLOR else s


def restore():
    if TTY:
        OUT.write("\033[?25h\033[0m")
        OUT.flush()


atexit.register(restore)
for _s in (signal.SIGTERM, signal.SIGHUP):
    signal.signal(_s, lambda *_: sys.exit(1))


# ---------- samplers ----------
def read_cpu():
    v = list(map(int, open("/proc/stat").readline().split()[1:]))
    return v[3] + v[4], sum(v)


def read_net():
    rx = tx = 0
    for line in list(open("/proc/net/dev"))[2:]:
        name, data = line.split(":", 1)
        if name.strip() == "lo":
            continue
        f = data.split()
        rx += int(f[0]); tx += int(f[8])
    return rx, tx


def cpu_temp():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(h + "/name").read().strip() in ("k10temp", "coretemp", "zenpower"):
                return int(open(h + "/temp1_input").read()) // 1000
        except (OSError, ValueError):
            pass
    for z in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
        try:
            return int(open(z).read()) // 1000
        except (OSError, ValueError):
            pass


def gpu_query(box):
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
             "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=0.6)
        u, mu, mt, t = [float(x) for x in r.stdout.strip().splitlines()[0].split(",")]
        box.append((u, mu / 1024, mt / 1024, int(t)))
    except Exception:
        pass


def battery():
    for b in glob.glob("/sys/class/power_supply/BAT*")[:1]:
        try:
            pct = int(open(b + "/capacity").read())
            st = open(b + "/status").read().strip()
            eta = ""
            try:
                p = int(open(b + "/power_now").read())
                if p > 0 and st == "Discharging":
                    hrs = int(open(b + "/energy_now").read()) / p
                    eta = f"{int(hrs)}h{int(hrs % 1 * 60):02d}"
            except (OSError, ValueError):
                pass
            return pct, st, eta
        except (OSError, ValueError):
            pass


def uptime():
    s = int(float(open("/proc/uptime").read().split()[0]))
    d, s = divmod(s, 86400); h, s = divmod(s, 3600)
    return (f"{d}d" if d else "") + (f"{h}h" if h else "") + f"{s // 60}m"


# ---------- rain ----------
RAIN_CHARS = "0123456789:.=*+-<>"
RAIN_TRAIL = [BRIGHT, ACCENT, ACCENT, DIM, DIM, TRACK]


def sample(state):
    """Take one CPU/NET sample into state; returns nothing."""
    now = time.time()
    c, n = read_cpu(), read_net()
    if state["c"]:
        idle, tot = c[0] - state["c"][0], c[1] - state["c"][1]
        state["cpu"].append(100 * (1 - idle / tot) if tot else 0)
        dt = max(now - state["t"], 1e-3)
        state["rx"].append((n[0] - state["n"][0]) / dt)
        state["tx"].append((n[1] - state["n"][1]) / dt)
    state["c"], state["n"], state["t"] = c, n, now


def run_sampling(state, secs, rain_rows=0):
    cols = W - 1
    end = time.time() + secs
    if not rain_rows:
        while time.time() < end:
            sample(state)
            time.sleep(0.03)
        return
    heads = [random.randint(-rain_rows, 0) for _ in range(cols)]
    speed = [random.choice((1, 1, 2)) for _ in range(cols)]
    grid = [[" "] * cols for _ in range(rain_rows)]
    age = [[99] * cols for _ in range(rain_rows)]
    OUT.write("\n" * rain_rows)
    while time.time() < end:
        sample(state)
        for c in range(cols):
            for _ in range(speed[c]):
                heads[c] += 1
                r = heads[c]
                if 0 <= r < rain_rows:
                    grid[r][c] = random.choice(RAIN_CHARS)
                    age[r][c] = 0
            if heads[c] > rain_rows + random.randint(0, 5):
                heads[c] = random.randint(-rain_rows, 0)
        buf = [f"\033[{rain_rows}A"]
        for r in range(rain_rows):
            line = []
            for c in range(cols):
                a = age[r][c]
                line.append(fg(RAIN_TRAIL[a]) + grid[r][c] if a < len(RAIN_TRAIL) else " ")
                age[r][c] = a + 1
            buf.append("".join(line) + RST + "\n")
        OUT.write("".join(buf))
        OUT.flush()
        time.sleep(0.03)
    OUT.write(f"\033[{rain_rows}A\033[J")


# ---------- graphics ----------
def level(p, inv=False, warn=75, crit=90):
    """Return (color, marker). inv: low is bad (battery)."""
    if inv:
        warn, crit = 100 - 30, 100 - 15
        p = 100 - p
    if p >= crit:
        return CRIT, "!"
    if p >= warn:
        return WARN, "▲"
    return ACCENT, ""


BRAILLE_BITS = {(0, 0): 1, (0, 1): 2, (0, 2): 4, (1, 0): 8, (1, 1): 16, (1, 2): 32, (0, 3): 64, (1, 3): 128}


def gauge(pct, color):
    """6x3 cell braille ring, 270 degree sweep starting bottom-left."""
    cells = [[[0, 0] for _ in range(6)] for _ in range(3)]  # [track_bits, fill_bits]
    for y in range(12):
        for x in range(12):
            dx, dy = x - 5.5, y - 5.5
            r = math.hypot(dx, dy)
            if not 4.2 <= r <= 5.9:
                continue
            sweep = (math.degrees(math.atan2(dy, dx)) - 135) % 360
            if sweep > 270:
                continue
            bit = BRAILLE_BITS[(x % 2, y % 4)]
            cell = cells[y // 4][x // 2]
            cell[1 if sweep / 270 <= pct / 100 else 0] |= bit
    num = f"{pct:.0f}%".center(4)
    rows = []
    for ry in range(3):
        out = []
        for cx in range(6):
            track, fill = cells[ry][cx]
            if ry == 1 and 1 <= cx <= 4:
                out.append(paint(BRIGHT, num[cx - 1]))
            elif fill:
                out.append(paint(color, chr(0x2800 + fill)))
            elif track:
                out.append(paint(TRACK, chr(0x2800 + track)))
            else:
                out.append(" ")
        rows.append("".join(out))
    return rows


SPARK_L = [0, 64, 64 | 4, 64 | 4 | 2, 64 | 4 | 2 | 1]
SPARK_R = [0, 128, 128 | 32, 128 | 32 | 16, 128 | 32 | 16 | 8]


def spark(vals, width, vmax, color):
    """Braille sparkline, 2 samples per cell, 4 levels."""
    n = width * 2
    if not vals:
        vals = [0]
    pts = [vals[min(len(vals) - 1, i * len(vals) // n)] for i in range(n)]
    out = []
    for i in range(0, n, 2):
        hs = [max(1, min(4, round(v / vmax * 4))) if vmax else 1 for v in pts[i:i + 2]]
        out.append(chr(0x2800 + SPARK_L[hs[0]] + SPARK_R[hs[1]]))
    return paint(color, "".join(out))


EIGHTHS = " ▏▎▍▌▋▊▉█"


def hbar(pct, width, color, tick=85):
    units = round(width * 8 * pct / 100)
    full, part = divmod(units, 8)
    cells = ["█"] * full + ([EIGHTHS[part]] if part and full < width else [])
    s = paint(color, "".join(cells))
    rest = width - len(cells)
    tick_at = int(width * tick / 100)
    track = []
    for i in range(len(cells), width):
        track.append("┆" if i == tick_at else "─")
    return s + paint(TRACK, "".join(track))


def fmt_rate(b):
    for unit in ("B", "K", "M", "G"):
        if b < 1024 or unit == "G":
            return f"{b:.0f}{unit}" if b < 100 or unit == "B" else f"{b:.0f}{unit}"
        b /= 1024


def center(s, vis, width):
    pad = max(0, width - vis)
    return " " * (pad // 2) + s + " " * (pad - pad // 2)


def section(title, width, right=""):
    left = f" ■ {title} "
    fill = max(2, width - len(left) - len(right) - (1 if right else 0))
    return (paint(ACCENT, " ■ ") + paint(BRIGHT, title) + " "
            + paint(DIM, "─" * fill) + (" " + paint(TEXT, right) if right else ""))


# ---------- card ----------
def card(state, gpu):
    I = max(36, min(W - 1, 64))
    lines = []
    host = platform.node().split(".")[0][:18]
    lines.append(section("SYSTEMS", I, f"{os.environ.get('USER', 'user')}@{host}"))

    mem = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
    mem_pct = 100 * (1 - mem["MemAvailable"] / mem["MemTotal"])
    mem_used = (mem["MemTotal"] - mem["MemAvailable"]) / 1048576
    mem_tot = mem["MemTotal"] / 1048576
    cpu_now = state["cpu"][-1] if state["cpu"] else 0
    cpu_avg = sum(state["cpu"]) / len(state["cpu"]) if state["cpu"] else 0
    temp = cpu_temp()

    gauges = []  # (label, pct, sub, color+marker)
    c, m = level(cpu_avg)
    gauges.append(("CPU", cpu_avg, f"{temp}°C" if temp else "", c, m))
    if gpu:
        u, mu, mt, t = gpu[0]
        c, m = level(u)
        gauges.append(("GPU", u, f"{t}°C {mu:.1f}G", c, m))
    c, m = level(mem_pct)
    gauges.append(("MEM", mem_pct, f"{mem_used:.1f}/{mem_tot:.0f}G", c, m))
    bat = battery()
    if bat:
        pct, st, eta = bat
        c, m = level(pct, inv=True)
        sym = {"Charging": "▲ chg", "Discharging": "▼ " + eta, "Full": "● full"}.get(st, "● ac")
        gauges.append(("BAT", pct, sym.strip(), c, m))
    else:
        sw = (mem["SwapTotal"] - mem["SwapFree"]) / mem["SwapTotal"] * 100 if mem.get("SwapTotal") else 0
        gauges.append(("SWAP", sw, "", ACCENT, ""))

    cw = I // len(gauges)
    grids = [gauge(g[1], g[3]) for g in gauges]
    for r in range(3):
        lines.append("".join(center(grids[i][r], 6, cw) for i in range(len(gauges))))
    lines.append("".join(center(paint(TEXT, g[0] + (g[4] and " " + paint(g[3], g[4]) + TEXT)),
                                len(g[0]) + (2 if g[4] else 0), cw) for g in gauges))
    lines.append("".join(center(paint(DIM, g[2]), len(g[2]), cw) for g in gauges))

    # activity
    lines.append(section("ACTIVITY", I, "now"))
    sw_ = max(8, I - 28)
    cpu_c, _ = level(cpu_now)
    lines.append(f" {paint(TEXT, 'CPU')} {spark(state['cpu'], sw_, max(25, max(state['cpu'] or [0])), cpu_c)}  "
                 + paint(BRIGHT, f"{cpu_now:3.0f}%"))
    rx = state["rx"][-1] if state["rx"] else 0
    tx = state["tx"][-1] if state["tx"] else 0
    scale = max(max(state["rx"] + state["tx"] + [0]), 10 * 1024)
    lines.append(f" {paint(TEXT, 'NET')} {spark(state['rx'], sw_, scale, ACCENT)}  "
                 + paint(BRIGHT, f"↓{fmt_rate(rx)}") + " " + paint(TEXT, f"↑{fmt_rate(tx)}"))

    # storage
    du = shutil.disk_usage("/")
    dp = 100 * du.used / du.total
    dc, dm = level(dp, warn=80, crit=92)
    txt = f"{du.used / 2**30:.0f}/{du.total / 2**30:.0f}G"
    bw = max(8, I - 6 - len(txt) - 3)
    lines.append(section("STORAGE", I, "/"))
    lines.append(f" {paint(TEXT, 'DISK')} {hbar(dp, bw, dc)} " + paint(BRIGHT, txt) + (" " + paint(dc, dm) if dm else ""))

    # footer
    try:
        osn = dict(l.strip().split("=", 1) for l in open("/etc/os-release") if "=" in l)["PRETTY_NAME"].strip('"')
        osn = osn.split(" (")[0]
    except (OSError, KeyError):
        osn = "Linux"
    bits = [("UP", uptime()), ("KERNEL", platform.release().split("-")[0]), ("OS", osn)]
    ros = os.environ.get("ROS_DISTRO")
    if ros:
        bits.append(("ROS", f"{ros}/{os.environ.get('ROS_DOMAIN_ID', '0')}"))
    lines.append(paint(DIM, " " + "─" * (I - 1)))
    lines.append(" " + "  ".join(paint(DIM, k) + " " + paint(TEXT, v) for k, v in bits))
    return "\n".join(lines)


def tiny(state):
    cpu = state["cpu"][-1] if state["cpu"] else 0
    mem = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
    mp = 100 * (1 - mem["MemAvailable"] / mem["MemTotal"])
    return f"{platform.node().split('.')[0]}  cpu {cpu:.0f}%  mem {mp:.0f}%  up {uptime()}"


def first_shell():
    """True if no banner ran in the last 20s (so splits and subshells skip the rain)."""
    path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "banner.stamp")
    try:
        recent = time.time() - os.path.getmtime(path) < 20
    except OSError:
        recent = False
    try:
        open(path, "w").close()
    except OSError:
        pass
    return not recent


def main():
    state = {"c": None, "n": None, "t": 0, "cpu": [], "rx": [], "tx": []}
    gpu = []
    th = threading.Thread(target=gpu_query, args=(gpu,), daemon=True)
    th.start()
    rain = (TTY and H >= 14 and W >= 30 and not os.environ.get("BANNER_NO_RAIN")
            and first_shell())
    if TTY:
        OUT.write("\033[?25l")
    run_sampling(state, 0.6 if rain else (0.3 if TTY else 0.1), rain_rows=4 if rain else 0)
    th.join(0.5)
    if TTY:
        OUT.write("\033[?25h")
    try:
        print(tiny(state) if W < 40 else card(state, gpu))
    except Exception:
        print(tiny(state))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception:
        pass
