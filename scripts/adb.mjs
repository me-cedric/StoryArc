// Where adb is, shared by the three scripts that drive a device.
//
// It was written three times and disagreed with itself. `pseudo-locale.mjs` knew about
// the Homebrew SDK; `a11y-scan.mjs` and `smoke-android.mjs` knew only about the one
// Android Studio installs and then fell back to the bare name. On a machine with the
// Homebrew command-line tools and no `adb` on PATH -- which is what a `brew install
// --cask android-commandlinetools` leaves you with -- two of the three device checks
// could not run at all, and the one that could was the one nobody reached for first.
//
// So: one resolver, and it asks the project before it guesses. `apps/android/
// local.properties` already has to name the SDK for Gradle to build, so a machine that
// can build the app can always find its adb.

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

/** `sdk.dir` out of the Gradle properties file, which is gitignored and machine-local. */
function sdkFromLocalProperties(root = ROOT) {
  const file = join(root, 'apps/android/local.properties')
  if (!existsSync(file)) return null
  // Gradle escapes the colon in a Windows path and tolerates spaces around the equals.
  const line = /^\s*sdk\.dir\s*=\s*(.+?)\s*$/m.exec(readFileSync(file, 'utf8'))
  return line ? line[1].replaceAll('\\:', ':').replaceAll('\\\\', '\\') : null
}

/**
 * Every place adb could be, best first.
 *
 * Exported so the self-test can assert the order without a device attached. An explicit
 * `$ADB` wins because someone who sets it means it; the project's own `sdk.dir` comes
 * next because it is the SDK this repository actually builds against; the two
 * conventional install locations follow; the bare name is last, and only because a
 * container image sometimes has adb on PATH and nothing else.
 */
export function adbCandidates(env = process.env, root = ROOT) {
  const sdks = [env.ANDROID_HOME, env.ANDROID_SDK_ROOT, sdkFromLocalProperties(root)]
  return [
    env.ADB,
    ...sdks.filter(Boolean).map((sdk) => join(sdk, 'platform-tools/adb')),
    join(homedir(), 'Library/Android/sdk/platform-tools/adb'),
    '/opt/homebrew/share/android-commandlinetools/platform-tools/adb',
  ].filter(Boolean)
}

/**
 * The adb to run.
 *
 * Preferring the bare name first looks harmless and is not: a child process does not
 * always inherit a shell's PATH, so `adb` resolves to nothing, every call throws ENOENT,
 * and a swallowed ENOENT reads as "every screen is fine".
 */
export function resolveAdb(env = process.env, root = ROOT) {
  return adbCandidates(env, root).find(existsSync) ?? 'adb'
}

/**
 * Runs adb and refuses to hide the one failure that matters.
 *
 * `onDeviceError` decides what a command that ran and failed means. A screen walk treats
 * it as "the device said no" and carries on with an empty string; a scan that needs the
 * output treats it as fatal. Neither may treat a *missing adb* as either, which is why
 * ENOENT is re-thrown with the path that was tried, above whatever the caller wanted.
 */
export function adbRunner(adb = resolveAdb(), { onDeviceError = 'throw' } = {}) {
  return (...args) => {
    try {
      return execFileSync(adb, args, { encoding: 'utf8', maxBuffer: 1 << 26 })
    } catch (error) {
      if (error.code === 'ENOENT') {
        throw new Error(
          `adb not found at ${adb}. Set ANDROID_HOME, or sdk.dir in apps/android/local.properties, or put adb on PATH.`
        )
      }
      if (onDeviceError === 'empty') return ''
      throw error
    }
  }
}

/** True when at least one device or emulator is attached. */
export function hasDevice(run) {
  return /\bdevice\b/.test(run('devices'))
}
