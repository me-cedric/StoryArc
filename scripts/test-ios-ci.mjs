#!/usr/bin/env node
// Runs the iOS UI tests that CI can actually prove something with, and keeps that list honest.
//
// **Why a list at all.** `StoryArcUITests` holds 202 tests and 181 of them are *captures*:
// walks that photograph a screen so a design change can be read. They are a local tool. On a
// GitHub runner they take about two hours, they attach their screenshots to a result bundle
// nobody downloads, and several of them cannot pass there at all — they want the 226-file
// corpus, a Kavita mock on port 5001, or an OPDS mock on 4444, and a runner has none of those.
//
// Measured on 2026-09-12: the `iOS` workflow had not gone green once in its last twenty runs.
// Every run was either a two-hour failure or a cancellation by the next push, because the job
// outlived the interval between commits. Six tests failed, all six for a missing fixture
// rather than for a defect.
//
// So CI runs the audits and the behaviour walks — the 21 tests that assert something about the
// app rather than photograph it — and the captures stay where they belong, behind
// `pnpm capture:ios` on a machine with the fixtures. `--check` prints both counts, so the
// numbers in this paragraph can be re-measured rather than believed.
//
// **The list drifts, so `--check` exists.** A new audit class that nobody adds here would
// silently not run in CI, which is the failure mode this file would otherwise introduce. The
// check reads every test method in `apps/ios/UITests`, calls anything named `testCapture…` a
// capture, and demands that every other test is either in `RUN` or in `EXCLUDED` with a
// reason. `pnpm lint` runs it, so the decision is forced at the moment a test is added.
//
// Usage:
//   node scripts/test-ios-ci.mjs             run them
//   node scripts/test-ios-ci.mjs --check     prove the list still covers every non-capture test
//   node scripts/test-ios-ci.mjs --list      print what would run

import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SUITE = 'StoryArcUITests'

/**
 * What CI runs. A class name runs every test in it; a `Class/test` runs the one.
 *
 * Whole classes where every test asserts, single tests where the class is otherwise captures.
 */
const RUN = [
  // Apple's own `performAccessibilityAudit` on seven screens: contrast, clipped text, hit
  // regions, missing descriptions. This is the job's reason to exist.
  'AccessibilityAuditTests',
  // The same audit on the player's six surfaces, plus two behaviours a sheet has to keep.
  'PlayerAuditTests',
  // The same audit on both readers.
  'ReaderAuditTests',
  // The round trip `reading-progress` calls the app's most consequential behaviour: read,
  // close, relaunch, reopen, same page.
  'ReadingContinuityUITests',
  // A notice that has to outlive six seconds, which only a running app can say.
  'SkippedNoticeTests',
  // Two assertions that live inside capture classes.
  'ScreenshotTests/testTheInertCapsuleIsDimmerThanTheLiveOne',
  'SweepSearchTests/testSearchOffersAFieldToTypeIn',
]

/**
 * Non-capture tests CI deliberately does not run, and why.
 *
 * Each one needs something a runner does not have. A reason, not a name, because the next
 * reader has to be able to tell a deliberate exclusion from a forgotten one.
 */
const EXCLUDED = {
  'AddMockKavitaTests/testAddTheMockServer':
    'Adds the mock Kavita server through the real form. It needs `node scripts/kavita-server.mjs --port 5001` running, which a runner does not start. It is capture setup: the source it adds is what the Shelves captures photograph.',
  'AppIconCaptureTests/testZZRestoreTheDefaultIcon':
    'Puts the alternate app icon back after the five icon captures. With no captures to clean up after, it has nothing to do.',
}

const argv = process.argv.slice(2)

/**
 * Every `XCTestCase` in the UI-test target, with the tests it declares.
 *
 * Two passes, because a test case's tests are not all in the file that declares it:
 * `LibrarySelectionCapture.swift` and `SkippedNoticeCapture.swift` are both
 * `extension ScreenshotTests`, written that way because `ScreenshotTests.swift` was one line
 * under the 400-line cap. A one-pass reader attributes those tests to a class that does not
 * exist, which is what the first version of this did.
 */
