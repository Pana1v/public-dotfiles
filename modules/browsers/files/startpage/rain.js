// Live digital rain behind the start page, in the palette's colours.
// Same look as the rain lock screen (modules/rice/tools/rain.py), drawn on a
// canvas. Off when palette.css sets --ascii: none, or when the system asks
// for reduced motion. requestAnimationFrame stops in hidden tabs on its own.
(() => {
  const css = getComputedStyle(document.documentElement);
  const v = (name, fallback) => (css.getPropertyValue(name).trim() || fallback);
  if (v("--ascii", "rain") === "none") return;
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const GLYPHS = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:.";
  const CELL = 18, FPS = 20, TRAIL = 22;
  const bg = v("--bg", "#000000"), accent = v("--accent", "#00ff41"), head = v("--fg", "#e6ffe6");

  const canvas = document.createElement("canvas");
  canvas.setAttribute("aria-hidden", "true");
  Object.assign(canvas.style, { position: "fixed", inset: "0", zIndex: "-1", width: "100vw", height: "100vh" });
  document.body.prepend(canvas);
  const ctx = canvas.getContext("2d");

  let cols = 0, rows = 0, drops = [];
  const pick = () => GLYPHS[(Math.random() * GLYPHS.length) | 0];
  function resize() {
    const dpr = window.devicePixelRatio || 1;
    canvas.width = innerWidth * dpr;
    canvas.height = innerHeight * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    cols = Math.ceil(innerWidth / CELL);
    rows = Math.ceil(innerHeight / CELL);
    drops = Array.from({ length: cols }, () => ({
      y: Math.random() * -rows, speed: 0.25 + Math.random() * 0.55,
    }));
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, innerWidth, innerHeight);
    ctx.font = `${CELL - 2}px "Noto Sans CJK JP", "JetBrains Mono", monospace`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
  }

  let last = 0;
  function tick(t) {
    requestAnimationFrame(tick);
    if (t - last < 1000 / FPS) return;
    last = t;
    // Fade the previous frame towards the background: this draws the trails.
    ctx.globalAlpha = 1 / (TRAIL * 0.45);
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, innerWidth, innerHeight);
    ctx.globalAlpha = 1;
    for (let c = 0; c < cols; c++) {
      const d = drops[c];
      const r = Math.floor(d.y);
      if (r >= 0) {
        const x = c * CELL + CELL / 2;
        // Repaint the cell above the head in the accent, then the bright head.
        ctx.fillStyle = accent;
        ctx.fillText(pick(), x, (r - 1) * CELL + CELL / 2);
        ctx.fillStyle = head;
        ctx.fillText(pick(), x, r * CELL + CELL / 2);
      }
      d.y += d.speed;
      if (r > rows + TRAIL * Math.random()) {
        d.y = Math.random() * -rows * 0.5;
        d.speed = 0.25 + Math.random() * 0.55;
      }
    }
  }

  addEventListener("resize", resize);
  resize();
  requestAnimationFrame(tick);
})();
