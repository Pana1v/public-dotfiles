import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {Sparkline, LoadBar, loadColor, cssColor, tempFraction} from './graph.js';
import {HISTORY_LENGTH, formatBytes, formatRate, formatUptime, percentFmt} from './panel.js';

const DETAIL_GRAPH_WIDTH = 248;
const DETAIL_GRAPH_HEIGHT = 46;
const CORE_COLUMNS = 2;
const PROCESS_ROWS = 5;
const DEVICE_ROWS = 6;

const MiB = 1024 * 1024;

/** Section header with a right-aligned summary value. */
const SectionHeader = GObject.registerClass(
class SectionHeader extends St.BoxLayout {
    constructor(title) {
        super({style_class: 'sysmon-section-header'});

        const titleLabel = new St.Label({
            style_class: 'sysmon-section-title',
            text: title,
            y_align: Clutter.ActorAlign.CENTER,
        });
        // The value label takes the slack, so the title must never be the one
        // that gives way.
        titleLabel.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
        this._titleLabel = titleLabel;
        this.add_child(titleLabel);

        this._value = new St.Label({
            style_class: 'sysmon-section-value',
            x_expand: true,
            x_align: Clutter.ActorAlign.END,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._value);

        // Temperature is a separate label because it needs its own colour.
        // Concatenating it into the value string would tint it by load, so a
        // throttling chip at idle would read green and a cool chip under full
        // load would read red.
        this._temp = new St.Label({
            style_class: 'sysmon-section-temp',
            y_align: Clutter.ActorAlign.CENTER,
            visible: false,
        });
        this.add_child(this._temp);
    }

    setValue(text, colorFraction) {
        this._value.text = text;

        if (colorFraction !== undefined)
            this._value.set_style(`color: ${cssColor(loadColor(colorFraction))};`);
    }

    /** celsius of null hides the reading entirely. */
    setTemp(celsius) {
        this._temp.visible = celsius !== null && celsius !== undefined;

        if (!this._temp.visible)
            return;

        this._temp.text = `${Math.round(celsius)}\u00b0C`;
        this._temp.set_style(
            `color: ${cssColor(loadColor(tempFraction(celsius)))};`);
    }
});

/** One process row: name, pid, and a metric. */
const ProcessRow = GObject.registerClass(
class ProcessRow extends St.BoxLayout {
    constructor() {
        super({style_class: 'sysmon-process-row'});

        this._name = new St.Label({
            style_class: 'sysmon-process-name',
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._name.clutter_text.ellipsize = Pango.EllipsizeMode.END;

        this._metric = new St.Label({
            style_class: 'sysmon-process-metric',
            y_align: Clutter.ActorAlign.CENTER,
        });

        this.add_child(this._name);
        this.add_child(this._metric);
    }

    setProcess(proc, metricText, colorFraction) {
        if (!proc) {
            this.visible = false;
            return;
        }

        this.visible = true;
        this._name.text = proc.name || `pid ${proc.pid}`;
        this._metric.text = metricText;
        this._metric.set_style(`color: ${cssColor(loadColor(colorFraction))};`);
    }
});

/**
 * The dropdown the stock extension does not have: full-width history graphs,
 * per-core load, GPU detail, and what is actually consuming the machine.
 */
export const DetailMenu = GObject.registerClass(
class DetailMenu extends PopupMenu.PopupBaseMenuItem {
    constructor(coreCount) {
        super({
            reactive: false,
            can_focus: false,
            style_class: 'sysmon-detail',
        });

        this._coreCount = coreCount;

        const root = new St.BoxLayout({
            vertical: true,
            style_class: 'sysmon-detail-root',
            x_expand: true,
        });
        this.add_child(root);

        this._buildCpu(root);
        this._buildMemory(root);
        this._buildGpu(root);
        this._buildDevices(root);
        this._buildProcesses(root);
        this._buildFooter(root);
    }

    _graph(styleClass) {
        return new Sparkline({
            capacity: HISTORY_LENGTH,
            width: DETAIL_GRAPH_WIDTH,
            styleClass,
        });
    }

    _buildCpu(root) {
        this._cpuHeader = new SectionHeader('Processor');
        root.add_child(this._cpuHeader);

        this._cpuGraph = this._graph('sysmon-detail-graph');
        this._cpuGraph.height = DETAIL_GRAPH_HEIGHT;
        root.add_child(this._cpuGraph);

        // Per-core bars laid out in fixed columns so the block keeps a stable
        // height regardless of core count.
        const grid = new St.BoxLayout({style_class: 'sysmon-core-grid'});
        const columns = [];

        for (let c = 0; c < CORE_COLUMNS; c++) {
            const column = new St.BoxLayout({
                vertical: true,
                style_class: 'sysmon-core-column',
                x_expand: true,
            });
            columns.push(column);
            grid.add_child(column);
        }

        this._coreBars = [];

        for (let i = 0; i < this._coreCount; i++) {
            const row = new St.BoxLayout({style_class: 'sysmon-core-row'});

            row.add_child(new St.Label({
                style_class: 'sysmon-core-label',
                text: `${i}`,
                y_align: Clutter.ActorAlign.CENTER,
            }));

            const bar = new LoadBar({});
            row.add_child(bar);
            this._coreBars.push(bar);

            columns[i % CORE_COLUMNS].add_child(row);
        }

        root.add_child(grid);
    }

    _buildMemory(root) {
        this._memHeader = new SectionHeader('Memory');
        root.add_child(this._memHeader);

        this._memGraph = this._graph('sysmon-detail-graph');
        this._memGraph.height = DETAIL_GRAPH_HEIGHT;
        root.add_child(this._memGraph);

        this._swapRow = new SectionHeader('Swap');
        this._swapRow.add_style_class_name('sysmon-subrow');
        root.add_child(this._swapRow);

        this._netRow = new SectionHeader('Network');
        this._netRow.add_style_class_name('sysmon-subrow');
        root.add_child(this._netRow);
    }

    _buildGpu(root) {
        this._gpuHeader = new SectionHeader('Graphics');
        root.add_child(this._gpuHeader);

        this._gpuGraph = this._graph('sysmon-detail-graph');
        this._gpuGraph.height = DETAIL_GRAPH_HEIGHT;
        root.add_child(this._gpuGraph);

        this._vramRow = new SectionHeader('VRAM');
        this._vramRow.add_style_class_name('sysmon-subrow');
        root.add_child(this._vramRow);

        this._gpuSection = [this._gpuHeader, this._gpuGraph, this._vramRow];
    }

    _buildDevices(root) {
        this._devHeader = new SectionHeader('Devices');
        root.add_child(this._devHeader);

        // Fixed pool, like the process rows, so the menu does not reflow
        this._devRows = [];
        for (let i = 0; i < DEVICE_ROWS; i++) {
            const row = new SectionHeader('');
            row.add_style_class_name('sysmon-subrow');
            this._devRows.push(row);
            root.add_child(row);
        }

        this._devSection = [this._devHeader, ...this._devRows];
    }

    _buildProcesses(root) {
        root.add_child(new SectionHeader('Top by processor'));

        this._cpuRows = [];
        for (let i = 0; i < PROCESS_ROWS; i++) {
            const row = new ProcessRow();
            this._cpuRows.push(row);
            root.add_child(row);
        }

        root.add_child(new SectionHeader('Top by memory'));

        this._memRows = [];
        for (let i = 0; i < PROCESS_ROWS; i++) {
            const row = new ProcessRow();
            this._memRows.push(row);
            root.add_child(row);
        }
    }

    _buildFooter(root) {
        const footer = new St.BoxLayout({style_class: 'sysmon-footer'});

        this._uptime = new St.Label({
            style_class: 'sysmon-uptime',
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        footer.add_child(this._uptime);

        const launch = new St.Button({
            style_class: 'sysmon-launch',
            label: 'System Monitor',
        });
        launch.connect('clicked', () => {
            const app = Shell.AppSystem.get_default()
                .lookup_app('gnome-system-monitor.desktop');
            app?.activate();
        });
        footer.add_child(launch);

        root.add_child(footer);
    }

    // --- updates -----------------------------------------------------------

    /**
     * Called every tick, open or not, so the graphs show real history the
     * moment the menu opens instead of starting empty.
     */
    pushHistory(cpu, mem, gpu) {
        this._cpuGraph.push(cpu.load);
        this._memGraph.push(mem.load);

        if (gpu.available)
            this._gpuGraph.push(gpu.utilisation);
    }

    updateCpu(cpu, temp) {
        this._cpuHeader.setValue(percentFmt.format(cpu.load), cpu.load);
        this._cpuHeader.setTemp(temp.celsius);

        for (let i = 0; i < this._coreBars.length; i++)
            this._coreBars[i].setValue(cpu.cores[i]);
    }

    updateMemory(mem) {
        this._memHeader.setValue(
            `${formatBytes(mem.usedBytes)} / ${formatBytes(mem.totalBytes)}`,
            mem.load);

        this._swapRow.setValue(
            mem.swapTotalBytes > 0
                ? `${percentFmt.format(mem.swapLoad)} of ${formatBytes(mem.swapTotalBytes)}`
                : 'none',
            mem.swapLoad);
    }

    updateNet(net) {
        this._netRow.setValue(
            `↓ ${formatRate(net.inBytesPerSec)}/s   ↑ ${formatRate(net.outBytesPerSec)}/s`);
    }

    updateGpu(gpu) {
        const visible = gpu.available;
        this._gpuSection.forEach(w => (w.visible = visible));

        if (!visible)
            return;

        this._gpuHeader.setValue(
            percentFmt.format(gpu.utilisation), gpu.utilisation);
        this._gpuHeader.setTemp(gpu.celsius);

        const vramLoad = gpu.totalMiB > 0 ? gpu.usedMiB / gpu.totalMiB : 0;
        this._vramRow.setValue(
            `${(gpu.usedMiB / 1024).toFixed(1)} / ${(gpu.totalMiB / 1024).toFixed(1)} GiB`,
            vramLoad);
    }

    updateDevices(devices) {
        // Nothing with a battery means no section at all
        this._devSection.forEach(w => (w.visible = devices.length > 0));
        this._devHeader.setValue(`${devices.length}`);

        this._devRows.forEach((row, i) => {
            const d = devices[i];
            row.visible = !!d;
            if (!d)
                return;

            row._titleLabel.text = d.name;
            // Low charge is the bad end, the reverse of a load fraction
            row.setValue(`${d.charging ? '+ ' : ''}${d.percent}%`,
                1 - d.percent / 100);
        });
    }

    updateProcesses(proc, coreCount) {
        this._cpuRows.forEach((row, i) => {
            const p = proc.byCpu[i];
            // Per-process CPU is measured against a single core, so a busy
            // thread can exceed 100%; normalise against the whole machine for
            // the colour so one hot process does not paint the list red.
            row.setProcess(p, p ? percentFmt.format(p.cpu) : '',
                p ? p.cpu / coreCount : 0);
        });

        this._memRows.forEach((row, i) => {
            const p = proc.byMem[i];
            row.setProcess(p, p ? `${Math.round(p.residentBytes / MiB)} MB` : '',
                p ? Math.min(1, p.residentBytes / (4 * 1024 * MiB)) : 0);
        });
    }

    updateUptime(seconds) {
        this._uptime.text = `up ${formatUptime(seconds)}`;
    }
});
