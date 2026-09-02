#!/usr/bin/env node
/**
 * A change that reads as finished while it is still carrying partials.
 *
 * **`openspec-guard` cannot see a `[~]`, and that is the hole this closes.** Its
 * `taskProgress` counts `- [ ]` and `- [x]` and nothing else — read
 * `docs/agent-compass/scripts/lib/openspec.mjs`. So a partial is in neither the numerator nor
 * the denominator, with two consequences:
 *
 * 1. **The reported ratio is wrong**, and wrong in the flattering direction.
 *    `audiobooks-and-playback` reports **15/29** while its list holds 15 done, 13 open and
 *    **23 partial** — 15 of 51. Anybody reading the guard sees a change half finished when it
 *    is under a third.
 * 2. **`[ready]` fires on the last `[ ]`, not on the last piece of work.** A change with every
 *    `[ ]` ticked and twenty `[~]` still open is announced as ready to verify and archive —
 *    and archiving is the one action that cannot be undone cheaply, because it moves the
 *    change directory and applies its deltas.
 *
 * This repository uses `[~]` heavily and on purpose: a two-platform change is routinely done
 * on one platform and not the other, and the convention is to tick `[~]` and name the missing
 * half rather than to round up. That convention is *why* the hole matters here more than it
 * would elsewhere.
 *
 * So this fails on the dangerous shape — no `[ ]` left and at least one `[~]` — and prints the
 * honest three-way count for every active change either way. It does not try to be the guard;
 * it is the one number the guard drops.
 *
 * The vendored guard is not edited: `docs/agent-compass/` is a submodule, and a local edit to
 * a managed file is lost on the next sync. Reported upstream-worthy, fixed here.
 *
 * Usage:
 *   node scripts/partial-tasks-check.mjs              check, and print the counts
 *   node scripts/partial-tasks-check.mjs --self-test  prove the check can fail
 */
import { existsSync, readFileSync, readdirSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const CHANGES = 'docs/openspec/changes'

/** The same file set the guard reads: the change's list, plus one per capability. */
function taskFiles(changeDir) {
    const files = [join(changeDir, 'tasks.md')]
    const specs = join(changeDir, 'specs')
    if (existsSync(specs)) {
        for (const capability of readdirSync(specs, { withFileTypes: true })) {
            if (capability.isDirectory()) files.push(join(specs, capability.name, 'tasks.md'))
        }
    }
    return files.filter((file) => existsSync(file))
}

/**
 * Done, open and partial for one change.
 *
 * The three patterns mirror the guard's own two so the numbers can be compared directly —
 * `[-*]` for the bullet, any indent, `[xX]` for done. A line that is not one of the three is
 * prose, and prose in a task list is the norm in this repository rather than the exception.
 */
function count(changeDir) {
    const tally = { done: 0, open: 0, partial: 0 }
    for (const file of taskFiles(changeDir)) {
        for (const line of readFileSync(file, 'utf8').split('\n')) {
            if (/^\s*[-*]\s*\[ \]/.test(line)) tally.open += 1
            else if (/^\s*[-*]\s*\[[xX]\]/.test(line)) tally.done += 1
            else if (/^\s*[-*]\s*\[~\]/.test(line)) tally.partial += 1
        }
    }
    return tally
}

function audit(root) {
    const rows = []
    const problems = []
    if (!existsSync(root)) return { rows, problems }
    for (const change of readdirSync(root).sort()) {
        if (change === 'archive') continue
        const dir = join(root, change)
        if (!taskFiles(dir).length) continue
        const tally = count(dir)
        const total = tally.done + tally.open + tally.partial
        if (!total) continue
        rows.push({ change, ...tally, total })
        if (tally.open === 0 && tally.partial > 0) {
            problems.push(
                `${change}: no task is open and ${tally.partial} ${tally.partial === 1 ? 'is' : 'are'} `
                + `partial, so \`openspec-guard\` will announce it as ready to verify and archive. `
                + `It is ${tally.done} of ${total}. Finish the partials, or split each one into a `
                + `ticked task and a new open task that names what is left.`
            )
        }
    }
    return { rows, problems }
}

// ── Self-test ────────────────────────────────────────────────────────────────
if (process.argv.includes('--self-test')) {
    const dir = join(tmpdir(), `partial-tasks-selftest-${process.pid}`)
    const cases = []
    const write = (change, body) => {
        mkdirSync(join(dir, change), { recursive: true })
        writeFileSync(join(dir, change, 'tasks.md'), body)
    }
    const run = (body) => {
        rmSync(dir, { recursive: true, force: true })
        write('c', body)
        return audit(dir)
    }

    let r = run('- [x] one\n- [ ] two\n- [~] three\n')
    cases.push(['open work left is not a problem, whatever the partials', r.problems.length === 0])
    cases.push(['the count is three-way', r.rows[0].done === 1 && r.rows[0].open === 1 && r.rows[0].partial === 1])

    r = run('- [x] one\n- [~] two\n')
    cases.push(['no open task with a partial left IS a problem', r.problems.length === 1])
    cases.push(['the message gives the honest ratio', r.problems[0].includes('1 of 2')])

    r = run('- [x] one\n- [x] two\n')
    cases.push(['a genuinely finished change passes', run('- [x] one\n- [x] two\n').problems.length === 0])

    // The guard's own blind spot, stated as a test so the reason survives.
    r = run('- [x] a\n- [~] b\n- [~] c\n')
    cases.push([
        "the guard would call this 1/1; this calls it 1 of 3",
        r.rows[0].done === 1 && r.rows[0].total === 3 && r.problems.length === 1,
    ])

    // Indentation and `*` bullets, because both appear in this repository.
    r = run('  * [x] indented star\n- [~] plain\n')
    cases.push(['indented and `*` bullets are counted', r.rows[0].done === 1 && r.rows[0].partial === 1])

    // A list that is all prose has nothing to say rather than dividing by zero.
    r = run('Some prose about a change.\n\nMore prose.\n')
    cases.push(['a list with no checkboxes is skipped, not reported', r.rows.length === 0 && r.problems.length === 0])

    rmSync(dir, { recursive: true, force: true })
    let failed = 0
    for (const [name, ok] of cases) {
        console.log(`  ${ok ? 'pass' : 'FAIL'}  ${name}`)
        if (!ok) failed += 1
    }
    console.log(`partial-tasks self-test: ${cases.length - failed}/${cases.length} passed`)
    process.exit(failed ? 1 : 0)
}

// ── Check ────────────────────────────────────────────────────────────────────

const { rows, problems } = audit(CHANGES)

console.log('Task progress, counting partials (which `openspec-guard` does not):')
for (const row of rows) {
    const flag = row.open === 0 && row.partial > 0 ? '  <-- reads as ready' : ''
    console.log(
        `  ${row.change.padEnd(38)} ${String(row.done).padStart(3)} done  `
        + `${String(row.partial).padStart(2)} partial  ${String(row.open).padStart(2)} open  `
        + `of ${row.total}${flag}`
    )
}

if (problems.length) {
    console.error(`\npartial-tasks: ${problems.length} problem(s).\n`)
    for (const problem of problems) console.error(`  ${problem}\n`)
    process.exit(1)
}
console.log('\npartial-tasks: no change reads as ready while carrying a partial.')
