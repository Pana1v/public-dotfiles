import { expect, test } from 'claude-code/testing'

const BACKDROP = {
  plugin: 'blackhole-theme',
  component: 'Backdrop',
  props: { scene: 'blackhole' },
} as const

test('desktop draws the traced wallpaper', async $ => {
  const ui = await $.ui.mount({ ...BACKDROP, surface: 'desktop' })

  const svg = await ui.find({ type: 'Svg' })
  expect(svg).toBeDefined()
  await ui.unmount()
})

test('the terminal sets no theme', async ($, on) => {
  let isSet = false
  on('theme.set', () => {
    isSet = true
    return { value: { isDrawn: false, reason: 'terminal' } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  expect(isSet).toBe(false)
})
