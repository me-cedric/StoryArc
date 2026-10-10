#!/usr/bin/env node
// Runs the screen-catalogue accessibility audit (`CatalogueAuditTests`) on a local simulator,
// with the same steps as the "Catalogue audit" step of `.github/workflows/ios.yml`.
//
//   node scripts/test-ios-audit.mjs          the newest iPhone 17 Pro
//   node scripts/test-ios-audit.mjs <udid>   another simulator
//
// The steps: build for testing, install and seed (`install-and-seed-simulator.mjs`), write the
// corpus (`corpus.mjs`), then run the class (`test-ios-ci.mjs --only CatalogueAuditTests`).
// A UDID, not a name, goes to every step: a Mac with several iOS runtimes has several
// "iPhone 17 Pro" devices, and a seed on one and a test on another proves nothing.
//
// A simulator this run booted is shut down again. One that was already up is left alone.

import { execFileSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const MODEL = 'iPhone 17 Pro'

const devices = () => JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'available', '-j'], { encoding: 'utf8' })).devices

/** The UDID of `MODEL` on the newest iOS runtime. */
const newest = () => {
  const runtimes = Object.keys(devices())
    .filter((runtime) => runtime.includes('.iOS-'))
    .sort((a, b) => a.localeCompare(b, 'en', { numeric: true }))
    .reverse()
  for (const runtime of runtimes) {
    const found = devices()[runtime].find((device) => device.name === MODEL)
    if (found) return found.udid
  }
  console.error(`No available ${MODEL} simulator. Pass a UDID.`)
  process.exit(1)
}

const udid = process.argv[2] ?? newest()
const state = () => Object.values(devices()).flat().find((device) => device.udid === udid)?.state
const wasBooted = state() === 'Booted'
const run = (file, args) => execFileSync(file, args, { cwd: ROOT, stdio: 'inherit' })

let status = 0
try {
  run('pnpm', ['build:ios:ui'])
  run('node', [join(ROOT, 'scripts/install-and-seed-simulator.mjs'), udid])
  run('node', [join(ROOT, 'scripts/corpus.mjs'), '--simulator', udid])
  run('node', [join(ROOT, 'scripts/test-ios-ci.mjs'), '--only', 'CatalogueAuditTests', '--device', udid])
} catch (error) {
  // The child has already printed why.
  status = error.status ?? 1
} finally {
  if (!wasBooted && state() === 'Booted') execFileSync('xcrun', ['simctl', 'shutdown', udid])
}
process.exit(status)
