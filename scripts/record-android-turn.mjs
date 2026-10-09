#!/usr/bin/env node
/**
 * Records a page turn on a connected Android device and cuts the recording into frames.
 *
 * A curl is a page at rest, so a screenshot cannot tell it from a slide, and `adb shell input
 * tap` returns before the tap lands. `docs/designs/screenshots/a-tap-that-curls-2026-10-06/`
 * took its frames from a recording, and every step of that was typed by hand. This is the part
 * that is the same every time: start `screenrecord`, drive the finger from the device's own
 * shell so the gap between two touches is the shell's and not the host's, stop, pull, and cut.
 *
 * `screenrecord` refuses the full size of a large panel, so the recording is 720 wide.
 *
 * Usage:
 *   node scripts/record-android-turn.mjs <mode> --out <directory> [--fps 30] [--seconds 6] [--to 0.5]
 *
 * Modes, each one gesture across the page at mid height (the reader must be open, in Curl):
 *   tap        one tap on the trailing third, so the roll runs with no finger on the screen
 *   back       one tap on the leading third, a backward turn
 *   drag       a held forward drag from 92 percent of the width to `--to` (default 50), lifted after a second
 *   interrupt  a forward drag lifted at 40 percent, then a second touch inside the settle that
 *              carries the page back to 85 percent. The page must not snap.
 */
import { execFileSync, spawn } from 'node:child_process'
import { mkdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'

import { adbRunner, resolveAdb } from './adb.mjs'

const argv = process.argv.slice(2)
const mode = argv[0]
const flag = (name, fallback = null) => {
    const at = argv.indexOf(`--${name}`)
    return at === -1 ? fallback : argv[at + 1]
}
const out = flag('out')
const fps = Number(flag('fps', '30'))
const seconds = Number(flag('seconds', '6'))
const to = Number(flag('to', '0.5'))
if (!['tap', 'back', 'drag', 'interrupt'].includes(mode) || !out) {
    console.error('Usage: node scripts/record-android-turn.mjs tap|back|drag|interrupt --out <directory> [--fps 30] [--seconds 6] [--to 0.5]')
    process.exit(2)
}

const run = adbRunner()
const [width, height] = (/(\d+)x(\d+)/.exec(run('shell', 'wm', 'size').split('\n').at(-2) ?? '') ?? [null, 1080, 2400]).slice(1).map(Number)
const x = (fraction) => Math.round(width * fraction)
const y = Math.round(height * 0.5)

/**
 * One finger, as `cmd input motionevent`, which asks the system server directly and takes about
 * 20 ms an event. `input motionevent` starts a Java process per event, about 130 ms each, and a
 * touch lifted and put down again 130 ms later has missed the spring it was meant to catch.
 * `sendevent` would be faster still and needs root, which a Play Store image does not give.
 */
const at = (fraction) => `${x(fraction)} ${y}`
const press = (fraction) => `cmd input motionevent DOWN ${at(fraction)}`
const slide = (fraction) => `cmd input motionevent MOVE ${at(fraction)}`
const lift = (fraction) => `cmd input motionevent UP ${at(fraction)}`
const wait = (seconds) => `sleep ${seconds}`

const slides = (path, pause = 0.06) => path.map((to) => `${slide(to)}; ${wait(pause)}`).join('; ')

/** `count` evenly spaced fractions from [from] to [to], the first step excluded. */
const path = (from, last, count) => Array.from({ length: count }, (_, i) => from + ((last - from) * (i + 1)) / count)

const gestures = {
    tap: `input tap ${x(0.92)} ${y}`,
    back: `input tap ${x(0.08)} ${y}`,
    drag: [press(0.92), slides(path(0.92, to, 7), 0.12), wait(1), lift(to)].join('; '),
    interrupt: [
        press(0.92),
        slides([0.7, 0.55, 0.4, 0.3], 0.1),
        lift(0.3),
        wait(0.05),
        press(0.3),
        slides([0.45, 0.6, 0.75, 0.9], 0.1),
        wait(1),
        lift(0.9),
    ].join('; '),
}

mkdirSync(out, { recursive: true })
const remote = '/sdcard/storyarc-turn.mp4'
const recording = spawn(resolveAdb(), ['shell', 'screenrecord', '--time-limit', String(seconds), '--bit-rate', '16000000', '--size', `720x${Math.round((720 * height) / width / 16) * 16}`, remote], { stdio: ['ignore', 'ignore', 'inherit'] })
const done = new Promise((resolve) => recording.on('exit', resolve))
await new Promise((resolve) => setTimeout(resolve, 1500))
run('shell', gestures[mode])

await done
const local = join(out, `${mode}.mp4`)
run('pull', remote, local)
run('shell', 'rm', remote)
for (const stale of [join(out, 'frames')]) rmSync(stale, { recursive: true, force: true })
mkdirSync(join(out, 'frames'), { recursive: true })
execFileSync('ffmpeg', ['-v', 'error', '-i', local, '-vf', `fps=${fps}`, join(out, 'frames', 'f%04d.png')])
console.log(`${local} and its frames in ${join(out, 'frames')}`)
