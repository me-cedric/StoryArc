#!/usr/bin/env node
/**
 * Compares a fresh sweep of screenshots against the reference sweep, frame by frame.
 *
 * `native-experience`'s "Screen change" scenario asks for a screenshot captured at the
 * project's device matrix **and compared against the reference**. Capture existed on both
 * platforms and nothing read a second image, so nothing was ever compared: a sweep was taken,
 * a person looked at some of it, and the rest was filed. This is the second image.
 *
 * Usage:
 *   node scripts/capture-compare.mjs --fresh <dir> --reference <dir>
 *   node scripts/capture-compare.mjs --fresh <dir>            reference defaults to REFERENCE
 *   node scripts/capture-compare.mjs --fresh <dir> --threshold 0.05 --ignore-top 8
 *   node scripts/capture-compare.mjs --self-test              no device, no directories
 *
 * **The threshold is the whole design of this tool, and both halves of it are measured.**
 * `scripts/device-matrix.mjs` carries the two numbers and the measurement each came from: a
 * band from the top of every frame that is ignored because the clock is in it, and the share
 * of the rest that may differ before a frame is reported. Two photographs of one screen taken
 * on different days are pixel-identical once the clock is out, and the smallest real change
 * in this project's own corpus is three times the threshold, so the gap is real rather than
 * hoped for. Read those two doc comments before changing either number.
 *
 * **It exits non-zero when it compared nothing.** An empty reference directory is the normal
 * state of a fresh checkout, and a tool that answered "0 differences" to it would be a green
 * light for a comparison that never happened — which is the failure the scenario exists to
 * prevent.
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { basename, join } from 'node:path'
import { pathToFileURL } from 'node:url'

import { IGNORE_TOP_PERCENT, THRESHOLD_PERCENT } from './device-matrix.mjs'
import { decode, encodeFiltered } from './png.mjs'

/** Where a baseline lives. Its README says what goes in it and the command that fills it. */
export const REFERENCE = 'docs/designs/screenshots/reference'

/**
 * Two frames, compared below the ignored band.
 *
 * Pure over its two buffers, so the self-test can put images through it that no device took.
 * A pixel differs when any of red, green or blue differs at all: a PNG is lossless and both
 * frames come off the same device, so there is no compression noise to forgive, and the
 * measurement behind `THRESHOLD_PERCENT` says an unchanged screen returns exactly zero.
 * Alpha is not compared — the two platforms disagree about whether a screenshot carries it.
 */
export function compare(freshPng, referencePng, options = {}) {
  const ignoreTopPercent = options.ignoreTopPercent ?? IGNORE_TOP_PERCENT
  const thresholdPercent = options.thresholdPercent ?? THRESHOLD_PERCENT
  const fresh = decode(freshPng)
  const reference = decode(referencePng)

  if (fresh.width !== reference.width || fresh.height !== reference.height) {
    return {
      verdict: 'reshaped',
      detail: `${fresh.width}x${fresh.height} against a reference of ${reference.width}x${reference.height}`,
      differing: 0,
      compared: 0,
      percent: 0,
      topRow: -1,
    }
  }

  const skip = Math.ceil(fresh.height * (ignoreTopPercent / 100))
  const compared = fresh.width * (fresh.height - skip)
  let differing = 0
  let topRow = -1
  let worst = 0
  for (let y = skip; y < fresh.height; y += 1) {
    for (let x = 0; x < fresh.width; x += 1) {
      const at = y * fresh.width + x
      const a = at * fresh.channels
      const b = at * reference.channels
      const delta = Math.max(
        Math.abs(fresh.pixels[a] - reference.pixels[b]),
        Math.abs(fresh.pixels[a + 1] - reference.pixels[b + 1]),
        Math.abs(fresh.pixels[a + 2] - reference.pixels[b + 2])
      )
      if (delta === 0) continue
      differing += 1
      if (topRow === -1) topRow = y
      if (delta > worst) worst = delta
    }
  }

  const percent = compared === 0 ? 0 : (differing / compared) * 100
  if (percent <= thresholdPercent) {
    return { verdict: 'same', detail: `${differing} pixel(s) differ, within the threshold`, differing, compared, percent, topRow }
  }
  return {
    verdict: 'differs',
    detail: `${differing} of ${compared} pixels (${percent.toFixed(4)}%), first at row ${topRow}, largest channel step ${worst}`,
    differing,
    compared,
    percent,
    topRow,
  }
}

