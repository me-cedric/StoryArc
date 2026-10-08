#!/usr/bin/env node
/**
 * Measures the paper grain off a pair of frames that differ in one thing, Natural on and off.
 *
 * `reader-theming-and-page-transitions` 0.5 asks whether the procedural grain "reads as paper".
 * A texture at this strength is invisible in one frame and obvious in a pair, so the answer is
 * read off the difference. `ios-paper-grain-2026-09-05/README.md` did that by hand on iOS and
 * wrote down five numbers; this is that measurement as a command, so Android, the dark pair and
 * a refusal are measured the same way.
 *
 * Over the page region, which is the middle half of the frame so both chrome bands are out:
 *
 * - the share of pixels the texture changed, and how strongly (0, 1, 2, 3 to 5, 6 or more
 *   levels out of 255 in the largest channel);
 * - the mean signed delta per channel, on minus off, over the region and over the changed pixels
 *   alone (the iOS write-up quoted the second). A warm grain darkens red less than blue, and a
 *   symmetric grey one shows three equal means, which reads as sensor noise;
 * - the length of each run of changed pixels along a scanline, median and 95th percentile,
 *   which is how big the speckle is.
 *
 * A refusal frame (Reduce Transparency, high contrast) measured against its Natural-off twin
 * must change nothing: 0% changed is what "the grain vanished" means in numbers.
 *
 * Usage:
 *   node scripts/grain-delta.mjs <natural-on.png> <natural-off.png>
 *   node scripts/grain-delta.mjs --self-test
 */
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

import { decode } from './png.mjs'

/** The buckets of |delta| the iOS write-up used, as [label, lowest, highest]. */
const BUCKETS = [['0', 0, 0], ['1', 1, 1], ['2', 2, 2], ['3-5', 3, 5], ['6+', 6, 255]]

/**
 * @param {{width:number,height:number,channels:number,pixels:Buffer}} on
 * @param {{width:number,height:number,channels:number,pixels:Buffer}} off
 */
export function grainDelta(on, off) {
  if (on.width !== off.width || on.height !== off.height) {
    throw new Error(`The pair differs in size: ${on.width}x${on.height} against ${off.width}x${off.height}.`)
  }
  const { width, height } = on
  const top = Math.floor(height / 4)
  const bottom = Math.floor((height * 3) / 4)
  const histogram = BUCKETS.map(() => 0)
  const signed = [0, 0, 0]
  const runs = []
  let total = 0
  let changed = 0

  for (let y = top; y < bottom; y += 1) {
    let run = 0
    for (let x = 0; x < width; x += 1) {
      let largest = 0
      for (let c = 0; c < 3; c += 1) {
        const a = on.pixels[(y * width + x) * on.channels + c]
        const b = off.pixels[(y * width + x) * off.channels + c]
        signed[c] += a - b
        largest = Math.max(largest, Math.abs(a - b))
      }
      total += 1
      histogram[BUCKETS.findIndex(([, low, high]) => largest >= low && largest <= high)] += 1
      if (largest > 0) {
        changed += 1
        run += 1
      } else if (run > 0) {
        runs.push(run)
        run = 0
      }
    }
    if (run > 0) runs.push(run)
  }

  runs.sort((a, b) => a - b)
  return {
    pixels: total,
    changedShare: changed / total,
    histogram: Object.fromEntries(BUCKETS.map(([label], i) => [label, histogram[i] / total])),
    meanSigned: signed.map((sum) => sum / total),
    meanSignedChanged: signed.map((sum) => (changed ? sum / changed : 0)),
    runMedian: runs.length ? runs[Math.floor(runs.length / 2)] : 0,
    runP95: runs.length ? runs[Math.floor(runs.length * 0.95)] : 0,
  }
}

const percent = (share) => `${(share * 100).toFixed(1)}%`

export function describe(result) {
  const [r, g, b] = result.meanSigned.map((v) => v.toFixed(2))
  const [rc, gc, bc] = result.meanSignedChanged.map((v) => v.toFixed(2))
  return [
    `changed ${percent(result.changedShare)} of ${result.pixels} pixels`,
    `by level: ${Object.entries(result.histogram).map(([k, v]) => `${k} ${percent(v)}`).join(', ')}`,
    `mean signed delta over the region R ${r}, G ${g}, B ${b}; over the changed pixels R ${rc}, G ${gc}, B ${bc}`,
    `speckle runs: median ${result.runMedian} px, 95th percentile ${result.runP95} px`,
  ].join('\n')
}

function selfTest() {
  const make = (value) => {
    const pixels = Buffer.alloc(8 * 8 * 3, value)
    return { width: 8, height: 8, channels: 3, pixels }
  }
  const off = make(200)
  const same = grainDelta(make(200), off)
  if (same.changedShare !== 0) throw new Error('Identical frames must change nothing.')
  const on = make(200)
  // Rows 2 to 5 are the page region. Darken a run of three pixels by two levels in red only.
  for (let x = 1; x < 4; x += 1) on.pixels[(3 * 8 + x) * 3] = 198
  const hit = grainDelta(on, off)
  if (hit.pixels !== 32 || hit.changedShare !== 3 / 32) throw new Error(`Expected 3 of 32 changed, got ${hit.changedShare}.`)
  if (hit.histogram['2'] !== 3 / 32) throw new Error('A two-level change belongs in the 2 bucket.')
  if (hit.runMedian !== 3 || hit.runP95 !== 3) throw new Error('The run is three pixels long.')
  if (Math.abs(hit.meanSigned[0] - -6 / 32) > 1e-9 || hit.meanSigned[2] !== 0) throw new Error('Only red moved.')
  if (Math.abs(hit.meanSignedChanged[0] - -2) > 1e-9) throw new Error('Over the changed pixels red moved by two.')
  console.log('grain-delta self-test: 5 checks passed')
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2)
  if (args[0] === '--self-test') {
    selfTest()
  } else if (args.length === 2) {
    console.log(describe(grainDelta(decode(readFileSync(args[0])), decode(readFileSync(args[1])))))
  } else {
    console.error('Usage: node scripts/grain-delta.mjs <natural-on.png> <natural-off.png> | --self-test')
    process.exit(2)
  }
}
