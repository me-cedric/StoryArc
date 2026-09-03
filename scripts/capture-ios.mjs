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
 *   node scripts/capture-ios.mjs --out /tmp/shots --only SweepLibraryTests
 *   node scripts/capture-ios.mjs --out /tmp/shots --only SweepLibraryTests/testCaptureCoverGrid
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
// Per-run, because two runs sharing one path destroy each other's bundle. It happened: a
// capture chain was interrupted, one of its children survived, and the next run's
// `xcresulttool export` reported "the run did not finish" on a suite that had finished — the
// other process was writing the same `.xcresult` at the same time. Eleven walks were lost to
// it, and the symptom named the wrong run.
const bundle = `/tmp/storyarc-shots-${process.pid}.xcresult`
const staging = `/tmp/storyarc-shots-${process.pid}`

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

// `--only` takes a bare test name in `ScreenshotTests`, a whole class, or `Class/testName`.
// Class-qualified because there is more than one: `PlayerScreenshotTests` exists, and a bare
// name pointed at the wrong class **passed with nothing attached** — the `-only-testing:`
// filter matched no test, xcodebuild reported success, and the only clue was this script's
// own "attached nothing" message. Silent success is the worst answer a capture harness can
// give.
//
// **A bare class name used to be that same silent success.** This file's own usage note and
// `AppIconCapture.swift`'s both say `--only AppIconCaptureTests` runs the class; it was
// rewritten to `ScreenshotTests/AppIconCaptureTests`, which is not a test, so the run passed
// and attached nothing. Whether an unqualified argument is a class or a test is decided by
// the one convention XCTest itself enforces — a test method begins with `test` — rather than
// by guessing, so `--only testCaptureHome` still reaches `ScreenshotTests` and `--only
// SweepLibraryTests` reaches the class.
const qualified = only && (only.includes('/') || !/^test/.test(only))
const target = only
    ? `StoryArcUITests/${qualified ? only : `ScreenshotTests/${only}`}`
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

/** How many cases actually ran, because `xcodebuild` exits 0 when the filter matches none.
 *
 * Read out of the result bundle rather than scraped from the log: `-quiet` prints no
 * `Test Case … passed` line at all, so a regex over the output reported "matched nothing"
 * on a run that had just taken four screenshots. The bundle is the same artifact the
 * attachments come out of, and it counts skips — which is the number that matters here,
 * because a walk that skips passes and photographs nothing.
 */
function report() {
    try {
        const summary = JSON.parse(run('xcrun', [
            'xcresulttool', 'get', 'test-results', 'summary',
            '--path', bundle, '--format', 'json',
        ]))
        const { passedTests = 0, failedTests = 0, skippedTests = 0 } = summary
        const total = passedTests + failedTests + skippedTests
        if (total === 0) {
            console.warn('The run executed no test case. The -only-testing filter matched nothing.')
            return
        }
        console.log(
            `${total} test case(s): ${passedTests} passed, ${failedTests} failed, `
            + `${skippedTests} skipped`
        )
        for (const failure of summary.testFailures ?? []) {
            console.log(`  failed: ${failure.testName ?? '?'} — ${failure.failureText ?? ''}`)
        }
    } catch {
        // Not worth failing a capture over. The "attached nothing" check below is the gate.
        console.warn('Could not read the run summary out of the result bundle.')
    }
}

// The project is generated and gitignored, and a UI-test file added since the last
// `xcodegen generate` is in no target — so the filter matches nothing, xcodebuild exits 0,
// and the only symptom is this script's "attached nothing". `build:ios` and
// `build:ios:tests` both regenerate first; a capture that did not was the one way to add a
// walk and photograph none of it.
run('xcodegen', ['generate', '--project', 'apps/ios', '--spec', 'apps/ios/project.yml'])

console.log(`Capturing ${target} on ${device}…`)
/** Whether some case failed. The screenshots the others took are still worth having. */
let failed = false
try {
    run('xcodebuild', [
        'test',
        '-project', 'apps/ios/StoryArc.xcodeproj',
        '-scheme', 'StoryArc',
        '-destination', `id=${udid}`,
        '-only-testing:' + target,
        '-resultBundlePath', bundle,
        // Ten minutes, spent after every failure, collecting a simulator diagnostic nobody
        // reads — then reported as `Failure collecting diagnostics from simulator: Timed
        // out after 600.0 seconds`. A fourteen-minute run of which four minutes were the
        // tests. `test:ios:epub` already passes this.
        '-collect-test-diagnostics', 'never',
        '-quiet',
    ])
    report()
} catch (error) {
    failed = true
    report()
    // The diagnostics, then the tail. A failed `swift-frontend` invocation is echoed in
    // full — one command line of about six thousand characters — and it buried the two
    // lines that named the file and the error underneath it.
    const output = (error.stdout ?? '') + (error.stderr ?? '')
    const lines = output.split('\n')
    const diagnostics = lines.filter((line) => /error:|warning: .*deprecat|Testing failed/.test(line))
    console.error('The capture run failed. Its diagnostics:')
    console.error((diagnostics.length ? diagnostics : lines.slice(-25)).join('\n'))
    console.error(`(${lines.length} lines of output suppressed; re-run the xcodebuild line to see it all.)`)
}
putBack()

// **Exported even when a case failed, which it was not.** One failing walk in a suite of
// sixteen exited here and threw away the eleven screenshots the passing ones had already
// attached — a fourteen-minute run for nothing, and the temptation to delete the failing
// walk rather than fix it. A capture harness should hand back what it managed to take.

// A run that was killed leaves a bundle with no `Info.plist`, and the export then threw a
// forty-line Node stack trace over the reason the run had stopped. Say it in one line.
try {
    run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', bundle, '--output-path', staging])
} catch {
    console.error(`No attachments could be read out of ${bundle}: the run did not finish.`)
    process.exit(1)
}

mkdirSync(out, { recursive: true })
const manifest = JSON.parse(readFileSync(join(staging, 'manifest.json'), 'utf8'))
let saved = 0
let skipped = 0
for (const test of manifest) {
    for (const attachment of test.attachments ?? []) {
        // `downloads_0_<uuid>.png` — the name the test gave it is everything before the
        // first underscore, and the rest is XCTest making it unique.
        const name = attachment.suggestedHumanReadableName.split('_')[0]
        // XCTest attaches its own artefacts on a failure — a screenshot of the moment, an
        // activity log, a crash report — and they arrive in the same manifest. Filed under
        // `ios-<name>.png` they would sit in the deliverable looking like captures. Only
        // what a walk named, and a walk here names in lower-case kebab.
        if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name) || !attachment.exportedFileName.endsWith('.png')) {
            skipped += 1
            continue
        }
        copyFileSync(join(staging, attachment.exportedFileName), join(out, `ios-${name}${suffix}.png`))
        console.log(`  ios-${name}${suffix}.png`)
        saved += 1
    }
}
if (skipped > 0) console.log(`${skipped} attachment(s) XCTest added itself were left behind.`)

if (saved === 0) {
    console.error('The run attached nothing this harness recognised. Check that the attachments')
    console.error('are `.keepAlways`: an attachment on a passing test is discarded by default.')
    process.exit(1)
}
console.log(`${saved} screenshot(s) in ${out}`)
// The exit code is the run's, not the export's. A suite with one failing walk has still
// handed back everything the others took, and the caller needs to know both.
if (failed) process.exit(1)
