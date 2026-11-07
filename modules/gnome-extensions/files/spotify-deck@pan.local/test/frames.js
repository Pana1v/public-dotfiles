// Unit-tests VizEngine._consume() with synthetic cava output.
// cava emits BAR_COUNT unsigned 16-bit little-endian samples per frame.
import GLib from 'gi://GLib';
const EXT = '/home/pan-navigator/.local/share/gnome-shell/extensions/spotify-deck@pan.local';
const {VizEngine} = await import(`file://${EXT}/src/viz.js`);

const BARS = 4;
const eng = new VizEngine(BARS);
eng._buffer = new Uint8Array(BARS * 2 * 8);
eng._bufferUsed = 0;

let last = null;
eng.connect('bars', (_e, b) => { last = [...b]; });

function frame(vals) {
  const buf = new Uint8Array(vals.length * 2);
  const dv = new DataView(buf.buffer);
  vals.forEach((v, i) => dv.setUint16(i * 2, v, true));   // little-endian
  return buf;
}
function concat(...arrs) {
  const total = arrs.reduce((n, a) => n + a.length, 0);
  const out = new Uint8Array(total);
  let o = 0; arrs.forEach(a => { out.set(a, o); o += a.length; });
  return out;
}

let pass = 0, fail = 0;
const check = (name, cond, detail='') => {
  if (cond) { pass++; print(`  PASS  ${name}`); }
  else { fail++; print(`  FAIL  ${name}  ${detail}`); }
};

print('--- single full frame, endianness + scaling ---');
// Smoothing is asymmetric; drive it to steady state before asserting values.
for (let i = 0; i < 400; i++) eng._consume(frame([0, 21845, 43690, 65535]));
check('bar0 ~ 0.00', Math.abs(last[0] - 0.0) < 0.01, `got ${last[0]}`);
check('bar1 ~ 0.33', Math.abs(last[1] - 1/3) < 0.01, `got ${last[1]}`);
check('bar2 ~ 0.67', Math.abs(last[2] - 2/3) < 0.01, `got ${last[2]}`);
check('bar3 ~ 1.00', Math.abs(last[3] - 1.0) < 0.01, `got ${last[3]}`);

print('--- newest frame wins when several arrive at once ---');
for (let i = 0; i < 400; i++)
  eng._consume(concat(frame([0,0,0,0]), frame([0,0,0,0]), frame([65535,65535,65535,65535])));
check('takes last frame, not first', last.every(v => v > 0.98), `got ${last.map(v=>v.toFixed(2))}`);

print('--- partial trailing frame is retained, not dropped ---');
eng._bufferUsed = 0;
const full = frame([65535, 0, 65535, 0]);
const partial = full.slice(0, 3);            // 3 of 8 bytes
eng._consume(concat(full, partial));
check('3 leftover bytes kept in buffer', eng._bufferUsed === 3, `bufferUsed=${eng._bufferUsed}`);
// feeding the rest must complete that frame
eng._consume(full.slice(3));
check('split frame reassembles', eng._bufferUsed === 0, `bufferUsed=${eng._bufferUsed}`);

print('--- buffer grows for oversized chunk ---');
eng._bufferUsed = 0;
const big = concat(...Array(20).fill(frame([1,2,3,4])));
eng._consume(big);
check('no overflow on large chunk', eng._bufferUsed === 0 && eng._buffer.length >= big.length,
      `used=${eng._bufferUsed} cap=${eng._buffer.length}`);

print(`\nRESULT: ${pass} passed, ${fail} failed`);
