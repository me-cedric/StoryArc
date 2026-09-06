#!/usr/bin/env node
/**
 * Reads how many frames a page turn cost, off a phone, and prints the count.
 *
 * `page-transitions` says a transition "holds the display's refresh rate, and a dropped frame
 * during a turn is treated as a defect". Nothing in this repository had ever counted a frame,
 * and the reason is honest: a simulator draws at its Mac's refresh rate and an emulator at its
 * host's, so a number taken on a build machine is a number about the build machine. The
 * scenario needs a device, and a check that needs a device tends not to get run. This is the
 * part that makes running it a five-minute job instead of a project.
 *
 * **It prints what the device reported. It judges nothing.** No frame rate is asserted here or
 * in any test. The instrument is `FrameProbe` on both platforms — `CADisplayLink` on iOS,
 * `Choreographer` on Android — and both are off unless armed, so this script's first job is to
 * arm them and its last job is to put the switch back.
 *
 * **Android.** The switch is a global setting that only `adb` can write, and the app reads it
 * on every turn, so the reader does not have to be restarted. The setting is restored when
 * this exits, however it exits — a left-behind `storyarc_frame_probe 1` costs the next
 * person's battery, which is the failure `capture-android.mjs` guards against for `font_scale`.
 *
 * **iOS.** The switch is a launch argument, which no ordinary launch can set, so the app is
 * launched here. `devicectl --console` connects the app's standard output to this process,
 * which is where the report is written.
 *
 * Usage:
 *   node scripts/measure-turn.mjs --android
 *   node scripts/measure-turn.mjs --ios
 *   node scripts/measure-turn.mjs --ios --device "Cédric's iPhone" --turns 10
 */
import { execFileSync, spawn } from 'node:child_process'
import { readFileSync, rmSync } from 'node:fs'

import { adbRunner, hasDevice, resolveAdb } from './adb.mjs'

const argv = process.argv.slice(2)
const flag = (name, fallback = null) => {
    const at = argv.indexOf(`--${name}`)
    return at === -1 ? fallback : argv[at + 1]
}

const turns = Number(flag('turns', '5'))
const timeout = Number(flag('timeout', '180'))
if (!Number.isInteger(turns) || turns < 1 || !Number.isFinite(timeout) || timeout < 1) {
    console.error('--turns takes a whole number of turns, --timeout a number of seconds.')
    process.exit(2)
}

const wantsAndroid = argv.includes('--android')
const wantsIos = argv.includes('--ios')
if (wantsAndroid === wantsIos) {
    console.error('Usage: node scripts/measure-turn.mjs --android | --ios [--device <name>] [--turns 5] [--timeout 180]')
    console.error('Pick one platform. A turn is measured on the device that draws it.')
    process.exit(2)
}

/** Matches what `FrameProbe` writes on either platform. */
const REPORT = /delivered=(\d+) dropped=(\d+) span_ms=(-?\d+)/

/** The global setting `FrameProbe.isArmed` reads on Android. Kept spelled the same. */
const ARMING_KEY = 'storyarc_frame_probe'

/** `FrameProbe.TAG` on Android. */
const TAG = 'StoryArcFrames'

/** The iOS launch argument, and the app it is passed to. */
const IOS_ARGUMENT = '-StoryArcFrameProbe'
const IOS_BUNDLE = 'app.storyarc.StoryArc'

const sleep = (ms) => execFileSync('/bin/sleep', [String(ms / 1000)])

/** What to ask for, once the instrument is armed. */
const ASK = `Open a publication in curl mode and turn ${turns} page${turns === 1 ? '' : 's'} with your finger.`

/**
 * What one turn cost, as the device reported it.
 *
 * The rate is divided out here rather than in the app, because it is a *report* and not a
 * measurement: the app counts frames and the display's own seconds, and nothing anywhere
 * decides what a good number is.
 *
 * `delivered - 1` because the span runs from the first frame to the last, which is one
 * interval fewer than the frame count. Counting the frames instead reports a rate a few per
 * cent too high, which is exactly the kind of number nobody would check.
 */
function describe(line, at) {
    const [, delivered, dropped, spanMs] = REPORT.exec(line)
    const span = Number(spanMs) / 1000
    const rate = span > 0 && Number(delivered) > 1 ? ((Number(delivered) - 1) / span).toFixed(1) : '—'
    return `turn ${at}: ${delivered} frames delivered, ${dropped} dropped, over ${spanMs} ms (${rate} delivered per second)`
}

