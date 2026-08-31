#!/usr/bin/env node
/**
 * Runs the Android build with a JDK and an SDK it found for itself.
 *
 * Four parallel agents in four worktrees hit the same three things in a row, and each one
 * lost time to it:
 *
 * 1. **`java` is not on PATH.** Homebrew installs its JDKs keg-only, and macOS ships
 *    `/usr/bin/java` -- a stub that reports "Unable to locate a Java Runtime" and shadows
 *    anything later on PATH. `org.gradle.java.home` does not help: that redirects the
 *    daemon's JVM, and the *wrapper* needs a JVM before it can read a property file.
 * 2. **`ANDROID_HOME` is not exported**, so AGP cannot find the SDK.
 * 3. **`apps/android/local.properties` does not exist in a fresh worktree.** It is
 *    gitignored -- correctly, it names a machine path -- so every new worktree starts
 *    without it and Gradle refuses to configure.
 *
 * All three are answerable without asking anyone, so this asks. `pnpm lint:android`,
 * `pnpm test:android` and `pnpm build:android` go through here; a direct `./gradlew` still
 * needs `JAVA_HOME` set, which AGENTS.md §5 now says.
 *
 * Usage:
 *   node scripts/gradle.mjs lint
 *   node scripts/gradle.mjs :feature:library:testDebugUnitTest
 *   node scripts/gradle.mjs --print-env      what it resolved, and nothing else
 */
import { execFileSync, spawnSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const ANDROID = join(ROOT, 'apps/android')

/** The Java version every module pins. Kept as a string because that is what the tools take. */
const JAVA_VERSION = '21'

/**
 * Everywhere a JDK could be, best first.
 *
 * `/usr/libexec/java_home -v 21` is asked before the hard-coded locations because it is
 * macOS's own answer and it knows about JDKs this list has never heard of. It is asked
 * *after* `$JAVA_HOME` because someone who exported one means it.
 */
export function javaHomeCandidates(env = process.env) {
    const asked = () => {
        if (process.platform !== 'darwin') return null
        try {
            return execFileSync('/usr/libexec/java_home', ['-v', JAVA_VERSION], {
                encoding: 'utf8',
                stdio: ['ignore', 'pipe', 'ignore'],
            }).trim()
        } catch {
            return null
        }
    }
    return [
        env.JAVA_HOME,
        asked(),
        `/opt/homebrew/opt/openjdk@${JAVA_VERSION}`,
        `/usr/local/opt/openjdk@${JAVA_VERSION}`,
        '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
    ].filter(Boolean)
}

/** Everywhere an SDK could be, best first. `sdk.dir` is read from whichever worktree this is. */
export function sdkCandidates(env = process.env, root = ROOT) {
    return [
        env.ANDROID_HOME,
        env.ANDROID_SDK_ROOT,
        sdkFromLocalProperties(root),
        '/opt/homebrew/share/android-commandlinetools',
        join(homedir(), 'Library/Android/sdk'),
    ].filter(Boolean)
}

function sdkFromLocalProperties(root) {
    const file = join(root, 'apps/android/local.properties')
    if (!existsSync(file)) return null
    const line = /^\s*sdk\.dir\s*=\s*(.+?)\s*$/m.exec(readFileSync(file, 'utf8'))
    return line ? line[1].replaceAll('\\:', ':').replaceAll('\\\\', '\\') : null
}

/** A JDK is a directory with a `bin/java` in it. Anything else is a stale path in an env var. */
const isJdk = (home) => existsSync(join(home, 'bin/java'))

/** An SDK is a directory with `platform-tools` in it. A bare `~/Library/Android` is not one. */
const isSdk = (home) => existsSync(join(home, 'platform-tools')) || existsSync(join(home, 'platforms'))

export function resolveJavaHome(env = process.env) {
    const found = javaHomeCandidates(env).find(isJdk)
    if (found) return found
    throw new Error(
        `No JDK ${JAVA_VERSION} found. Tried:\n  ${javaHomeCandidates(env).join('\n  ')}\n` +
            `Install one (brew install openjdk@${JAVA_VERSION}) or export JAVA_HOME.`
    )
}

export function resolveSdk(env = process.env, root = ROOT) {
    const found = sdkCandidates(env, root).find(isSdk)
    if (found) return found
    throw new Error(
        `No Android SDK found. Tried:\n  ${sdkCandidates(env, root).join('\n  ')}\n` +
            `Export ANDROID_HOME or set sdk.dir in apps/android/local.properties.`
    )
}

/**
 * Writes `local.properties` when it is absent.
 *
 * Gradle reads `ANDROID_HOME` too, so this is not strictly required to build -- but Android
 * Studio and the IDE tooling read only the file, and a worktree that builds from the shell
 * and not from the IDE is a confusing place to land. The file is gitignored, so writing it
 * cannot end up in a commit.
 */
function ensureLocalProperties(sdk) {
    const file = join(ANDROID, 'local.properties')
    if (existsSync(file)) return false
    writeFileSync(file, `# Written by scripts/gradle.mjs. Gitignored: it names a machine path.\nsdk.dir=${sdk}\n`)
    return true
}

const args = process.argv.slice(2)
const javaHome = resolveJavaHome()
const sdk = resolveSdk()

if (args[0] === '--print-env') {
    console.log(`JAVA_HOME=${javaHome}`)
    console.log(`ANDROID_HOME=${sdk}`)
    process.exit(0)
}

if (ensureLocalProperties(sdk)) {
    console.log(`gradle: wrote apps/android/local.properties (sdk.dir=${sdk})`)
}

const result = spawnSync(join(ANDROID, 'gradlew'), args, {
    cwd: ANDROID,
    stdio: 'inherit',
    env: {
        ...process.env,
        JAVA_HOME: javaHome,
        ANDROID_HOME: sdk,
        PATH: `${join(javaHome, 'bin')}:${process.env.PATH ?? ''}`,
    },
})

process.exit(result.status ?? 1)
