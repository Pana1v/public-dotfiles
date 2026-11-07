import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GTop from 'gi://GTop';

const HWMON_ROOT = '/sys/class/hwmon';

// Intel and AMD expose package temperature under different driver names.
const CPU_TEMP_DRIVERS = ['coretemp', 'k10temp', 'zenpower'];

const MILLIDEGREE = 1000;

// Overlay, bridge and virtual interfaces carry traffic that also traverses a
// physical NIC, so counting them would inflate the reading.
const VIRTUAL_IFACE_PREFIXES = [
    'lo', 'br-', 'docker', 'veth', 'virbr', 'tailscale', 'tun', 'tap', 'wg',
];

const GPU_POLL_SEC = 2;

const POWER_ROOT = '/sys/class/power_supply';
// Snapshot written by the conky feeds service (see conky/Common/feeds.py)
const BUDS_FEED = `${GLib.get_home_dir()}/.cache/conky/cmf_buds.tsv`;

/** GTop sizes per-core arrays to a compile-time maximum, not the real count. */
const CORE_COUNT = GLib.get_num_processors();

/**
 * Decodes GTop's fixed-size, NUL-padded command byte array.
 * Reading it directly yields raw numbers rather than a process name.
 */
function decodeCmd(bytes) {
    if (!bytes)
        return '';

    const end = bytes.indexOf(0);
    const slice = end === -1 ? bytes : bytes.slice(0, end);

    return String.fromCharCode(...slice);
}

/**
 * The kernel name is cut to 15 characters ("falcon-sensor-b") and some
 * binaries are named after their version ("2.1.310" for claude), so argv[0]
 * names a program better. Kernel threads have no argv and keep their name.
 */
function programName(pid, kernelName) {
    try {
        const [, bytes] = GLib.file_get_contents(`/proc/${pid}/cmdline`);
        // Some programs rewrite argv[0] into a title ("sshd: pan@pts/0"),
        // so take the first word before treating it as a path.
        const word = decodeCmd(bytes).split(' ')[0].replace(/:$/, '');
        const name = word.includes('/') ? GLib.path_get_basename(word) : word;
        return name || kernelName;
    } catch {
        return kernelName;
    }
}

/** Samples CPU load overall and per core from cumulative jiffy counters. */
export class CpuSource {
    constructor() {
        this._prev = null;
        this._prevCores = new Array(CORE_COUNT).fill(null);

        this.load = 0;
        this.cores = new Array(CORE_COUNT).fill(0);
    }

    get coreCount() {
        return CORE_COUNT;
    }

    update() {
        const cpu = new GTop.glibtop_cpu();
        GTop.glibtop_get_cpu(cpu);

        this.load = this._delta(this._prev, cpu);
        this._prev = {
            total: cpu.total,
            busy: cpu.user + cpu.sys + cpu.nice,
        };

        for (let i = 0; i < CORE_COUNT; i++) {
            const sample = {
                total: cpu.xcpu_total[i],
                busy: cpu.xcpu_user[i] + cpu.xcpu_sys[i] + cpu.xcpu_nice[i],
            };

            this.cores[i] = this._delta(this._prevCores[i], sample);
            this._prevCores[i] = sample;
        }
    }

    /** Counters are cumulative; load is the ratio of the deltas. */
    _delta(prev, next) {
        const busy = next.busy ?? (next.user + next.sys + next.nice);

        if (!prev)
            return 0;

        const totalDelta = next.total - prev.total;
        const busyDelta = busy - prev.busy;

        if (totalDelta <= 0)
            return 0;

        return Math.max(0, Math.min(1, busyDelta / totalDelta));
    }
}

export class MemSource {
    constructor() {
        this.load = 0;
        this.usedBytes = 0;
        this.totalBytes = 0;

        this.swapLoad = 0;
        this.swapUsedBytes = 0;
        this.swapTotalBytes = 0;
    }

    update() {
        const mem = new GTop.glibtop_mem();
        GTop.glibtop_get_mem(mem);

        this.usedBytes = mem.user;
        this.totalBytes = mem.total;
        this.load = mem.total > 0 ? mem.user / mem.total : 0;

        const swap = new GTop.glibtop_swap();
        GTop.glibtop_get_swap(swap);

        this.swapUsedBytes = swap.used;
        this.swapTotalBytes = swap.total;
        this.swapLoad = swap.total > 0 ? swap.used / swap.total : 0;
    }
}

/** Aggregates throughput across physical interfaces only. */
export class NetSource {
    constructor() {
        this._prevIn = 0;
        this._prevOut = 0;
        this._prevClock = 0;

        this.inBytesPerSec = 0;
        this.outBytesPerSec = 0;
    }

    _isPhysical(name) {
        return !VIRTUAL_IFACE_PREFIXES.some(p => name.startsWith(p));
    }

