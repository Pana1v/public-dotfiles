import type { Register, ThemeSetArgs } from 'claude-code'

import { EMBER } from './ember.js'
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

// ---------- the scene: the ember wallpaper, traced to vector ----------

function scene(): string {
  const css = [
    '.grain{animation:grain .6s steps(6) infinite}',
    '@keyframes grain{0%{transform:translate(0,0)}20%{transform:translate(-37px,23px)}40%{transform:translate(19px,-41px)}60%{transform:translate(-11px,-17px)}80%{transform:translate(43px,29px)}100%{transform:translate(0,0)}}',
  ].join('')

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1309 1008" width="1309" height="1008" preserveAspectRatio="xMaxYMid slice">
<style>${css}</style>
<defs>
<filter id="trace" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation=".7"/></filter>
<filter id="noise"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 1  0 0 0 0 .9  0 0 0 0 .9  0 0 0 .55 -.2"/></filter>
</defs>
${EMBER}
<g opacity=".2"><rect class="grain" x="-60" y="-60" width="1430" height="1130" filter="url(#noise)"/></g>
</svg>`
}

const LOOK: ThemeSetArgs = {
  colors: theme,
  overrideColorScheme: 'dark',
  backdrop: { scene: 'blackhole', glass: { blur: 10, tint: P.bg, opacity: 0.45 } },
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // Desktop app only: the terminal draws no theme.
    if (e.surface === 'terminal') {
      return next(e)
    }

    const unpainted = problems.find(line => line.startsWith("Desktop won't paint"))
    if (unpainted !== undefined) $.ui.toast(unpainted)

    await $.theme.set(LOOK)

    return next(e)
  })

  on('ui.render', { component: 'Backdrop' }, ($, e, next) => {
    if (e.surface !== 'desktop' && e.surface !== 'mobile') return next(e)
    if (e.props.scene !== 'blackhole') return next(e)
    const { Svg } = $.ui.resolve(e)
    return <Svg source={scene()} alt="An ember black hole" isInteractive />
  })
}
