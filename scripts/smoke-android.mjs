#!/usr/bin/env node
/**
 * Walks every screen on a connected device and reports any that crashes.
 *
 * Exists because opening About crashed the whole process for days without anyone
 * noticing. Two checks had said it was fine: a `@Preview`, which cannot nest the screen
 * inside its real host, and an accessibility scan, which happily read the
 * "StoryArc keeps stopping" dialog and reported no problems.
 *
 * A crash is not subtle, and neither is this: reach a screen, then ask logcat whether the
 * process died. Nothing else about the screen is judged here. `a11y-scan.mjs` does that,
 * and it is only meaningful once the screen exists.
 *
 * Usage:
 *   node scripts/smoke-android.mjs            walk every route
 *   node scripts/smoke-android.mjs Settings   walk only routes whose name matches
 */
import { execFileSync } from 'node:child_process'

import { adbRunner, hasDevice, resolveAdb } from './adb.mjs'
import { scan } from './a11y-scan.mjs'

const PKG = 'app.storyarc.debug'
const ACTIVITY = `${PKG}/app.storyarc.MainActivity`

/**
 * Runs adb, and refuses to hide the one failure that matters.
 *
 * A command that fails because the device said no is normal and returns empty. A command
 * that fails because adb itself is missing or unreachable is not: swallowing it makes
 * every check pass, which is how a crash on a screen went unnoticed. So that one throws
 * -- see scripts/adb.mjs, which now owns finding it.
 */
const sh = adbRunner(resolveAdb(), { onDeviceError: 'empty' })

// Fail now rather than reporting a clean sweep against nothing.
if (!hasDevice(sh)) {
  console.error('No device or emulator is attached. Start one, then run this again.')
  process.exit(2)
}

const sleep = (ms) => execFileSync('/bin/sleep', [String(ms / 1000)])

/**
 * Every route worth reaching, as the taps that reach it.
 *
 * A route is a list of names to tap in order. Each is matched against a node's text or
 * its content description, so the list reads as what a person would do.
 */
const ROUTES = [
  ['Home', []],
  ['Library', ['Library']],
  ['Downloads', ['Downloads']],
  // A cover leads to the publication's page now, and the page's own action leads to the
  // reader. That is two taps where this list used to have one, and the reason the list
  // said twelve of thirteen routes were unreachable the first time it ran after the
  // navigation rewrite: it was still describing the app as it had been.
  ['Publication page', ['Library', ', CBZ']],
  ['Comic reader', ['Library', ', CBZ', 'Read']],
  ['Comic reader > chrome', ['Library', ', CBZ', 'Read', '@tap-centre']],
  ['EPUB reader', ['Library', ', EPUB', 'Read']],
  // Settings left the browse path in the shell revamp: it is behind the library's
  // overflow, which is why naming it as a first step found nothing.
  ['Settings', ['Library', 'More', 'Settings']],
  ['Settings > Appearance', ['Library', 'More', 'Settings', 'Appearance']],
  ['Settings > Reading', ['Library', 'More', 'Settings', 'Reading']],
  ['Settings > Privacy', ['Library', 'More', 'Settings', 'Privacy']],
  ['Settings > About', ['Library', 'More', 'Settings', 'About']],
  ['Settings > About > licence', ['Library', 'More', 'Settings', 'About', 'Readium Kotlin Toolkit']],
  ['Settings > Your libraries', ['Library', 'More', 'Settings', 'Your libraries']],
  ['Settings > Downloads', ['Library', 'More', 'Settings', 'Downloads and storage']],
  ['Settings > Language', ['Library', 'More', 'Settings', 'Language']],
]

/**
 * The accessibility tree, retried, because a single attempt lies.
 *
 * uiautomator answers `ERROR: null root node returned by UiTestAutomationBridge` and writes
 * nothing whenever it is asked while a window is animating -- which, in a script whose every
 * step is a tap followed immediately by a read, is most of the time. The caller then saw an
 * empty document, concluded the control it wanted was absent, scrolled looking for it, and
 * eventually reported the route unreachable. Thirteen of sixteen routes failed that way
 * against an app where every one of them worked.
 *
 * So: ask again, and give the window a moment first. Three attempts is enough for a
 * transition; a screen that cannot be read after that is genuinely not there.
 */
const dump = () => {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    if (attempt > 0) sleep(900)
    const dumped = sh('shell', 'uiautomator', 'dump', '/sdcard/smoke.xml')
    if (!/dumped to/.test(dumped)) continue
    const xml = sh('shell', 'cat', '/sdcard/smoke.xml')
    if (xml.includes('<?xml')) return xml.slice(xml.indexOf('<?xml'))
  }
  return ''
}

