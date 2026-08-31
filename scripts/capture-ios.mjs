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
    console.error('Usage: node scripts/capture-ios.mjs --out <directory> [--only <testName>] [--device <udid-or-name>]')
    process.exit(2)
}

const only = flag('only')
const device = flag('device', 'StoryArc-iPhone17Pro')
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

const target = only ? `StoryArcUITests/ScreenshotTests/${only}` : 'StoryArcUITests/ScreenshotTests'
console.log(`Capturing ${target} on ${device}…`)
try {
    run('xcodebuild', [
        'test',
        '-project', 'apps/ios/StoryArc.xcodeproj',
        '-scheme', 'StoryArc',
        '-destination', `id=${udidFor(device)}`,
        '-only-testing:' + target,
        '-resultBundlePath', bundle,
        '-quiet',
    ])
} catch (error) {
    console.error('The capture run failed. Its output:')
    console.error((error.stdout ?? '') + (error.stderr ?? ''))
    process.exit(1)
}

run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', bundle, '--output-path', staging])

mkdirSync(out, { recursive: true })
const manifest = JSON.parse(readFileSync(join(staging, 'manifest.json'), 'utf8'))
let saved = 0
for (const test of manifest) {
    for (const attachment of test.attachments ?? []) {
        // `downloads_0_<uuid>.png` — the name the test gave it is everything before the
        // first underscore, and the rest is XCTest making it unique.
        const name = attachment.suggestedHumanReadableName.split('_')[0]
        copyFileSync(join(staging, attachment.exportedFileName), join(out, `ios-${name}.png`))
        console.log(`  ios-${name}.png`)
        saved += 1
    }
}

if (saved === 0) {
    console.error('The run passed and attached nothing. Check that the attachments are `.keepAlways`:')
    console.error('an attachment on a passing test is discarded by default.')
    process.exit(1)
}
console.log(`${saved} screenshot(s) in ${out}`)
