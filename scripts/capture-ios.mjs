#!/usr/bin/env node
/**
 * Photographs iOS screens, the way `capture-android.mjs` photographs Android ones.
 *
 * `xcrun simctl io booted screenshot` takes a picture of whatever happens to be in front of
 * it, so every iOS proof this project has taken involved someone driving the simulator by
 * hand. The one time that was automated with synthetic clicks into the Simulator window, the
 * coordinate mapping was wrong and it produced a picture of *Home* filed as *Downloads* —
 * which is the failure mode `AuditWalk.swift` already warns about at length: a check that
 * can silently measure the wrong screen is worse than no check.
 *
 * A UI test already knows how to reach a screen, and `UITests/ScreenshotTests.swift` is that
 * walk. This drives it and lifts the screenshots out of the result bundle, which is the part
 * that is tedious rather than interesting.
 *
 * Usage:
 *   node scripts/capture-ios.mjs --out docs/designs/screenshots/after-x
 *   node scripts/capture-ios.mjs --out /tmp/shots --only testCaptureDownloads
 *   node scripts/capture-ios.mjs --out /tmp/shots --appearance dark
 *
 * `--appearance` exists because the app's default appearance is `.system`, and the settings
 * are stored as one JSON blob under a single key — so there is no launch argument that sets
 * only the theme. The simulator's own appearance is the lever, and it has to be set from
 * outside the test process. Without this flag, every iOS dark capture this project owns was
 * taken by somebody flipping the simulator by hand and remembering to flip it back; the
 * `-dark` suffix on the filenames is added here so a light run and a dark run of the same
 * walk cannot overwrite each other, which is what made that manual route lossy.
 */
import { execFileSync } from 'node:child_process'
import { copyFileSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'

const argv = process.argv.slice(2)
const flag = (name, fallback = null) => {
    const at = argv.indexOf(`--${name}`)
    return at === -1 ? fallback : argv[at + 1]
}

const out = flag('out')
if (!out) {
    console.error('Usage: node scripts/capture-ios.mjs --out <directory> [--only <testName>] [--device <udid-or-name>] [--appearance light|dark]')
    process.exit(2)
}

const only = flag('only')
const device = flag('device', 'StoryArc-iPhone17Pro')

/** `light`, `dark`, or null to photograph the simulator however it is already set. */
const appearance = flag('appearance')
if (appearance && !['light', 'dark'].includes(appearance)) {
    console.error(`--appearance takes 'light' or 'dark', not '${appearance}'.`)
    process.exit(2)
}
/** So a light run and a dark run of the same walk do not overwrite each other. */
const suffix = appearance === 'dark' ? '-dark' : ''
const bundle = '/tmp/storyarc-shots.xcresult'
const staging = '/tmp/storyarc-shots'

/** A booted simulator's udid, because `-destination name=` does not match a renamed device. */
function udidFor(nameOrUdid) {
    if (/^[0-9A-F-]{36}$/i.test(nameOrUdid)) return nameOrUdid
    const listed = execFileSync('xcrun', ['simctl', 'list', 'devices'], { encoding: 'utf8' })
    const found = new RegExp(`${nameOrUdid}\\s+\\(([0-9A-F-]{36})\\)`, 'i').exec(listed)
    if (!found) {
        console.error(`No simulator called ${nameOrUdid}. \`xcrun simctl list devices\` shows what there is.`)
        process.exit(2)
    }
    return found[1]
}

const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] })

for (const path of [bundle, staging]) rmSync(path, { recursive: true, force: true })

// `--only` takes a bare test name in `ScreenshotTests`, or `Class/testName` for a capture
// suite of its own. Class-qualified because there is more than one: `PlayerScreenshotTests`
// exists, and a bare name pointed at the wrong class **passed with nothing attached** — the
// `-only-testing:` filter matched no test, xcodebuild reported success, and the only clue was
// this script's own "attached nothing" message. Silent success is the worst answer a capture
// harness can give.
const target = only
    ? `StoryArcUITests/${only.includes('/') ? only : `ScreenshotTests/${only}`}`
    : 'StoryArcUITests/ScreenshotTests'
const udid = udidFor(device)

// Read it before setting it, and put it back afterwards even if the run fails. A capture
// script that leaves the device in dark mode makes the *next* person's light capture a lie,
// and they will not know to check.
let restore = null
if (appearance) {
    try {
        restore = run('xcrun', ['simctl', 'ui', udid, 'appearance']).trim() || null
    } catch {
        // Older simctl cannot read it back. Setting still works; restoring does not, and
        // saying so is better than silently leaving the device flipped.
        console.warn('Could not read the simulator\'s current appearance — it will not be restored.')
    }
    run('xcrun', ['simctl', 'ui', udid, 'appearance', appearance])
    console.log(`Simulator appearance set to ${appearance}${restore ? ` (was ${restore})` : ''}.`)
}
const putBack = () => {
    if (appearance && restore && restore !== appearance) {
        try {
            run('xcrun', ['simctl', 'ui', udid, 'appearance', restore])
            console.log(`Simulator appearance put back to ${restore}.`)
        } catch {
            console.warn(`Could not put the appearance back to ${restore}. Do it by hand.`)
        }
    }
}

console.log(`Capturing ${target} on ${device}…`)
try {
    run('xcodebuild', [
        'test',
        '-project', 'apps/ios/StoryArc.xcodeproj',
        '-scheme', 'StoryArc',
        '-destination', `id=${udid}`,
        '-only-testing:' + target,
        '-resultBundlePath', bundle,
        '-quiet',
    ])
} catch (error) {
    putBack()
    console.error('The capture run failed. Its output:')
    console.error((error.stdout ?? '') + (error.stderr ?? ''))
    process.exit(1)
}
putBack()

run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', bundle, '--output-path', staging])

mkdirSync(out, { recursive: true })
const manifest = JSON.parse(readFileSync(join(staging, 'manifest.json'), 'utf8'))
let saved = 0
for (const test of manifest) {
    for (const attachment of test.attachments ?? []) {
        // `downloads_0_<uuid>.png` — the name the test gave it is everything before the
        // first underscore, and the rest is XCTest making it unique.
        const name = attachment.suggestedHumanReadableName.split('_')[0]
        copyFileSync(join(staging, attachment.exportedFileName), join(out, `ios-${name}${suffix}.png`))
        console.log(`  ios-${name}${suffix}.png`)
        saved += 1
    }
}

if (saved === 0) {
    console.error('The run passed and attached nothing. Check that the attachments are `.keepAlways`:')
    console.error('an attachment on a passing test is discarded by default.')
    process.exit(1)
}
console.log(`${saved} screenshot(s) in ${out}`)
