import type { Register, ThemeSetArgs } from 'claude-code'

import { makeColors } from './make-colors.js'

// Ares rice (modules/rice/themes/ares.palette): black and red program glow,
// cyan kept for "good" states, with the ember black hole moving behind it.
const P = {
  bg: '#0a0506',
  bg3: '#120809',
  card: '#1a0b0d',
  menu: '#1f0c0f',
  fg: '#ffe9eb',
  fg2: '#f2c4c8',
  dim2: '#b86a72',
  accent: '#ff1f3d',
  orange: '#ff7a29',
  red: '#ff3b1f',
  cyan: '#52e5ff',
  yellow: '#ffc14d',
  magenta: '#ff4f8b',
}

const { theme, problems } = makeColors({
  label: 'Ares black hole',
  only: 'dark',
  roles: { accent: P.accent, danger: P.red, success: P.cyan, warning: P.yellow, pro: P.magenta },
  dark: {
    gray: {
      anchors: {
        'surface-0': P.bg,
        'surface-1': P.bg3,
        'surface-2': P.card,
        'surface-3': P.menu,
        'text-primary': P.fg,
        'text-secondary': P.fg2,
        'text-muted': P.dim2,
      },
    },
  },
})

// ---------- the scene: a CSS-animated ember black hole ----------

const RINGS = [
  { rx: 150, w: 5, dash: [40, 16, 90, 22], dur: 5, c: P.fg, op: 0.9 },
  { rx: 185, w: 7, dash: [70, 30, 24, 40], dur: 10, c: P.orange, op: 0.85 },
  { rx: 225, w: 9, dash: [120, 50, 30, 28], dur: 15, c: P.accent, op: 0.8 },
  { rx: 270, w: 10, dash: [90, 60, 160, 40], dur: 20, c: P.accent, op: 0.6 },
  { rx: 330, w: 12, dash: [60, 80, 40, 90], dur: 30, c: P.accent, op: 0.4 },
]
const ARCS = [118, 138, 166]
const sum = (a: number[]) => a.reduce((s, n) => s + n, 0)

function scene(): string {
  const css = [
    '.spin{transform-box:fill-box;transform-origin:center;animation:spin 40s linear infinite}',
    '@keyframes spin{to{transform:rotate(360deg)}}',
    '.breathe{transform-box:fill-box;transform-origin:center;animation:breathe 5s ease-in-out infinite}',
    '@keyframes breathe{50%{transform:scale(1.08);opacity:.8}}',
    '.pulse{animation:pulse 5s ease-in-out infinite}',
    '@keyframes pulse{50%{stroke-opacity:.35}}',
    '.grain{animation:grain .6s steps(6) infinite}',
    '@keyframes grain{0%{transform:translate(0,0)}20%{transform:translate(-37px,23px)}40%{transform:translate(19px,-41px)}60%{transform:translate(-11px,-17px)}80%{transform:translate(43px,29px)}100%{transform:translate(0,0)}}',
    ...RINGS.map((r, i) => `.r${i}{animation:r${i} ${r.dur}s linear infinite}@keyframes r${i}{to{stroke-dashoffset:${-sum(r.dash)}}}`),
    ...ARCS.map((_, i) => `.a${i}{animation:a${i} ${10 * (1 + i * 0.6)}s linear infinite}@keyframes a${i}{to{stroke-dashoffset:${-(210 + i * 60)}}}`),
    // Narrow or tall boxes: shrink the hole so it stays in its corner.
    
  ].join('')

  const disk = RINGS.map(
    (r, i) => `<ellipse class="r${i}" rx="${r.rx}" ry="${r.rx * 0.2}" fill="none" stroke="${r.c}" stroke-width="${r.w}" stroke-opacity="${r.op}" stroke-dasharray="${r.dash.join(' ')}" filter="url(#soft)"/>`,
  ).join('')
  const arcs = ARCS.map(
    (rx, i) => `<circle class="a${i}" r="${rx}" fill="none" stroke="${i ? P.accent : P.orange}" stroke-width="${6 + i * 3}" stroke-opacity="${0.55 - i * 0.12}" stroke-dasharray="${150 + i * 40} ${60 + i * 20}" filter="url(#soft)"/>`,
  ).join('')

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" width="1600" height="900" preserveAspectRatio="xMaxYMax slice">
<style>${css}</style>
<defs>
<radialGradient id="halo"><stop offset="0" stop-color="${P.accent}" stop-opacity=".5"/><stop offset=".35" stop-color="${P.accent}" stop-opacity=".16"/><stop offset="1" stop-color="${P.accent}" stop-opacity="0"/></radialGradient>
<filter id="soft" x="-20%" y="-60%" width="140%" height="220%"><feGaussianBlur stdDeviation="2.2"/></filter>
<filter id="noise"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 1  0 0 0 0 .9  0 0 0 0 .9  0 0 0 .55 -.2"/></filter>
</defs>
<rect x="-800" y="-800" width="3200" height="2500" fill="${P.bg}"/>
<g transform="translate(1260 560)"><g class="hole">
  <circle class="breathe" r="520" fill="url(#halo)"/>
  <g transform="rotate(-14)">${disk}</g>
  <g class="spin">${arcs}</g>
  <circle r="104" fill="#000"/>
  <circle r="106" fill="none" stroke="${P.fg}" stroke-width="2" stroke-opacity=".9" filter="url(#soft)"/>
  <circle class="pulse" r="110" fill="none" stroke="${P.orange}" stroke-width="5" stroke-opacity=".7" filter="url(#soft)"/>
</g></g>
<g opacity=".09"><rect class="grain" x="-60" y="-60" width="1720" height="1020" filter="url(#noise)"/></g>
</svg>`
}

const LOOK: ThemeSetArgs = {
  colors: theme,
  overrideColorScheme: 'dark',
  backdrop: { scene: 'blackhole', glass: { blur: 10, tint: P.bg, opacity: 0.45 } },
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const unpainted = problems.find(line => line.startsWith("Desktop won't paint"))
    if (unpainted !== undefined) $.ui.toast(unpainted)

    const set = await $.theme.set(LOOK)
    if (!set.isDrawn) $.ui.status(set.reason)

    return next(e)
  })

  on('ui.render', { component: 'Backdrop' }, ($, e, next) => {
    if (e.surface !== 'desktop' && e.surface !== 'mobile') return next(e)
    if (e.props.scene !== 'blackhole') return next(e)
    const { Svg } = $.ui.resolve(e)
    return <Svg source={scene()} alt="An ember black hole, its disk slowly orbiting" isInteractive />
  })
}