    update() {
        const netlist = new GTop.glibtop_netlist();
        const devices = GTop.glibtop_get_netlist(netlist);

        let totalIn = 0;
        let totalOut = 0;

        for (const device of devices) {
            if (!this._isPhysical(device))
                continue;

            const load = new GTop.glibtop_netload();
            GTop.glibtop_get_netload(load, device);

            totalIn += load.bytes_in;
            totalOut += load.bytes_out;
        }

        const now = GLib.get_monotonic_time() / 1000000;
        const elapsed = now - this._prevClock;

        // First sample has no baseline, and a counter that went backwards means
        // an interface disappeared; either way, report nothing rather than a
        // fabricated spike.
        if (this._prevClock > 0 && elapsed > 0 &&
            totalIn >= this._prevIn && totalOut >= this._prevOut) {
            this.inBytesPerSec = (totalIn - this._prevIn) / elapsed;
            this.outBytesPerSec = (totalOut - this._prevOut) / elapsed;
        }

        this._prevIn = totalIn;
        this._prevOut = totalOut;
        this._prevClock = now;
    }
}

/**
 * Reads CPU package temperature from sysfs.
 *
 * hwmon indices are assigned in driver probe order and are not stable across
 * reboots, so the sensor is resolved by driver name every time rather than
 * pinned to a path like hwmon8.
 */
export class TempSource {
    constructor() {
        this.celsius = null;
        this._path = null;
        this._resolve();
    }

    get available() {
        return this._path !== null;
    }

    _resolve() {
        let dir;
        try {
            dir = Gio.File.new_for_path(HWMON_ROOT);
            const iter = dir.enumerate_children(
                'standard::name', Gio.FileQueryInfoFlags.NONE, null);

            let info;
            while ((info = iter.next_file(null)) !== null) {
                const name = this._readText(
                    `${HWMON_ROOT}/${info.get_name()}/name`);

                if (!CPU_TEMP_DRIVERS.includes(name))
                    continue;

                const candidate =
                    `${HWMON_ROOT}/${info.get_name()}/temp1_input`;

                if (GLib.file_test(candidate, GLib.FileTest.EXISTS)) {
                    this._path = candidate;
                    break;
                }
            }
            iter.close(null);
        } catch (e) {
            this._path = null;
        }
    }

    _readText(path) {
        try {
            const [ok, bytes] = GLib.file_get_contents(path);
            return ok ? new TextDecoder().decode(bytes).trim() : null;
        } catch (e) {
            return null;
        }
    }

    update() {
        if (!this._path)
            return;

        const raw = this._readText(this._path);
        this.celsius = raw === null ? null : parseInt(raw, 10) / MILLIDEGREE;
    }
}

/**
 * Reads NVIDIA GPU stats from a single long-lived nvidia-smi process.
 *
 * Spawning nvidia-smi once per second would cost a process launch and roughly
 * 50-100ms of work each tick; --loop keeps one process streaming lines that we
 * read asynchronously, the same thin-pipe contract used for the audio helper.
 */
export class GpuSource {
    constructor() {
        this.available = false;
        this.utilisation = 0;
        this.celsius = null;
        this.usedMiB = 0;
        this.totalMiB = 0;

        this._proc = null;
        this._stdout = null;
        this._cancellable = null;
    }

    start() {
        if (!GLib.find_program_in_path('nvidia-smi'))
            return;

        try {
            const launcher = new Gio.SubprocessLauncher({
                flags: Gio.SubprocessFlags.STDOUT_PIPE |
                       Gio.SubprocessFlags.STDERR_SILENCE,
            });

            this._proc = launcher.spawnv([
                'nvidia-smi',
                '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total',
                '--format=csv,noheader,nounits',
                `--loop=${GPU_POLL_SEC}`,
            ]);

            this._cancellable = new Gio.Cancellable();
            this._stdout = new Gio.DataInputStream({
                base_stream: this._proc.get_stdout_pipe(),
            });

            this._readLine();
        } catch (e) {
            logError(e, 'sysmon-flair: nvidia-smi launch failed');
            this.stop();
        }
    }

    _readLine() {
        if (!this._stdout || this._cancellable?.is_cancelled())
            return;

        this._stdout.read_line_async(
            GLib.PRIORITY_DEFAULT, this._cancellable, (stream, res) => {
                let line;
                try {
                    [line] = stream.read_line_finish_utf8(res);
                } catch (e) {
                    if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        this.available = false;
                    return;
                }

                if (line === null) {
                    this.available = false;
                    return;
                }

                this._parse(line);
                this._readLine();
            });
    }

    _parse(line) {
        const parts = line.split(',').map(s => parseFloat(s.trim()));
        if (parts.length < 4 || parts.some(Number.isNaN))
            return;

        const [util, temp, used, total] = parts;

        this.utilisation = util / 100;
        this.celsius = temp;
        this.usedMiB = used;
        this.totalMiB = total;
        this.available = true;
    }

    stop() {
        this._cancellable?.cancel();
        this._cancellable = null;

        try {
            this._proc?.force_exit();
        } catch (e) {
            // Already exited.
        }

        this._proc = null;
        this._stdout = null;
        this.available = false;
    }
}