const centre = (xml, needle) => {
  for (const [tag] of xml.matchAll(/<node\b[^>]*?\/?>/g)) {
    const attrs = Object.fromEntries(
      [...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([, key, value]) => [key, value]),
    )
    const name = `${attrs['content-desc'] ?? ''}\0${attrs.text ?? ''}`
    if (!name.toLowerCase().includes(needle.toLowerCase())) continue
    const box = /\[(\d+),(\d+)]\[(\d+),(\d+)]/.exec(attrs.bounds ?? '')
    if (box) {
      const [l, t, r, b] = box.slice(1).map(Number)
      return [Math.round((l + r) / 2), Math.round((t + b) / 2)]
    }
  }
  return null
}

const tap = (x, y) => {
  sh('shell', 'input', 'tap', String(x), String(y))
  sleep(1700)
}

// `--a11y` also inspects each screen it reaches. Off by default, so a crash walk stays a
// crash walk and its exit code keeps meaning what it has always meant.
const wantsAccessibility = process.argv.includes('--a11y')
const density = Number(/(\d+)/.exec(sh('shell', 'wm', 'density'))?.[1] ?? 420)
const filter = process.argv.filter((a) => !a.startsWith('--'))[2]
const routes = filter ? ROUTES.filter(([name]) => name.includes(filter)) : ROUTES
const failures = []

for (const [name, steps] of routes) {
  // A fresh launch per route. Walking between routes means a back press per hop, and one
  // back press too many leaves the app without saying so.
  sh('logcat', '-c', '-b', 'crash')
  sh('shell', 'am', 'force-stop', PKG)
  sh('shell', 'am', 'start', '-n', ACTIVITY)
  sleep(3500)

  let reached = true
  for (const step of steps) {
    if (step === '@tap-centre') {
      // Revealing the reader chrome is a tap on the page, not on a named control.
      tap(540, 1200)
      continue
    }
    let spot = null
    for (let attempt = 0; attempt < 3 && !spot; attempt += 1) {
      spot = centre(dump(), step)
      if (!spot) {
        sh('shell', 'input', 'swipe', '540', '1800', '540', '800', '260')
        sleep(1200)
      }
    }
    if (!spot) {
      reached = false
      failures.push(`${name}: could not reach "${step}"`)
      break
    }
    tap(...spot)
  }

  // The screen is already here and already dumped. Asking whether anything on it is
  // unnamed, raw or too small to hit costs one more read of a tree this walk has in hand —
  // and `a11y-scan.mjs` on its own only ever sees whichever screen was in front of whoever
  // ran it. Sixteen routes checked is what iOS's own audit now does per screen.
  if (reached && wantsAccessibility) {
    const { problems } = scan(dump(), density)
    for (const problem of problems) failures.push(`${name}: ${problem}`)
    if (problems.length > 0) console.log(`  a11y   ${name}: ${problems.length} problem(s)`)
  }

  const crash = sh('logcat', '-d', '-b', 'crash')
  const fatal = /FATAL EXCEPTION/.test(crash) && crash.includes(PKG)
  if (fatal) {
    // The exception line, which is the one that names the cause.
    const line = crash.split('\n').find((l) => /^\s*\S+\s+\S+\s+\d+\s+\d+ E AndroidRuntime: [a-z]/.test(l))
    failures.push(`${name}: CRASHED — ${(line ?? '').split('AndroidRuntime: ').pop()?.slice(0, 160)}`)
    console.log(`  CRASH  ${name}`)
  } else if (reached) {
    console.log(`  ok     ${name}`)
  }
}

// Two outcomes, and conflating them is how this script lied the first time it ran after
// the navigation rewrite: it reported `1/13 routes clean`, which reads as twelve crashes,
// when there were none and the route map was simply describing an older app.
//
// A crash is what this exists to find. A route it could not walk is a question about the
// map or about what is on the device -- an empty library has no cover to tap, and a
// publication whose source is unreachable has no `Read` to press -- and it is reported as
// its own thing, in its own words.
const crashes = failures.filter((f) => f.includes('CRASHED'))
const accessibility = failures.filter((f) => /: (UNNAMED|RAW-VALUE|SMALL)\b/.test(f))
const unreachable = failures.filter((f) => !crashes.includes(f) && !accessibility.includes(f))

console.log(`\n${routes.length - failures.length}/${routes.length} routes walked and survived`)
if (crashes.length) {
  console.log(`\n${crashes.length} CRASHED:`)
  for (const failure of crashes) console.log(`  ${failure}`)
}
if (accessibility.length) {
  console.log(`\n${accessibility.length} accessibility problem(s) across the routes:`)
  for (const problem of accessibility) console.log(`  ${problem}`)
}
if (unreachable.length) {
  console.log(`\n${unreachable.length} could not be reached -- the route map may be stale,`)
  console.log('or this device has no publication in the state the route needs:')
  for (const failure of unreachable) console.log(`  ${failure}`)
}

// A crash fails loudly. A route that could not be walked is worth a different exit code,
// because the two want different things done about them.
process.exit(crashes.length ? 1 : unreachable.length ? 2 : accessibility.length ? 3 : 0)
process.exitCode = failures.length > 0 ? 1 : 0
