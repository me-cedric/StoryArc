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
import { adbRunner, hasDevice, resolveAdb } from "./adb.mjs"
import { scan } from "./a11y-scan.mjs"
import { ROUTES, navigator } from "./android-routes.mjs"

/**
 * Runs adb, and refuses to hide the one failure that matters.
 *
 * A command that fails because the device said no is normal and returns empty. A command
 * that fails because adb itself is missing or unreachable is not: swallowing it makes
 * every check pass, which is how a crash on a screen went unnoticed. So that one throws
 * -- see scripts/adb.mjs, which now owns finding it.
 */
const sh = adbRunner(resolveAdb(), { onDeviceError: "empty" })

// Fail now rather than reporting a clean sweep against nothing.
if (!hasDevice(sh)) {
  console.error("No device or emulator is attached. Start one, then run this again.")
  process.exit(2)
}

// Reaching a screen belongs to `android-routes.mjs`. This file only judges what it finds.
const { dump, walk } = navigator(sh)

// `--a11y` also inspects each screen it reaches. Off by default, so a crash walk stays a
// crash walk and its exit code keeps meaning what it has always meant.
const wantsAccessibility = process.argv.includes("--a11y")
const density = Number(/(\d+)/.exec(sh("shell", "wm", "density"))?.[1] ?? 420)
const filter = process.argv.filter((a) => !a.startsWith("--"))[2]
const routes = filter ? ROUTES.filter(([name]) => name.includes(filter)) : ROUTES
const failures = []

for (const [name, steps] of routes) {
  // Cleared before the launch `walk` does, so the log holds this route and no other.
  sh("logcat", "-c", "-b", "crash")
  const missed = walk(steps)
  const reached = missed === null
  if (!reached) failures.push(`${name}: could not reach "${missed}"`)

  // The screen is already here and already dumped. Asking whether anything on it is
  // unnamed, raw or too small to hit costs one more read of a tree this walk has in hand --
  // and `a11y-scan.mjs` on its own only ever sees whichever screen was in front of whoever
  // ran it. Sixteen routes checked is what iOS's own audit now does per screen.
  if (reached && wantsAccessibility) {
    const { problems } = scan(dump(), density)
    for (const problem of problems) failures.push(`${name}: ${problem}`)
    if (problems.length > 0) console.log(`  a11y   ${name}: ${problems.length} problem(s)`)
  }

  const crash = sh("logcat", "-d", "-b", "crash")
  const fatal = /FATAL EXCEPTION/.test(crash) && crash.includes("app.storyarc.debug")
  if (fatal) {
    // The exception line, which is the one that names the cause.
    const line = crash.split("\n").find((l) => /^\s*\S+\s+\S+\s+\d+\s+\d+ E AndroidRuntime: [a-z]/.test(l))
    failures.push(`${name}: CRASHED — ${(line ?? "").split("AndroidRuntime: ").pop()?.slice(0, 160)}`)
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

// Counted from the routes, not from the failures. Subtracting every failure conflated the
// three kinds all over again, one line below the comment saying not to: with `--a11y` on,
// three accessibility problems on two screens made a clean walk of sixteen routes report
// `13/16`, which reads as three screens that could not be reached. Somebody chased that as
// a regression for an hour. A screen with an unnamed view is a screen this walk *reached*.
const walked = routes.length - crashes.length - unreachable.length
console.log(`\n${walked}/${routes.length} routes walked and survived`)
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