/**
 * Ranks running processes by CPU and memory.
 *
 * This walks every PID on the system, so it is only sampled while the detail
 * menu is actually open rather than on the panel's own tick.
 */
export class ProcessSource {
    constructor() {
        this._prevTimes = new Map();
        this._prevClock = 0;

        this.byCpu = [];
        this.byMem = [];
    }

    update() {
        // Two samples taken microseconds apart would divide a tiny CPU delta by
        // a near-zero window and report nonsense percentages. Below this gap the
        // previous ranking stands.
        const MIN_WINDOW_SEC = 0.2;

        const clock = GLib.get_monotonic_time() / 1000000;
        if (this._prevClock > 0 && clock - this._prevClock < MIN_WINDOW_SEC)
            return;

        const proclist = new GTop.glibtop_proclist();
        const pids = GTop.glibtop_get_proclist(
            proclist, GTop.GLIBTOP_KERN_PROC_ALL, 0);

        const now = GLib.get_monotonic_time() / 1000000;
        const elapsed = now - this._prevClock;
        const times = new Map();
        const rows = [];

        for (const pid of pids) {
            const time = new GTop.glibtop_proc_time();
            GTop.glibtop_get_proc_time(time, pid);

            const ticks = time.utime + time.stime;
            const frequency = time.frequency || 100;
            times.set(pid, {ticks, frequency});

            const mem = new GTop.glibtop_proc_mem();
            GTop.glibtop_get_proc_mem(mem, pid);

            const state = new GTop.glibtop_proc_state();
            GTop.glibtop_get_proc_state(state, pid);

            const prev = this._prevTimes.get(pid);
            let cpu = 0;

            if (prev && elapsed > 0 && ticks >= prev.ticks)
                cpu = ((ticks - prev.ticks) / frequency) / elapsed;

            rows.push({
                pid,
                name: decodeCmd(state.cmd),
                cpu,
                residentBytes: mem.resident,
            });
        }

        this._prevTimes = times;
        this._prevClock = now;

        this.byCpu = [...rows].sort((a, b) => b.cpu - a.cpu).slice(0, 5);
        this.byMem = [...rows]
            .sort((a, b) => b.residentBytes - a.residentBytes).slice(0, 5);

        // Only the shown rows get the costlier name lookup.
        for (const row of [...this.byCpu, ...this.byMem])
            row.name = programName(row.pid, row.name);
    }

    reset() {
        this._prevTimes.clear();
        this._prevClock = 0;
    }
}

export function uptimeSeconds() {
    const up = new GTop.glibtop_uptime();
    GTop.glibtop_get_uptime(up);
    return up.uptime;
}

/**
 * Things with a battery: the laptop, plus any bluetooth device the kernel
 * exposes under power_supply, plus the earbuds from the conky feed (they talk
 * a vendor protocol the kernel knows nothing about).
 */
export class DevicesSource {
    constructor() {
        // [{name, percent, charging}], laptop first
        this.devices = [];
    }

    _readText(path) {
        try {
            const [ok, bytes] = GLib.file_get_contents(path);
            return ok ? new TextDecoder().decode(bytes).trim() : null;
        } catch {
            return null;
        }
    }

    _powerSupplies() {
        const found = [];
        let iter;
        try {
            iter = Gio.File.new_for_path(POWER_ROOT).enumerate_children(
                'standard::name', Gio.FileQueryInfoFlags.NONE, null);
        } catch {
            return found;
        }

        let info;
        while ((info = iter.next_file(null)) !== null) {
            const dir = `${POWER_ROOT}/${info.get_name()}`;
            if (this._readText(`${dir}/type`) !== 'Battery')
                continue;

            const percent = parseInt(this._readText(`${dir}/capacity`), 10);
            if (Number.isNaN(percent))
                continue;

            const isLaptop = this._readText(`${dir}/scope`) !== 'Device';
            const model = this._readText(`${dir}/model_name`);
            found.push({
                name: isLaptop ? 'Laptop' : (model || info.get_name()),
                percent,
                charging: this._readText(`${dir}/status`) === 'Charging',
                laptop: isLaptop,
            });
        }
        iter.close(null);

        return found.sort((a, b) => b.laptop - a.laptop);
    }

    _buds() {
        const text = this._readText(BUDS_FEED);
        if (!text)
            return [];

        const rows = text.split('\n').map(l => l.split('\t'));
        if (!rows.some(r => r[0] === 'state' && r[1] === 'connected'))
            return [];

        const label = {left: 'Buds left', right: 'Buds right', case: 'Buds case'};
        return rows
            .filter(r => r[0] === 'battery' && label[r[1]])
            .map(r => ({
                name: label[r[1]],
                percent: parseInt(r[2], 10),
                charging: r[3] === '1',
            }))
            .filter(d => !Number.isNaN(d.percent));
    }

    update() {
        this.devices = [...this._powerSupplies(), ...this._buds()];
    }
}
