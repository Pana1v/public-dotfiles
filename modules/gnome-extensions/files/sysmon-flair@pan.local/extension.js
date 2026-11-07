import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

import {
    CpuSource, MemSource, NetSource, TempSource, GpuSource, ProcessSource, DevicesSource,
    uptimeSeconds,
} from './src/sources.js';
import {StatChip, tagged, formatUsage, formatRate} from './src/panel.js';
import {DetailMenu} from './src/menu.js';
import {HeatGlow} from './src/heat.js';
import {watchPalette} from './src/palette.js';

const PANEL_ROLE = 'sysmon-flair';
const PANEL_BOX = 'right';
const PANEL_INDEX = 0;

const TICK_SEC = 1;

// Fits "8.1/62G" at the chip value font size.
const USAGE_CHIP_WIDTH = 66;

const MIB = 1024 * 1024;

// Download graph and colour need a 0..1 load. 200 Mbit/s reads as full; a
// faster link just pins the graph at the top while the number stays exact.
const NET_FULL_SCALE_BYTES = 25 * 1000 * 1000;

// Walking every PID costs three GTop syscalls each, and this machine runs ~600
// processes. Sampling that at 1Hz on the compositor thread is not worth it, so
// the process list refreshes every few ticks instead.
const PROCESS_EVERY_N_TICKS = 3;

const SysmonIndicator = GObject.registerClass(
class SysmonIndicator extends PanelMenu.Button {
    constructor(coreCount) {
        super(0.5, 'System Monitor Flair');

        this.add_style_class_name('sysmon-indicator');

        this._box = new St.BoxLayout({style_class: 'sysmon-panel'});
        this.add_child(this._box);

        // Panel carries what decides whether a job fits: load, heat and
        // memory headroom, plus download rate. Swap, upload and per-core live
        // in the dropdown.
        this.cpu = new StatChip({
            accessibleName: 'Processor load and temperature',
            withTemp: true,
        });
        this.ram = new StatChip({
            accessibleName: 'Memory used',
            width: USAGE_CHIP_WIDTH,
        });
        this.gpu = new StatChip({
            accessibleName: 'Graphics load and temperature',
            withTemp: true,
        });
        this.vram = new StatChip({
            accessibleName: 'Graphics memory used',
            width: USAGE_CHIP_WIDTH,
        });

        this._box.add_child(tagged('C', this.cpu));
        this._box.add_child(tagged('R', this.ram));

        // One box so a machine without nvidia-smi hides both GPU chips.
        this.gpuGroup = new St.BoxLayout({style_class: 'sysmon-panel'});
        this.gpuGroup.add_child(tagged('G', this.gpu));
        this.gpuGroup.add_child(tagged('V', this.vram));
        this._box.add_child(this.gpuGroup);

        this.down = new StatChip({accessibleName: 'Download speed'});
        this._box.add_child(tagged('↓', this.down));

        this.detail = new DetailMenu(coreCount);
        this.menu.addMenuItem(this.detail);
    }
});

export default class SysmonFlairExtension extends Extension {
    enable() {
        this._cpu = new CpuSource();
        this._mem = new MemSource();
        this._net = new NetSource();
        this._temp = new TempSource();
        this._gpu = new GpuSource();
        this._proc = new ProcessSource();
        this._devices = new DevicesSource();

        this._gpu.start();

        this._indicator = new SysmonIndicator(this._cpu.coreCount);
        this._heat = new HeatGlow();
        // A theme switch rewrites the palette file; repaint with the new colours.
        this._unwatchPalette = watchPalette(() => this._tick());

        this._menuId = this._indicator.menu.connect('open-state-changed',
            (menu, open) => {
                this._menuOpen = open;

                if (!open)
                    return;

                // Process CPU needs two samples to mean anything. Prime the
                // baseline now and paint everything else immediately; the list
                // fills in on the next tick rather than showing a column of
                // zeros.
                this._proc.reset();
                this._proc.update();

                this._tick();
                this._procPending = true;
            });

        Main.panel.addToStatusArea(
            PANEL_ROLE, this._indicator, PANEL_INDEX, PANEL_BOX);

        // Prime the counters so the first visible sample is a real delta
        // rather than a meaningless zero.
        this._sample();

        this._tickId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, TICK_SEC, () => {
                this._tick();
                return GLib.SOURCE_CONTINUE;
            });
    }

    _sample() {
        this._cpu.update();
        this._mem.update();
        this._net.update();
        this._temp.update();
    }

    _tick() {
        this._ticks = (this._ticks ?? 0) + 1;

        this._sample();

        this._updatePanel();

        const gpuLoad = this._gpu.available ? this._gpu.utilisation : 0;
        this._heat.update(Math.max(this._cpu.load, this._mem.load, gpuLoad));

        this._indicator.detail.pushHistory(this._cpu, this._mem, this._gpu);

        if (this._menuOpen)
            this._updateDetail();
    }

    _updatePanel() {
        const {cpu, ram, gpu, vram, gpuGroup, down} = this._indicator;

        cpu.update(this._cpu.load);
        cpu.setTemp(this._temp.celsius);

        const mem = this._mem;
        ram.update(mem.load, formatUsage(mem.usedBytes, mem.totalBytes));

        const rate = this._net.inBytesPerSec;
        down.update(Math.min(1, rate / NET_FULL_SCALE_BYTES), formatRate(rate));

        gpuGroup.visible = this._gpu.available;
        if (!gpuGroup.visible)
            return;

        const g = this._gpu;
        gpu.update(g.utilisation);
        gpu.setTemp(g.celsius);

        const vramLoad = g.totalMiB > 0 ? g.usedMiB / g.totalMiB : 0;
        vram.update(vramLoad, formatUsage(g.usedMiB * MIB, g.totalMiB * MIB));
    }

    _procDue() {
        if (this._procPending) {
            this._procPending = false;
            return true;
        }

        return this._ticks % PROCESS_EVERY_N_TICKS === 0;
    }

    _updateDetail() {
        const detail = this._indicator.detail;

        if (this._procDue())
            this._proc.update();

        detail.updateCpu(this._cpu, this._temp);
        detail.updateMemory(this._mem);
        detail.updateNet(this._net);
        detail.updateGpu(this._gpu);
        this._devices.update();
        detail.updateDevices(this._devices.devices);
        detail.updateProcesses(this._proc, this._cpu.coreCount);
        detail.updateUptime(uptimeSeconds());
    }

    disable() {
        if (this._tickId)
            GLib.source_remove(this._tickId);
        this._tickId = 0;

        if (this._menuId)
            this._indicator?.menu.disconnect(this._menuId);
        this._menuId = 0;

        this._gpu?.stop();
        this._unwatchPalette?.();
        this._unwatchPalette = null;
        this._heat?.destroy();
        this._heat = null;
        this._indicator?.destroy();

        this._indicator = null;
        this._cpu = null;
        this._mem = null;
        this._net = null;
        this._temp = null;
        this._gpu = null;
        this._proc = null;
        this._menuOpen = false;
        this._procPending = false;
    }
}