function classes() {
  const directory = join(ROOT, 'apps/ios/UITests')
  const files = readdirSync(directory)
    .filter((name) => name.endsWith('.swift'))
    .map((name) => [name, readFileSync(join(directory, name), 'utf8')])

  const found = new Map()
  for (const [name, text] of files) {
    for (const line of text.split('\n')) {
      const declared = /^\s*(?:final\s+)?class\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase/.exec(line)
      if (declared) found.set(declared[1], { file: name, tests: [] })
    }
  }

  for (const [name, text] of files) {
    let current = null
    for (const line of text.split('\n')) {
      const opened = /^\s*(?:(?:final\s+)?class|extension)\s+([A-Za-z0-9_]+)\b/.exec(line)
      // A type this file opens that is not a test case — a helper struct, an enum of
      // fixtures — takes `current` away, so its methods are not read as tests.
      if (opened) current = found.has(opened[1]) ? opened[1] : null
      const test = /^\s*func\s+(test[A-Za-z0-9_]*)\s*\(/.exec(line)
      if (test && current) found.get(current).tests.push(test[1])
    }
  }
  return found
}

if (argv.includes('--check')) {
  const declared = classes()
  const wholeClasses = new Set(RUN.filter((entry) => !entry.includes('/')))
  const singleTests = new Set(RUN.filter((entry) => entry.includes('/')))
  const problems = []

  for (const name of wholeClasses) {
    if (!declared.has(name)) problems.push(`${name} is in the CI list and no such class exists.`)
  }
  for (const identifier of [...singleTests, ...Object.keys(EXCLUDED)]) {
    const [name, test] = identifier.split('/')
    const entry = declared.get(name)
    if (!entry) problems.push(`${identifier} names a class that does not exist.`)
    else if (!entry.tests.includes(test)) problems.push(`${identifier} names a test ${name} does not declare.`)
  }

  for (const [name, { file, tests }] of declared) {
    if (wholeClasses.has(name)) continue
    for (const test of tests) {
      if (test.startsWith('testCapture')) continue
      const identifier = `${name}/${test}`
      if (singleTests.has(identifier) || EXCLUDED[identifier]) continue
      problems.push(
        `${identifier} (${file}) asserts something and CI does not run it. `
          + 'Add it to RUN, or to EXCLUDED with the reason a runner cannot.'
      )
    }
  }

  if (problems.length) {
    console.error('test-ios-ci: the CI list no longer covers what it claims.')
    for (const problem of problems) console.error(`  ${problem}`)
    process.exit(1)
  }
  const count = [...declared].reduce((total, [, entry]) => total + entry.tests.length, 0)
  const runs = [...declared].reduce(
    (total, [name, entry]) =>
      total + (wholeClasses.has(name) ? entry.tests.length : entry.tests.filter((test) => singleTests.has(`${name}/${test}`)).length),
    0
  )
  console.log(`test-ios-ci: ${runs} of ${count} UI tests run in CI; the rest are captures or excluded with a reason.`)
  process.exit(0)
}

const only = RUN.flatMap((entry) => ['-only-testing:' + `${SUITE}/${entry}`])

if (argv.includes('--list')) {
  console.log(only.join('\n'))
  process.exit(0)
}

// `xcodebuild` refuses to write a result bundle over an existing one — it stops at once with
// `error: Existing file at -resultBundlePath` and runs no test. The script this replaced
// cleared the path on every run for that reason, and leaving it out made every second run in
// one tree fail for a reason that has nothing to do with the app.
const bundle = join(ROOT, '.build/xcresult/ui.xcresult')
mkdirSync(dirname(bundle), { recursive: true })
rmSync(bundle, { recursive: true, force: true })

try {
  execFileSync(
    'xcodebuild',
    [
      'test-without-building',
      '-project', 'StoryArc.xcodeproj',
      '-scheme', 'StoryArc',
      '-destination', 'platform=iOS Simulator,name=iPhone 17 Pro',
      '-derivedDataPath', '../../.build/ios-ui',
      ...only,
      // For the reason `test:ios:epub` gives: a failing run otherwise spends ten minutes
      // collecting a simulator diagnostic nobody reads.
      '-collect-test-diagnostics', 'never',
      '-resultBundlePath', '../../.build/xcresult/ui.xcresult',
      '-quiet',
    ],
    { cwd: join(ROOT, 'apps/ios'), stdio: 'inherit' }
  )
} catch (error) {
  // The child has already printed why. A Node stack trace on top of it buries the one line
  // that names the failing test, which is what a reader came here for.
  process.exit(error.status ?? 1)
}
