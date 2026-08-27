#!/usr/bin/env node
/**
 * Reads the Android accessibility tree off a connected device and reports what a screen
 * reader cannot recover from.
 *
 * Exists because three real defects reached a commit and none of them was visible in a
 * screenshot: a comic page announced as "page10.png", a colour swatch announced as
 * "Colour #E8EFE6", and a settings row whose tap target was 34dp because its label
 * happened to fit on one line. A reviewer cannot see any of those. The tree can.
 *
 * Three checks:
 *
 *   UNNAMED    an actionable node with no name anywhere in its own subtree. A named
 *              *descendant* is fine — the platform merges a non-focusable child into its
 *              focusable parent, so the parent speaks the child's name.
 *   RAW-VALUE  a name that is a file name, a path, a URL or a bare float. None of those
 *              is something the reader chose to hear.
 *   SMALL      an actionable node below the 48dp floor that Material and WCAG agree on.
 *
 * Two sources of false positive are excluded, both learnt by shipping them:
 *
 *   - Density comes from the device, never a constant. At 420dpi a 126px target is
 *     exactly 48dp, and a guessed 2.75 turns that into a defect that is not there.
 *   - A node clipped by the screen or by a scrolling ancestor measures short, and can
 *     lose the label that scrolled away with it. Only a node lying fully inside its clip
 *     rectangle is judged.
 *
 * Usage:
 *   node scripts/a11y-scan.mjs              scan whatever is on screen now
 *   node scripts/a11y-scan.mjs dump.xml     scan a saved uiautomator dump
 *   node scripts/a11y-scan.mjs --self-test  check the checks still fire
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const MIN_DP = 48
const RAW =
  /(\.(png|jpe?g|webp|gif|xml|json|cbz|cbr|epub)$)|^(\/|file:|https?:|smb:)|^-?\d+\.\d+$/i
const ACTIONABLE = ['clickable', 'checkable', 'long-clickable']

/**
 * The SDK's adb if it is there, otherwise whatever is on PATH.
 *
 * Order matters. Preferring the bare name first looks harmless and is not: the child
 * process does not always inherit a shell's PATH, so `adb` resolves to nothing, every
 * call throws ENOENT, and a swallowed ENOENT reads as "every screen is fine".
 */
const SDK_ADB = join(homedir(), 'Library/Android/sdk/platform-tools/adb')
const adb = existsSync(SDK_ADB) ? SDK_ADB : 'adb'

const run = (...args) => {
  try {
    return execFileSync(adb, args, { encoding: 'utf8', maxBuffer: 1 << 26 })
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new Error(`adb not found at ${adb}. Install the platform tools or add adb to PATH.`)
    }
    throw error
  }
}

/** The device's own density. A guessed one invents defects, so this is never a constant. */
const density = () => Number(/(\d+)/.exec(run('shell', 'wm', 'density'))?.[1] ?? 420)

const liveDump = () => {
  run('shell', 'uiautomator', 'dump', '/sdcard/a11y.xml')
  const xml = run('shell', 'cat', '/sdcard/a11y.xml')
  return xml.slice(xml.indexOf('<?xml'))
}

/**
 * Parses the flat `<node .../>` stream into a tree.
 *
 * uiautomator emits self-closing and paired tags in one document, so nesting is tracked
 * from the tag shape rather than from an XML library — which keeps this dependency-free.
 */
const parse = (xml) => {
  const root = { attrs: {}, children: [] }
  const stack = [root]
  for (const [tag] of xml.matchAll(/<node\b[^>]*?\/?>|<\/node>/g)) {
    if (tag === '</node>') {
      stack.pop()
      continue
    }
    const attrs = Object.fromEntries(
      [...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([, key, value]) => [key, value]),
    )
    const node = { attrs, children: [] }
    stack.at(-1).children.push(node)
    if (!tag.endsWith('/>')) stack.push(node)
  }
  return root
}

const boxOf = (node) => {
  const m = /\[(-?\d+),(-?\d+)]\[(-?\d+),(-?\d+)]/.exec(node.attrs.bounds ?? '')
  return m ? m.slice(1).map(Number) : null
}