/**
 * The one sentence a caller acts on, and whether the run passed.
 *
 * Every count is a number of frames, not of pixels. Pure over them, because the case that
 * matters most is the one with no frames at all, and a self-test should be able to reach it
 * without building a directory.
 */
export function verdict({ compared = 0, differing = 0, reshaped = 0, unreadable = 0, unreferenced = 0, uncaptured = 0 }) {
  if (compared === 0) {
    return {
      ok: false,
      sentence:
        'Nothing was compared. The reference directory holds no frame under any of these names, '
        + 'so this run proves nothing. Take a baseline first — the reference README says how.',
    }
  }
  const failing = differing + reshaped + unreadable
  const trailing = [
    unreferenced > 0 ? `${unreferenced} had no reference` : null,
    uncaptured > 0 ? `${uncaptured} reference frame(s) were not captured this run` : null,
  ].filter(Boolean)
  const tail = trailing.length > 0 ? `. ${trailing.join(', ')}` : ''
  if (failing === 0) return { ok: true, sentence: `${compared} frame(s) match the reference${tail}.` }
  // "did not match" rather than "differ", because a frame counted here may have been the
  // wrong size or unreadable rather than simply changed. The line above it says which.
  return { ok: false, sentence: `${failing} of ${compared} frame(s) did not match the reference${tail}.` }
}

const pngsIn = (directory) =>
  existsSync(directory) ? readdirSync(directory).filter((name) => name.endsWith('.png')).sort() : []

function sweep(freshDir, referenceDir, options) {
  const fresh = pngsIn(freshDir)
  const reference = new Set(pngsIn(referenceDir))
  if (fresh.length === 0) {
    console.error(`No PNG in ${freshDir}. Capture a sweep first.`)
    return 2
  }

  const counts = { compared: 0, differing: 0, reshaped: 0, unreadable: 0, unreferenced: 0, uncaptured: 0 }
  for (const name of fresh) {
    if (!reference.has(name)) {
      counts.unreferenced += 1
      console.log(`  ${name.padEnd(44)} no reference`)
      continue
    }
    let result
    try {
      result = compare(readFileSync(join(freshDir, name)), readFileSync(join(referenceDir, name)), options)
    } catch (error) {
      // A frame this cannot read is a frame it did not compare, and it fails for that reason
      // rather than being quietly dropped. `png.mjs` refuses by name, so the message says why.
      counts.compared += 1
      counts.unreadable += 1
      console.log(`  ${name.padEnd(44)} UNREADABLE  ${error.message}`)
      continue
    }
    counts.compared += 1
    if (result.verdict === 'same') console.log(`  ${name.padEnd(44)} ok          ${result.detail}`)
    else {
      counts[result.verdict === 'reshaped' ? 'reshaped' : 'differing'] += 1
      console.log(`  ${name.padEnd(44)} ${result.verdict.toUpperCase().padEnd(11)} ${result.detail}`)
    }
  }
  for (const name of reference) {
    if (!fresh.includes(name)) counts.uncaptured += 1
  }

  const answer = verdict(counts)
  console.log(answer.sentence)
  return answer.ok ? 0 : 1
}

/**
 * Proves the comparison catches a real difference and forgives an unchanged frame.
 *
 * Every image is built here, in memory, so no device and no directory is needed. Six frames
 * go through the comparison, and they are arranged as the two sides of each number the tool
 * turns on: a hundred pixels inside the ignored band is forgiven and the same hundred one row
 * below it is not, and five stray pixels are forgiven where six are not.
 *
 * The counts are hand-worked from the stated numbers rather than recomputed here. A 200x300
 * frame with the top 6% ignored compares 200 x (300 - 18) = 56,400 pixels, and 0.01% of that
 * is 5.64 pixels — so five pixels pass and six fail. Change either number in
 * `device-matrix.mjs` and these cases stop agreeing with it, which is the point of them.
 */
