#!/usr/bin/env node
/**
 * The 800-line cap, actually counted.
 *
 * `AGENTS.md` and the compass contract both state it, three change task lists track it,
 * and **nothing has ever measured it**. `pnpm lint` runs ten checks and not one of them
 * counts a line, which is how five Kotlin files went past the cap without anyone noticing
 * and how the notes tracking them came to name the wrong file as the largest.
 *
 * This is a ratchet rather than a cliff. Splitting `ReaderScreen.kt` is a slice of its own
 * with a test suite in front of it, and a gate that fails the build until somebody does
 * that is a gate somebody switches off. So: every file already over the cap is recorded
 * here with the length it had when it was recorded, and the check fails if it **grows** or
 * if a **new** file crosses. Shrinking one below its recorded length is free; taking it
 * under 800 means deleting its line here, and the check says so when you do.
 *
 * Usage:
 *   node scripts/line-cap.mjs              check
 *   node scripts/line-cap.mjs --list       every file over the cap, longest first
 *   node scripts/line-cap.mjs --self-test  the rules, without touching the tree
 */
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

/** What the contract says, in one place. */
const CAP = 800

/**
 * What was already over the cap on 2026-08-31, with the length it had that day.
 *
 * Every one of these is debt with a name. Do not add to it without saying why in the
 * commit that does — a new entry here is a decision to ship a file nobody can hold in
 * their head, and the whole point of a ratchet is that adding a tooth costs something.
 */
const ALLOWED = {
    'apps/android/feature/reader/src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt': 1893,
    'apps/android/feature/library/src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt': 1717,
    'apps/android/feature/epubreader/src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt': 1051,
    'apps/android/feature/reader/src/main/kotlin/app/storyarc/feature/reader/ReaderViewModel.kt': 811,
}

/** Source this project writes. Generated files and dependencies are nobody's to split. */
const COUNTED = /\.(kt|swift)$/
const SKIPPED = /(^|\/)(build|\.build|DerivedData|node_modules|\.git|\.claude)(\/|$)/

/** Every counted file under `root`, as repository-relative paths. */
export function sources(root = ROOT) {
    const found = []
    const walk = (dir) => {
        for (const entry of readdirSync(dir)) {
            const path = join(dir, entry)
            const rel = relative(root, path)
            if (SKIPPED.test(rel)) continue
            if (statSync(path).isDirectory()) walk(path)
            else if (COUNTED.test(entry)) found.push(rel)
        }
    }
    walk(root)
    return found.sort()
}

/**
 * Lines, counted the way `wc -l` counts them.
 *
 * `split('\n').length` is one more than that on any file ending in a newline, which is
 * every file here — and an off-by-one in a ratchet is not cosmetic: it reports every
 * recorded file as having grown by one the first time it runs.
 */
const lines = (path, root = ROOT) => {
    const text = readFileSync(join(root, path), 'utf8')
    return text.split('\n').length - (text.endsWith('\n') ? 1 : 0)
}

/**
 * What is wrong with the tree, as sentences.
 *
 * Exported and pure over its inputs so the self-test can put every rule through it without
 * a checkout that happens to be in the right state.
 */
export function verdicts(measured, allowed = ALLOWED, cap = CAP) {
    const problems = []
    for (const [path, length] of Object.entries(measured)) {
        const budget = allowed[path]
        if (budget === undefined) {
            if (length > cap) {
                problems.push(
                    `${path} is ${length} lines, over the ${cap}-line cap. Split it, or record it in scripts/line-cap.mjs and say why in the commit.`
                )
            }
        } else if (length > budget) {
            problems.push(
                `${path} grew from ${budget} to ${length}. It is already over the cap; it may not get longer.`
            )
        } else if (length <= cap) {
            problems.push(
                `${path} is ${length} lines and under the cap at last. Delete its line from scripts/line-cap.mjs.`
            )
        }
    }
    for (const path of Object.keys(allowed)) {
        if (!(path in measured)) {
            problems.push(`${path} is recorded in scripts/line-cap.mjs and no longer exists. Delete its line.`)
        }
    }
    return problems
}

function selfTest() {
    const cases = [
        [{ measured: { a: 900 }, allowed: {} }, 1, 'a new file over the cap fails'],
        [{ measured: { a: 700 }, allowed: {} }, 0, 'a file under the cap passes'],
        [{ measured: { a: 900 }, allowed: { a: 900 } }, 0, 'a recorded file at its length passes'],
        [{ measured: { a: 850 }, allowed: { a: 900 } }, 0, 'a recorded file that shrank passes'],
        [{ measured: { a: 901 }, allowed: { a: 900 } }, 1, 'a recorded file that grew fails'],
        [{ measured: { a: 700 }, allowed: { a: 900 } }, 1, 'a recorded file under the cap asks to be delisted'],
        [{ measured: {}, allowed: { a: 900 } }, 1, 'a recorded file that is gone asks to be delisted'],
    ]
    let ok = true
    for (const [{ measured, allowed }, expected, name] of cases) {
        const got = verdicts(measured, allowed).length
        if (got !== expected) {
            ok = false
            console.error(`  ${name}: expected ${expected} problem(s), got ${got}`)
        }
    }
    console.log(ok ? `line cap self-test: ${cases.length} checks passed` : 'line cap self-test failed')
    process.exit(ok ? 0 : 1)
}

const mode = process.argv[2]
if (mode === '--self-test') selfTest()

const measured = Object.fromEntries(
    sources()
        .map((path) => [path, lines(path)])
        .filter(([path, length]) => length > CAP || path in ALLOWED)
)

if (mode === '--list') {
    for (const [path, length] of Object.entries(measured).sort((a, b) => b[1] - a[1])) {
        console.log(`${String(length).padStart(5)}  ${path}`)
    }
    process.exit(0)
}

const problems = verdicts(measured)
if (problems.length > 0) {
    console.error(`line cap: ${problems.length} problem(s)`)
    for (const problem of problems) console.error(`  ${problem}`)
    process.exit(1)
}
console.log(`line cap: ${Object.keys(measured).length} recorded file(s), none grew, nothing new crossed ${CAP}.`)
