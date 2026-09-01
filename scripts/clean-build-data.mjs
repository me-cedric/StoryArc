#!/usr/bin/env node
/**
 * Build data for worktrees that no longer exist.
 *
 * `git worktree remove` deletes the checkout and **nothing else**. Xcode keeps its build
 * products in `~/Library/Developer/Xcode/DerivedData/<name>-<hash of the project path>`,
 * outside the repository, and that hash is different for every worktree — so each parallel
 * agent leaves roughly **1.5 GB** behind that no git command will ever touch, on top of the
 * ~700 MB AGENTS.md §9 already warns about inside the checkout itself.
 *
 * That was found the way these things are found: 92 GB of DerivedData across 50 folders,
 * 47 of them orphaned, on a machine with 1.9 GB free. Removing them returned 70 GB.
 *
 * Safety is the whole design. Every folder carries an `info.plist` naming the project it
 * was built from; a folder is removed **only** when that path no longer exists on disk. A
 * worktree that is still there — including one an agent is building in right now — is
 * never touched, so this is safe to run mid-wave.
 *
 * **The shared caches are not orphaned and are usually the biggest thing there.** They are
 * skipped by default, on purpose: they rebuild themselves and deleting one costs the next
 * build minutes. But skipping them *silently* hid the real state of the disk, and that cost
 * an hour on 2026-09-01: `ModuleCache.noindex` had reached **15 GB** of a 22 GB DerivedData
 * on a volume with 1.2 GB free, this script answered "nothing orphaned", and
 * `CoverCacheTests` failed on two assertions — the two that write bytes — which reads
 * exactly like a code defect and is not one. A full disk makes a write fail silently and a
 * test fail loudly, in the wrong place.
 *
 * So the sizes are always reported, the free space is always reported, and `--caches` is the
 * lever when that space is what is needed.
 *
 * Usage:
 *   node scripts/clean-build-data.mjs            remove orphaned build data
 *   node scripts/clean-build-data.mjs --dry-run  say what would go, remove nothing
 *   node scripts/clean-build-data.mjs --caches   also clear the shared caches (slower next build)
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync, rmSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const DERIVED = join(homedir(), 'Library/Developer/Xcode/DerivedData')
const dry = process.argv.includes('--dry-run')
const caches = process.argv.includes('--caches')

/** Free bytes on the volume, so a report can say whether any of this matters. */
function freeBytes() {
    try {
        const line = execFileSync('df', ['-k', DERIVED], { encoding: 'utf8' }).trim().split('\n').pop()
        return Number(line.split(/\s+/)[3]) * 1024
    } catch {
        return null
    }
}

/**
 * Bytes under a path via `du`, which is far faster than walking a cache of millions of
 * small files. Falls back to the walker, which is what the rest of this script uses.
 */
function measured(path) {
    try {
        const out = execFileSync('du', ['-sk', path], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
        return Number(out.trim().split(/\s+/)[0]) * 1024
    } catch {
        return size(path)
    }
}

/** The project a build folder was built from, or null when it does not say. */
function workspaceOf(folder) {
    const plist = join(folder, 'info.plist')
    if (!existsSync(plist)) return null
    try {
        return execFileSync('plutil', ['-extract', 'WorkspacePath', 'raw', plist], {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'ignore'],
        }).trim()
    } catch {
        return null
    }
}

/** Bytes under a directory, for saying what was reclaimed rather than guessing. */
function size(path) {
    try {
        return Number(execFileSync('du', ['-sk', path], { encoding: 'utf8' }).split('\t')[0]) * 1024
    } catch {
        return 0
    }
}

const gigabytes = (bytes) => `${(bytes / 1024 ** 3).toFixed(1)} GB`

if (!existsSync(DERIVED)) {
    console.log('No DerivedData on this machine. Nothing to clean.')
    process.exit(0)
}

let reclaimed = 0
let removed = 0
let kept = 0

const sharedCaches = []

for (const entry of readdirSync(DERIVED)) {
    const folder = join(DERIVED, entry)
    if (!statSync(folder).isDirectory()) continue
    // Shared caches rather than a project's build products. They rebuild themselves, and
    // deleting one costs the next build several minutes for no lasting gain — so they are
    // never removed as *orphans*. They are measured either way: see the header for what
    // hiding their size cost once.
    if (entry.endsWith('.noindex')) {
        sharedCaches.push({ entry, folder, bytes: measured(folder) })
        continue
    }

    const workspace = workspaceOf(folder)
    if (workspace && existsSync(workspace)) {
        kept += 1
        continue
    }

    const bytes = size(folder)
    reclaimed += bytes
    removed += 1
    console.log(`${dry ? 'would remove' : 'removing'}  ${entry}  (${gigabytes(bytes)})`)
    console.log(`             built from ${workspace ?? 'a project it does not name'}, which is gone`)
    if (!dry) rmSync(folder, { recursive: true, force: true })
}

console.log(
    removed === 0
        ? `Nothing orphaned. ${kept} build folder(s) still belong to a checkout that exists.`
        : `${dry ? 'Would reclaim' : 'Reclaimed'} ${gigabytes(reclaimed)} from ${removed} orphaned build folder(s). ${kept} still in use.`
)

// ── The shared caches ────────────────────────────────────────────────────────

const cacheTotal = sharedCaches.reduce((sum, cache) => sum + cache.bytes, 0)
if (sharedCaches.length) {
    console.log(`\nShared caches, ${gigabytes(cacheTotal)} in total:`)
    for (const cache of sharedCaches.sort((a, b) => b.bytes - a.bytes)) {
        console.log(`  ${gigabytes(cache.bytes).padStart(8)}  ${cache.entry}`)
    }
    if (caches) {
        for (const cache of sharedCaches) {
            console.log(`${dry ? 'would clear' : 'clearing'}  ${cache.entry}`)
            if (!dry) rmSync(cache.folder, { recursive: true, force: true })
        }
        console.log(
            `${dry ? 'Would clear' : 'Cleared'} ${gigabytes(cacheTotal)} of shared cache. `
            + 'The next build recompiles the module cache, which takes a few minutes once.'
        )
    } else {
        console.log('  Not removed — they belong to no project and rebuild themselves. `--caches` clears them.')
    }
}

const free = freeBytes()
if (free !== null) {
    console.log(`\n${gigabytes(free)} free on that volume.`)
    // Four parallel agents need roughly 2 GB each in DerivedData alone, so this is not a
    // round number chosen for comfort. Overridable because a warning branch that cannot be
    // reached without filling the disk is a warning branch nobody has ever seen fire:
    // `STORYARC_FREE_FLOOR_GB=999 node scripts/clean-build-data.mjs --dry-run`.
    const floor = Number(process.env.STORYARC_FREE_FLOOR_GB ?? 8)
    if (free < floor * 1024 ** 3) {
        console.error(
            '\nThat is not enough for a wave of parallel agents, and a full disk does not fail'
            + ' honestly:\n  a write fails silently and a test fails loudly somewhere else.'
            + ' `CoverCacheTests` failing on\n  exactly its two byte-writing assertions is what'
            + ' that looks like.\n'
            + (caches ? '' : '  Run with `--caches` to clear the shared caches above.\n')
        )
    }
}
