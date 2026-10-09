#!/usr/bin/env node
// Runs the iOS screen-catalogue snapshot tests on a simulator.
//
//   node scripts/snap-ios.mjs                       verify: a changed image fails its test
//   node scripts/snap-ios.mjs --record              record every reference again
//   node scripts/snap-ios.mjs --only LibraryCatalogueTests   one class, or Class/testCase
//
// The references are recorded on an iPhone 17 running iOS 26.2, and that is the default. Liquid
// Glass and the system text rendering change between iOS releases, so another OS version fails
// the comparison by a few thousand pixels or by a whole bar; record again on that version.
// Set SNAP_DEVICE to an xcodebuild destination to use another simulator, for example
// SNAP_DEVICE='platform=iOS Simulator,id=<udid>'. The iPhone 17 Pro has the same 402 by 874 size.
//
// The tests are a unit-test bundle hosted by the app (`StoryArcSnapshotTests` in project.yml), so
// Liquid Glass and blurs are drawn by a real key window. The references sit in
// `apps/ios/SnapshotTests/__Snapshots__`.
//
// A simulator this run booted is shut down again. One that was already up is left alone.

import { execFileSync, spawnSync } from 'node:child_process'
import { mkdirSync, rmSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const IOS = join(ROOT, 'apps/ios')
const RESULT = join(ROOT, '.build/xcresult/snapshots.xcresult')

const args = process.argv.slice(2)
const record = args.includes('--record')
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null
const destination = process.env.SNAP_DEVICE ?? 'platform=iOS Simulator,name=iPhone 17,OS=26.2'

const booted = () => {
  const out = execFileSync('xcrun', ['simctl', 'list', 'devices', 'booted', '-j'], { encoding: 'utf8' })
  return new Set(
    Object.values(JSON.parse(out).devices)
      .flat()
      .map((device) => device.udid),
  )
}

const before = booted()
mkdirSync(dirname(RESULT), { recursive: true })
rmSync(RESULT, { recursive: true, force: true })
execFileSync('xcodegen', ['generate'], { cwd: IOS, stdio: 'ignore' })

const run = spawnSync(
  'xcodebuild',
  [
    'test',
    '-project', 'StoryArc.xcodeproj',
    '-scheme', 'StoryArc',
    '-destination', destination,
    '-derivedDataPath', join(ROOT, '.build/ios-snap'),
    `-only-testing:StoryArcSnapshotTests${only ? `/${only}` : ''}`,
    '-collect-test-diagnostics', 'never',
    '-test-timeouts-enabled', 'YES',
    '-default-test-execution-time-allowance', '120',
    '-maximum-test-execution-time-allowance', '300',
    '-resultBundlePath', RESULT,
    '-quiet',
  ],
  {
    cwd: IOS,
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
    // `TEST_RUNNER_` is stripped by xcodebuild, so the library reads SNAPSHOT_TESTING_RECORD and
    // the host app reads TZ. UTC keeps a date on screen the same on every machine.
    env: {
      ...process.env,
      TEST_RUNNER_TZ: 'UTC',
      ...(record ? { TEST_RUNNER_SNAPSHOT_TESTING_RECORD: 'all' } : {}),
    },
  },
)

process.stdout.write(run.stdout ?? '')
process.stderr.write(run.stderr ?? '')

for (const udid of booted()) {
  if (!before.has(udid)) spawnSync('xcrun', ['simctl', 'shutdown', udid], { stdio: 'ignore' })
}

// Recording writes the new files and then reports each as a failure, by design of the library.
// The files are the result, so a record run that built and ran is a pass.
const output = `${run.stdout}\n${run.stderr}`
const buildFailed = /\.swift:\d+:\d+: error:|because the build failed|BUILD FAILED|INTERRUPTED/.test(output)
if (record && run.status !== 0 && !buildFailed) {
  console.log('snap:ios:record wrote the references. Run `pnpm snap:ios` to check them.')
  process.exit(0)
}
process.exit(run.status ?? 1)
