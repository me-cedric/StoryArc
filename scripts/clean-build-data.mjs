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
 * Usage:
 *   node scripts/clean-build-data.mjs            remove orphaned build data
 *   node scripts/clean-build-data.mjs --dry-run  say what would go, remove nothing
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync, rmSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const DERIVED = join(homedir(), 'Library/Developer/Xcode/DerivedData')
const dry = process.argv.includes('--dry-run')

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

for (const entry of readdirSync(DERIVED)) {
    const folder = join(DERIVED, entry)
    if (!statSync(folder).isDirectory()) continue
    // Shared caches rather than a project's build products. They rebuild themselves, and
    // deleting one costs the next build several minutes for no lasting gain.
    if (entry.endsWith('.noindex')) continue

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
