#!/usr/bin/env node
// Shrinks PNG frames to 1200 pixels on the long side, in place, with `sips` (macOS, free).
//
//   pnpm frames:shrink <file or folder>...
//
// A frame already within 1200 pixels is left alone, so the command is safe to run again.
// A folder is searched for `.png` files, at every depth.

import { execFileSync } from 'node:child_process'
import { readdirSync, statSync } from 'node:fs'
import { extname, join, resolve } from 'node:path'

const LONG_SIDE = 1200

/** Every PNG under the arguments, in the order given. */
function pngsUnder(path) {
  if (statSync(path).isFile()) return extname(path).toLowerCase() === '.png' ? [path] : []
  return readdirSync(path, { withFileTypes: true }).flatMap((entry) => pngsUnder(join(path, entry.name)))
}

function size(file) {
  const out = execFileSync('sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', file], { encoding: 'utf8' })
  const read = (key) => Number(out.match(new RegExp(`${key}:\\s*(\\d+)`))?.[1])
  return { width: read('pixelWidth'), height: read('pixelHeight') }
}

const targets = process.argv.slice(2)
if (targets.length === 0) {
  console.error('Name a PNG file or a folder: pnpm frames:shrink <file or folder>...')
  process.exit(2)
}

let shrunk = 0
let kept = 0
for (const file of targets.flatMap((target) => pngsUnder(resolve(target)))) {
  const { width, height } = size(file)
  if (Math.max(width, height) <= LONG_SIDE) {
    kept += 1
    continue
  }
  execFileSync('sips', ['-Z', String(LONG_SIDE), file], { stdio: 'ignore' })
  shrunk += 1
}
console.log(`frames:shrink: ${shrunk} shrunk to ${LONG_SIDE} px, ${kept} already small enough.`)
