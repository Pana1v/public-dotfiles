import GLib from 'gi://GLib';
const EXT = '/home/pan-navigator/.local/share/gnome-shell/extensions/sysmon-flair@pan.local';
const S = await import(`file://${EXT}/src/sources.js`);

const loop = new GLib.MainLoop(null, false);
const cpu = new S.CpuSource(), mem = new S.MemSource(), net = new S.NetSource();
const temp = new S.TempSource(), gpu = new S.GpuSource(), proc = new S.ProcessSource();

gpu.start();
[cpu, mem, net, temp].forEach(s => s.update());
proc.update();

let n = 0;
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
  [cpu, mem, net, temp].forEach(s => s.update());
  n++;
  if (n < 3) return GLib.SOURCE_CONTINUE;

  print('cores reported      : ' + cpu.coreCount + '  (nproc=' + GLib.get_num_processors() + ')');
  print('cpu load            : ' + (cpu.load*100).toFixed(1) + '%');
  print('per-core sample     : ' + cpu.cores.slice(0,8).map(c=>(c*100).toFixed(0)).join(' '));
  print('per-core array len  : ' + cpu.cores.length);
  print('mem                 : ' + (mem.load*100).toFixed(1) + '%  ' + (mem.usedBytes/1e9).toFixed(1) + '/' + (mem.totalBytes/1e9).toFixed(1) + ' GB');
  print('swap                : ' + (mem.swapLoad*100).toFixed(1) + '%');
  print('net in/out          : ' + (net.inBytesPerSec/1024).toFixed(1) + ' / ' + (net.outBytesPerSec/1024).toFixed(1) + ' KB/s');
  print('cpu temp available  : ' + temp.available + '  -> ' + (temp.celsius ?? 'n/a') + ' C  [' + temp._path + ']');
  print('gpu available       : ' + gpu.available);
  if (gpu.available)
    print('gpu                 : ' + (gpu.utilisation*100).toFixed(0) + '%  ' + gpu.celsius + 'C  ' + gpu.usedMiB + '/' + gpu.totalMiB + ' MiB');

  proc.update();
  print('top by cpu          :');
  proc.byCpu.forEach(p => print('   ' + String(p.pid).padStart(7) + '  ' + (p.cpu*100).toFixed(1).padStart(5) + '%  ' + p.name));
  print('top by mem          :');
  proc.byMem.forEach(p => print('   ' + String(p.pid).padStart(7) + '  ' + (p.residentBytes/1e6).toFixed(0).padStart(5) + ' MB  ' + p.name));
  print('uptime              : ' + (S.uptimeSeconds()/3600).toFixed(2) + ' h');

  gpu.stop(); loop.quit();
  return GLib.SOURCE_REMOVE;
});
loop.run();
