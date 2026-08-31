#!/usr/bin/env node
/**
 * Photographs a screen on a connected Android device, in a named condition.
 *
 * `AGENTS.md` section 6 requires visual proof for every change a reader can see, and every
 * one of those proofs was being taken by hand: force-stop, start, tap, tap, tap, screencap,
 * and remember to put the font scale back. Twelve captures for one day's fixes, each a
 * dozen `adb` invocations, is how a required proof quietly becomes an optional one.
 *
 * Two conditions matter and both are set here rather than left to whoever is watching:
 * the text size, because `design.md` section 3 rule 3 says every screen survives the
 * largest accessibility size, and the appearance, because half this project's defects only
 * appear in one of them.
 *
 * **It always puts the device back.** A left-behind `font_scale 2.0` makes the next
 * person's screenshots wrong in a way that looks like a regression, which has cost an hour
 * at least once. The restore runs even when the capture fails.
 *
 * Usage:
 *   node scripts/capture-android.mjs Downloads --out shot.png
 *   node scripts/capture-android.mjs Downloads --out shot.png --dark --font-scale 2.0
 *   node scripts/capture-android.mjs --list
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

import { adbRunner, hasDevice, resolveAdb } from './adb.mjs'
import { ROUTES, navigator, sleep } from './android-routes.mjs'

const argv = process.argv.slice(2)
const flag = (name, fallback = null) => {
    const at = argv.indexOf(`--${name}`)
    return at === -1 ? fallback : argv[at + 1]
}

if (argv.includes('--list')) {
    for (const [name] of ROUTES) console.log(name)
    process.exit(0)
}

/** Flags that swallow the word after them, so it is not mistaken for the route name. */
const VALUED = new Set(["--out", "--font-scale"])
const positional = argv.filter((a, at) => !a.startsWith("--") && !VALUED.has(argv[at - 1]))
const wanted = positional[0]
const out = flag('out')
const scale = flag('font-scale', '1.0')
const dark = argv.includes('--dark')

if (!wanted || !out) {
    console.error('Usage: node scripts/capture-android.mjs <route> --out <path> [--dark] [--font-scale 2.0]')
    console.error('       node scripts/capture-android.mjs --list')
    process.exit(2)
}

const route = ROUTES.find(([name]) => name.toLowerCase() === wanted.toLowerCase())
    ?? ROUTES.find(([name]) => name.toLowerCase().includes(wanted.toLowerCase()))
if (!route) {
    console.error(`No route matches "${wanted}". Run with --list to see them.`)
    process.exit(2)
}

const adb = resolveAdb()
const sh = adbRunner(adb, { onDeviceError: 'empty' })
if (!hasDevice(sh)) {
    console.error('No device or emulator is attached. Start one, then run this again.')
    process.exit(2)
}

/** What the device was set to, so it can be put back. */
const wasScale = (/(\d+(?:\.\d+)?)/.exec(sh('shell', 'settings', 'get', 'system', 'font_scale')) ?? [])[1] ?? '1.0'
const wasNight = /yes|true/i.test(sh('shell', 'cmd', 'uimode', 'night'))

const restore = () => {
    sh('shell', 'settings', 'put', 'system', 'font_scale', wasScale)
    sh('shell', 'cmd', 'uimode', 'night', wasNight ? 'yes' : 'no')
}
process.on('exit', restore)
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => process.exit(130))

const [name, steps] = route
sh('shell', 'settings', 'put', 'system', 'font_scale', scale)
sh('shell', 'cmd', 'uimode', 'night', dark ? 'yes' : 'no')
// A font scale change restarts activities. Let that settle before the walk starts, or the
// first tap lands on a screen that is about to be thrown away.
sleep(2500)

const { walk, dump } = navigator(sh)
const missed = walk(steps)
if (missed !== null) {
    console.error(`Could not reach "${missed}" on the way to ${name}.`)
    console.error('The route map may be stale, or this device has no publication in the state it needs.')
    process.exit(1)
}

/**
 * Waits until the app has actually drawn something, rather than trusting a delay.
 *
 * The launch inside `walk` waits a fixed 3.5 seconds, which is plenty for a warm start and
 * **not** plenty for the first launch after an install. The first Home capture taken with
 * this script came out as a picture of the splash screen — the orange book on a cream field
 * — filed under `android-home-default-light.png`, which is precisely the failure this
 * script's own header claims to prevent and the one `AuditWalk.swift` warns about at length.
 *
 * A splash screen is an image and nothing else: no text, no content description. So the
 * signal is a node carrying either, and it is a signal rather than a guess.
 */
const drawn = () => {
    for (let attempt = 0; attempt < 12; attempt += 1) {
        const xml = dump()
        if (/(text|content-desc)="[^"]+"/.test(xml)) return true
        sleep(1000)
    }
    return false
}

if (!drawn()) {
    console.error(`${name} drew nothing readable within twelve seconds — the screenshot would be a splash screen.`)
    process.exit(1)
}

// Settled: the last tap animates, and a screenshot mid-transition is a screenshot of
// neither screen.
sleep(1200)
// `exec-out` rather than `shell`, because a screenshot is bytes and the shell mangles them.
const png = execFileSync(adb, ['exec-out', 'screencap', '-p'], { maxBuffer: 1 << 28 })
mkdirSync(dirname(out), { recursive: true })
writeFileSync(out, png)

const condition = [`font_scale ${scale}`, dark ? 'dark' : 'light'].join(', ')
console.log(`${name} (${condition}) -> ${out}  ${(png.length / 1024).toFixed(0)} KB`)
