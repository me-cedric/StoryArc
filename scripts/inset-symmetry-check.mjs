#!/usr/bin/env node
/**
 * Fails when app code mirrors one edge's inset onto the other.
 *
 * `native-experience`, *Foldable devices*, *Two apps side by side on the open display*: the
 * system puts its controls on one side only, so each inset is read on its own. On iPhone Duo
 * the vertical bars sit on the left in landscape and in Split View. A width computed as
 * `safeAreaInsets.left * 2` is then wrong by one bar (`foldables-and-iphone-duo`, task 1.5).
 *
 * Usage:
 *   node scripts/inset-symmetry-check.mjs              check apps/ios and apps/android
 *   node scripts/inset-symmetry-check.mjs --self-test  the pattern, without touching the tree
 */
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const DIRS = ['apps/ios', 'apps/android']
const SKIP = new Set(['build', '.build', '.gradle', 'DerivedData', 'node_modules', '.git'])

/** One edge of an inset, doubled: `insets.left * 2`, `2 * safeAreaInsets.leading`. */
const MIRRORED = /(?:nsets?|safeArea)[\w.()]*\.(?:left|right|leading|trailing|start|end)\w*\s*\*\s*2\b|\b2\s*\*\s*[\w.()]*(?:nsets?|safeArea)[\w.()]*\.(?:left|right|leading|trailing|start|end)\b/

export const mirrored = (line) => MIRRORED.test(line)

function* sources(dir) {
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue
    const path = join(dir, name)
    if (statSync(path).isDirectory()) yield* sources(path)
    else if (/\.(swift|kt)$/.test(name)) yield path
  }
}

function selfTest() {
  const assert = (condition, what) => {
    if (!condition) throw new Error(`self-test: ${what}`)
  }
  assert(mirrored('let width = size.width - proxy.safeAreaInsets.leading * 2'), 'a doubled leading inset is found')
  assert(mirrored('val w = insets.left * 2'), 'a doubled left inset is found')
  assert(mirrored('let w = 2 * window.safeAreaInsets.left'), 'a doubled inset with the 2 first is found')
  assert(mirrored('val pad = WindowInsets.systemBars.getStart(density).start * 2'), 'a call chain is found')
  assert(!mirrored('let w = insets.leading + insets.trailing'), 'each edge read on its own passes')
  assert(!mirrored('let w = size.width * 2'), 'a doubled width that is no inset passes')
  assert(!mirrored('val gap = insets.left * 20'), 'a factor that is not 2 passes')
  console.log('inset-symmetry-check self-test: all pass')
}

function check() {
  const found = []
  for (const dir of DIRS) {
    for (const path of sources(join(ROOT, dir))) {
      readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
        if (mirrored(line)) found.push(`${relative(ROOT, path)}:${index + 1}: ${line.trim()}`)
      })
    }
  }
  if (found.length) {
    console.error(`An inset is mirrored from one edge to the other. Read each edge on its own:\n${found.join('\n')}`)
    process.exitCode = 1
  }
}

if (process.argv.includes('--self-test')) selfTest()
else check()