function selfTest() {
  const failures = []
  const width = 200
  const height = 300
  const options = { ignoreTopPercent: 6, thresholdPercent: 0.01 }

  /** A flat frame, with a run of pixels on one row painted a different colour. */
  const frame = (spots = []) => {
    const stride = width * 3
    const raw = Buffer.alloc((stride + 1) * height)
    for (let y = 0; y < height; y += 1) {
      const row = y * (stride + 1)
      raw[row] = 0
      for (let x = 0; x < width; x += 1) {
        raw[row + 1 + x * 3] = 240
        raw[row + 2 + x * 3] = 238
        raw[row + 3 + x * 3] = 234
      }
    }
    for (const [row, from, count] of spots) {
      for (let x = from; x < from + count; x += 1) {
        const at = row * (stride + 1) + 1 + x * 3
        raw[at] = 12
        raw[at + 1] = 12
        raw[at + 2] = 12
      }
    }
    return encodeFiltered(width, height, raw)
  }

  const reference = frame()
  const cases = [
    ['an unchanged frame', frame(), 'same'],
    ['a clock inside the ignored band', frame([[9, 30, 100]]), 'same'],
    ['the same change one row below the band', frame([[18, 30, 100]]), 'differs'],
    ['five stray pixels below the band', frame([[150, 30, 5]]), 'same'],
    ['six stray pixels below the band', frame([[150, 30, 6]]), 'differs'],
    ['a real change, a 40x40 block', frame(Array.from({ length: 40 }, (_, i) => [150 + i, 30, 40])), 'differs'],
  ]
  for (const [what, image, expected] of cases) {
    const result = compare(image, reference, options)
    if (result.verdict !== expected) {
      failures.push(`${what}: ${result.verdict}, expected ${expected} (${result.detail})`)
    }
    if (result.compared !== 56400) {
      failures.push(`${what}: compared ${result.compared} pixels, expected 56400`)
    }
  }

  const reshaped = compare(frame(), encodeFiltered(width, 299, Buffer.alloc((width * 3 + 1) * 299)), options)
  if (reshaped.verdict !== 'reshaped') failures.push(`a frame of another size: ${reshaped.verdict}, expected reshaped`)

  const nothing = verdict({ compared: 0, unreferenced: 12 })
  if (nothing.ok) failures.push('an empty reference passed, and it must never pass')
  if (!/Nothing was compared/.test(nothing.sentence)) failures.push('an empty reference did not say it compared nothing')
  const matched = verdict({ compared: 12, differing: 0 })
  if (!matched.ok) failures.push('twelve matching frames failed')
  const oneOff = verdict({ compared: 12, differing: 1 })
  if (oneOff.ok) failures.push('one differing frame passed')
  const broken = verdict({ compared: 12, unreadable: 1 })
  if (broken.ok) failures.push('one unreadable frame passed')

  for (const failure of failures) console.error(`  ${failure}`)
  const checks = cases.length * 2 + 6
  console.log(
    failures.length === 0
      ? `capture-compare self-test: ${checks} checks passed`
      : `capture-compare self-test FAILED: ${failures.length} of ${checks}`
  )
  process.exitCode = failures.length === 0 ? 0 : 1
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const argv = process.argv.slice(2)
  const flag = (name, fallback = null) => {
    const at = argv.indexOf(`--${name}`)
    return at === -1 ? fallback : argv[at + 1]
  }
  if (argv.includes('--self-test')) {
    selfTest()
  } else {
    const freshDir = flag('fresh')
    if (!freshDir) {
      console.error('Usage: node scripts/capture-compare.mjs --fresh <dir> [--reference <dir>]')
      console.error('       node scripts/capture-compare.mjs --self-test')
      process.exitCode = 2
    } else {
      const referenceDir = flag('reference', REFERENCE)
      const options = {
        ignoreTopPercent: Number(flag('ignore-top', IGNORE_TOP_PERCENT)),
        thresholdPercent: Number(flag('threshold', THRESHOLD_PERCENT)),
      }
      // A number this cannot read would make every frame compare zero pixels and pass, which
      // is the silent green this whole tool exists to refuse.
      const sane = (value) => Number.isFinite(value) && value >= 0 && value <= 100
      if (!sane(options.ignoreTopPercent) || !sane(options.thresholdPercent)) {
        console.error('--ignore-top and --threshold each take a number from 0 to 100.')
        process.exit(2)
      }
      console.log(
        `${basename(freshDir)} against ${referenceDir}, ignoring the top ${options.ignoreTopPercent}% `
        + `and failing above ${options.thresholdPercent}%`
      )
      process.exitCode = sweep(freshDir, referenceDir, options)
    }
  }
}