function summarise(lines) {
    if (lines.length === 0) {
        console.error('No turn was reported. Read any error above first — the app may not have started.')
        console.error('Otherwise: the publication must be open in curl mode, and the page dragged by a finger.')
        process.exit(1)
    }
    for (const [at, line] of lines.entries()) console.log(describe(line, at + 1))
    const totals = lines.map((line) => REPORT.exec(line))
    const delivered = totals.reduce((sum, [, count]) => sum + Number(count), 0)
    const dropped = totals.reduce((sum, [, , count]) => sum + Number(count), 0)
    console.log(`${lines.length} turns: ${delivered} frames delivered, ${dropped} dropped.`)
    console.log('These numbers describe this device and this build. Nothing asserts them.')
}

// MARK: - Android

function measureAndroid() {
    const sh = adbRunner(resolveAdb(), { onDeviceError: 'empty' })
    if (!hasDevice(sh)) {
        console.error('No device or emulator is attached. Connect one, then run this again.')
        process.exit(2)
    }

    const was = sh('shell', 'settings', 'get', 'global', ARMING_KEY).trim()
    const restore = () => {
        if (was && was !== 'null') sh('shell', 'settings', 'put', 'global', ARMING_KEY, was)
        else sh('shell', 'settings', 'delete', 'global', ARMING_KEY)
    }
    process.on('exit', restore)
    for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => process.exit(130))

    sh('shell', 'settings', 'put', 'global', ARMING_KEY, '1')
    sh('logcat', '-c')
    console.log(`Armed. ${ASK}`)

    let lines = []
    for (let waited = 0; waited < timeout && lines.length < turns; waited += 1) {
        sleep(1000)
        lines = sh('logcat', '-d', '-s', `${TAG}:I`).split('\n').filter((line) => REPORT.test(line))
    }
    summarise(lines.slice(0, turns))
}

// MARK: - iOS

/** The connected iOS device, or the one named. `capture-ios.mjs` resolves a simulator the same way. */
function iosDevice(wanted) {
    const out = `/tmp/storyarc-devices-${process.pid}.json`
    execFileSync('xcrun', ['devicectl', 'list', 'devices', '--quiet', '--json-output', out])
    const listed = JSON.parse(readFileSync(out, 'utf8')).result.devices
    rmSync(out, { force: true })
    const phones = listed.filter((device) => device.hardwareProperties?.platform === 'iOS')
    const found = wanted
        ? phones.find((device) => [device.identifier, device.hardwareProperties?.udid, device.deviceProperties?.name].includes(wanted))
        : phones.find((device) => device.connectionProperties?.tunnelState === 'connected')
    if (!found) {
        console.error(wanted ? `No connected iPhone or iPad called ${wanted}.` : 'No iPhone or iPad is connected.')
        console.error('`xcrun devicectl list devices` shows what there is. Unlock the device and trust this Mac.')
        process.exit(2)
    }
    return found
}

function measureIos() {
    const device = iosDevice(flag('device'))
    console.log(`Armed on ${device.deviceProperties?.name ?? device.identifier}.`)
    console.log(ASK)

    const app = spawn('xcrun', [
        'devicectl', 'device', 'process', 'launch',
        '--device', device.identifier,
        '--console', '--terminate-existing',
        IOS_BUNDLE,
        // Everything after this reaches the app rather than `devicectl`.
        '--', IOS_ARGUMENT, 'YES',
    ])

    const lines = []
    let finished = false
    const done = (code) => {
        // The kill below raises `exit`, which would report the same run twice.
        if (finished) return
        finished = true
        app.kill()
        summarise(lines.slice(0, turns))
        process.exit(code)
    }
    const clock = setTimeout(() => done(lines.length >= turns ? 0 : 1), timeout * 1000)

    let rest = ''
    app.stdout.on('data', (chunk) => {
        rest += chunk.toString()
        const parts = rest.split('\n')
        rest = parts.pop()
        for (const line of parts) {
            if (!REPORT.test(line)) continue
            lines.push(line)
            if (lines.length >= turns) {
                clearTimeout(clock)
                done(0)
            }
        }
    })
    app.stderr.on('data', (chunk) => process.stderr.write(chunk))
    app.on('error', () => {
        console.error('`xcrun devicectl` could not be run. Install Xcode, or run this on the Mac the phone is plugged into.')
        process.exit(2)
    })
    app.on('exit', () => {
        clearTimeout(clock)
        done(lines.length >= turns ? 0 : 1)
    })
}

if (wantsAndroid) measureAndroid()
else measureIos()
