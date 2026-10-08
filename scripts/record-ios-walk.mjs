#!/usr/bin/env node
/**
 * Records the simulator while one UI-test walk runs, and cuts the recording into frames.
 *
 * XCUITest has no primitive that holds a touch down across a screenshot, and its
 * `press(forDuration:thenDragTo:...)` returns after the finger lifts, so a still of a curl is a
 * still of a settled page. `ios-curl-2026-09-05/README.md` took its frames from a recording and
 * typed every step by hand, which is how a required proof becomes an optional one. This is that
 * recipe as one command.
 *
 * The recording starts before the walk and stops after it, so the frames hold the walk's
 * launch and its idle seconds as well. Cut with `--fps` high enough to keep a roll of a fifth
 * of a second in more than one frame, and pick the ones with the fold in them.
 *
 * Usage:
 *   node scripts/record-ios-walk.mjs --only CurlWalkTests/testCaptureCurlLastPageHeld \
 *       --out /tmp/rec [--device <udid>] [--appearance light|dark] [--fps 20, or 0 to keep only the video] [--snap <seconds>]
 *
 * It prints the video and the folder of frames. The screenshots the walk itself attaches go to
 * `<out>/shots`.
 */
import { execFileSync, spawn } from 'node:child_process'
import { mkdirSync, rmSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const argv = process.argv.slice(2)
const flag = (name, fallback = null) => {
    const at = argv.indexOf(`--${name}`)
    return at === -1 ? fallback : argv[at + 1]
}
const only = flag('only')
const out = flag('out')
const device = flag('device')
const appearance = flag('appearance')
const fps = flag('fps', '20')
const snap = Number(flag('snap', '0'))
if (!only || !out || !device) {
    console.error('Usage: node scripts/record-ios-walk.mjs --only <Class/test> --out <directory> --device <udid> [--appearance light|dark] [--fps 20, or 0 to keep only the video] [--snap <seconds>]')
    process.exit(2)
}

const here = dirname(fileURLToPath(import.meta.url))
const video = resolve(out, 'walk.mov')
const frames = resolve(out, 'frames')
mkdirSync(out, { recursive: true })
for (const path of [video, frames]) rmSync(path, { recursive: true, force: true })
mkdirSync(frames, { recursive: true })

const recorder = spawn('xcrun', ['simctl', 'io', device, 'recordVideo', '--codec', 'h264', '--force', video], { stdio: 'ignore' })
const stopped = new Promise((resolveStop) => recorder.on('exit', resolveStop))
await new Promise((resolveWait) => setTimeout(resolveWait, 2000))

// A video made of a screen that rarely changes keeps no wall clock, so `--snap` also takes a
// screenshot every N seconds, named by the second it was asked for, to tell when a frame was.
const snaps = join(out, 'snaps')
rmSync(snaps, { recursive: true, force: true })
mkdirSync(snaps, { recursive: true })
const began = Date.now()
const ticker = snap > 0
    ? setInterval(() => {
        const seconds = String(Math.round((Date.now() - began) / 1000)).padStart(4, '0')
        spawn('xcrun', ['simctl', 'io', device, 'screenshot', join(snaps, `t${seconds}.png`)], { stdio: 'ignore' })
    }, snap * 1000)
    : null

const capture = ['--out', join(out, 'shots'), '--only', only, '--device', device]
if (appearance) capture.push('--appearance', appearance)
const walk = await new Promise((resolveWalk) => {
    const child = spawn(process.execPath, [join(here, 'capture-ios.mjs'), ...capture], { stdio: 'inherit' })
    child.on('exit', (status) => resolveWalk({ status }))
})
if (ticker) clearInterval(ticker)

// SIGINT is what finishes the file: killing the recorder any harder leaves a movie with no index.
recorder.kill('SIGINT')
await stopped
if (Number(fps) > 0) execFileSync('ffmpeg', ['-v', 'error', '-i', video, '-vf', `fps=${fps}`, '-pix_fmt', 'rgb24', join(frames, 'f%04d.png')])
console.log(`${video}, and its frames in ${frames}`)
process.exit(walk.status ?? 1)