const nameOf = (node) =>
  (node.attrs['content-desc'] ?? '').trim() || (node.attrs.text ?? '').trim()

/** Any name at or below this node, which is what the reader actually hears. */
const subtreeName = (node) =>
  nameOf(node) || node.children.map(subtreeName).find(Boolean) || ''

const scan = (xml, dpi) => {
  const scale = dpi / 160
  const tree = parse(xml)
  const screen = tree.children[0] ? boxOf(tree.children[0]) : null
  const problems = []
  let count = 0

  const walk = (node, clip) => {
    count += 1
    const box = boxOf(node)
    const cls = (node.attrs.class ?? '?').split('.').pop()
    const actionable = ACTIONABLE.some((key) => node.attrs[key] === 'true')
    const own = nameOf(node)
    const merged = subtreeName(node)

    // Inside its clip rectangle, with a pixel of tolerance for rounding at the edges.
    const whole =
      box != null &&
      clip != null &&
      box[0] >= clip[0] - 1 &&
      box[1] >= clip[1] - 1 &&
      box[2] <= clip[2] + 1 &&
      box[3] <= clip[3] + 1

    if (actionable && !merged && whole) problems.push(`UNNAMED   ${cls} at ${node.attrs.bounds}`)
    if (own && RAW.test(own)) problems.push(`RAW-VALUE ${cls} "${own}"`)
    if (actionable && whole) {
      const w = (box[2] - box[0]) / scale
      const h = (box[3] - box[1]) / scale
      // A zero dimension is a node that is not laid out, not a small target.
      if (Math.min(w, h) > 0 && Math.min(w, h) < MIN_DP - 0.5) {
        problems.push(`SMALL     ${cls} ${w.toFixed(1)}x${h.toFixed(1)}dp "${merged.slice(0, 30)}"`)
      }
    }

    // A scrolling node clips whatever is inside it, which is what hides a label.
    const inner = node.attrs.scrollable === 'true' && box ? box : clip
    for (const child of node.children) walk(child, inner)
  }

  for (const top of tree.children) walk(top, screen)
  return { count, problems: [...new Set(problems)] }
}

/**
 * Checks that each check still fires and each exclusion still holds.
 *
 * A scanner that silently stops matching reports a clean screen, which is worse than no
 * scanner at all. The fixture holds one node per rule, including the two that must NOT be
 * reported: a node named by its child, and a node clipped by a scrolling ancestor.
 */
const selfTest = () => {
  const fixture = new URL('./fixtures/a11y-probe.xml', import.meta.url)
  const { problems } = scan(readFileSync(fixture, 'utf8'), 420)
  const expected = [
    'RAW-VALUE ImageView "page10.png"',
    'UNNAMED   Button at [100,900][205,1026]',
    'SMALL     Button 40.0x48.0dp ""',
    'RAW-VALUE SeekBar "0.45"',
  ]
  const missing = expected.filter((line) => !problems.includes(line))
  // The scroll-clipped node measures 38dp and is unnamed, and must be reported as
  // neither: it is cut off, not small, and its label scrolled away with it.
  const leaked = problems.filter((line) => line.includes('[0,1380]'))

  for (const line of missing) console.error(`  MISSING  ${line}`)
  for (const line of leaked) console.error(`  FALSE POSITIVE  ${line}`)
  const ok = missing.length === 0 && leaked.length === 0
  console.log(ok ? 'self-test passed' : 'self-test FAILED')
  process.exitCode = ok ? 0 : 1
}

const [file] = process.argv.slice(2)
if (file === '--self-test') {
  selfTest()
} else {
  const xml = file ? readFileSync(file, 'utf8') : liveDump()
  const dpi = file ? 420 : density()
  const { count, problems } = scan(xml, dpi)

  console.log(`${count} nodes, ${problems.length} problems  (density ${dpi}dpi)`)
  for (const problem of problems) console.log(`  ${problem}`)
  process.exitCode = problems.length > 0 ? 1 : 0
}
