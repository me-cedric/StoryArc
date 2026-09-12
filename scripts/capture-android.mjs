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
 *   node scripts/capture-android.mjs Downloads --out <directory> --matrix
 *   node scripts/capture-android.mjs --list
 */
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

import { adbRunner, hasDevice, resolveAdb } from './adb.mjs'
import { ROUTES, navigator, sleep, splitLate } from './android-routes.mjs'
import { MATRIX, describe, slug } from './device-matrix.mjs'

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
    console.error('       node scripts/capture-android.mjs <route> --out <directory> --matrix')
    console.error('       node scripts/capture-android.mjs --list')
    process.exit(2)
}

const route = ROUTES.find(([name]) => name.toLowerCase() === wanted.toLowerCase())
    ?? ROUTES.find(([name]) => name.toLowerCase().includes(wanted.toLowerCase()))
if (!route) {
    console.error(`No route matches "${wanted}". Run with --list to see them.`)
    process.exit(2)
}

/**
 * `--matrix` photographs the route in every condition `device-matrix.mjs` names.
 *
 * It re-invokes this script once per condition rather than looping inside it. Everything
 * below is per-run and hard-won -- the settings are read back before they are changed, the
 * restore is registered against `exit` and both signals, and a font scale change restarts
 * every activity -- and a loop wrapped around that would have to take all of it apart for no
 * gain. One process per condition costs milliseconds against a walk that takes seconds, and
 * each condition restores the device on its own way out even when it fails.
 *
 * `--out` is a directory here, and the file names come from the matrix, because
 * `capture-compare.mjs` pairs a fresh frame with a reference frame by name.
 */
if (argv.includes('--matrix')) {
    mkdirSync(out, { recursive: true })
    let worst = 0
    for (const condition of MATRIX.android.conditions) {
        const file = join(out, `android-${slug(route[0])}${condition.suffix}.png`)
        const args = [process.argv[1], route[0], '--out', file, '--font-scale', condition.fontScale]
        if (condition.appearance === 'dark') args.push('--dark')
        console.log(`\n${route[0]} — ${describe(condition)}`)
        const done = spawnSync(process.execPath, args, { stdio: 'inherit' })
        worst = Math.max(worst, done.status ?? 1)
    }
    console.log(`\n${MATRIX.android.conditions.length} condition(s) into ${out}`)
    process.exit(worst)
}

const adb = resolveAdb()
const sh = adbRunner(adb, { onDeviceError: 'empty' })
if (!hasDevice(sh)) {
    console.error('No device or emulator is attached. Start one, then run this again.')
    process.exit(2)
}
// **Two devices is the case this used to fail at, with `adb: more than one device`.** These
// scripts pass no `-s`, deliberately: `adb` reads `ANDROID_SERIAL` itself, so naming the
// device is the caller's business and stays out of every `adb` call here. Met on 2026-09-12,
// with an emulator and a phone attached at once.
if (!process.env.ANDROID_SERIAL && /\bdevice\b[\s\S]*\bdevice\b/.test(sh('devices'))) {
    console.error(
        'More than one device is attached. Name the one you mean:\n' +
        '  ANDROID_SERIAL=emulator-5554 node scripts/capture-android.mjs ...',
    )
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

const { walk, perform, dump } = navigator(sh)
// A route's `!` steps are held back until the screen has been proved drawn — see
// `splitLate`. A condition that expires in four seconds cannot be set up before a
// four-second check, and the committed reader-chrome route was filing a bare page.
const [early, late] = splitLate(steps)
const missed = walk(early)
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

// The perishable part of the route, now that nothing slow is left to do.
const missedLate = perform(late)
if (missedLate !== null) {
    console.error(`Could not reach "${missedLate}" on the way to ${name}.`)
    process.exit(1)
}

// Settled: the last tap animates, and a screenshot mid-transition is a screenshot of
// neither screen. A `!` step already waited for its own animation, and waiting the full
// settle again is what expired the chrome, so that case gets the shorter one.
sleep(late.length > 0 ? 250 : 1200)
// `exec-out` rather than `shell`, because a screenshot is bytes and the shell mangles them.
const png = execFileSync(adb, ['exec-out', 'screencap', '-p'], { maxBuffer: 1 << 28 })
mkdirSync(dirname(out), { recursive: true })
writeFileSync(out, png)

const condition = [`font_scale ${scale}`, dark ? 'dark' : 'light'].join(', ')
console.log(`${name} (${condition}) -> ${out}  ${(png.length / 1024).toFixed(0)} KB`)
