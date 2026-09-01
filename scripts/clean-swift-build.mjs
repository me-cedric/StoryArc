#!/usr/bin/env node
/**
 * The Swift packages' own build directories, in **this** checkout.
 *
 * Not the same job as `clean-build-data.mjs`, and deliberately a separate script. That one
 * reclaims disk from worktrees that no longer exist and is safe to run mid-wave, because it
 * only touches build folders whose project is gone. This one deletes build products for a
 * checkout that is very much still here, which is the opposite promise.
 *
 * **Why it exists.** `StoryArcCore` is not built with library evolution, so a non-resilient
 * type's memory layout is baked into every client that compiled against it. Add a case to an
 * enum like `ReadingPosition` and an incrementally-rebuilt test target keeps the **old**
 * layout: the symptoms are a test failing on two values that print identically, and then the
 * whole suite exiting on signal 11 with no message. `pnpm check` reports
 *
 *     exited with unexpected signal code 11
 *
 * and nothing else. It is not a defect, it is not flaky, and it is not a compiler bug —
 * which is what it looks like for the first hour.
 *
 * Found on 2026-09-01 after `ReadingPosition` gained its `listening` case. It cost an agent an
 * hour, and it will cost the next person the same unless the remedy is a command with a name.
 *
 * Usage:
 *   node scripts/clean-swift-build.mjs            remove them
 *   node scripts/clean-swift-build.mjs --dry-run  say what would go, remove nothing
 */
import { existsSync, readdirSync, rmSync, statSync } from 'node:fs'
import { join } from 'node:path'

/** Every Swift package in the repository, by where its `Package.swift` sits. */
const PACKAGES = 'apps/ios/Packages'
const dry = process.argv.includes('--dry-run')

/** Bytes under a directory. Walked rather than shelled out to, so it works with no `du`. */
function size(path) {
    let total = 0
    for (const entry of readdirSync(path, { withFileTypes: true })) {
        const child = join(path, entry.name)
        // Symlinks are not followed: SPM puts one at `.build/debug` pointing at the
        // architecture folder, and following it counts everything twice.
        if (entry.isSymbolicLink()) continue
        total += entry.isDirectory() ? size(child) : statSync(child).size
    }
    return total
}

const gigabytes = (bytes) => `${(bytes / 1024 ** 3).toFixed(2)} GB`

if (!existsSync(PACKAGES)) {
    console.error(`${PACKAGES} is not here — run this from the repository root.`)
    process.exit(1)
}

let reclaimed = 0
let removed = 0

for (const entry of readdirSync(PACKAGES, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue
    const build = join(PACKAGES, entry.name, '.build')
    if (!existsSync(build)) continue
    const bytes = size(build)
    reclaimed += bytes
    removed += 1
    console.log(`${dry ? 'would remove' : 'removing'}  ${build}  (${gigabytes(bytes)})`)
    if (!dry) rmSync(build, { recursive: true, force: true })
}

if (removed === 0) {
    console.log('No Swift package build directories in this checkout. Nothing to clean.')
} else {
    console.log(
        `${dry ? 'Would reclaim' : 'Reclaimed'} ${gigabytes(reclaimed)} from ${removed} `
        + `package build director${removed === 1 ? 'y' : 'ies'}.`
    )
    console.log('The next `pnpm test:ios` rebuilds from scratch, which takes a few minutes.')
}
