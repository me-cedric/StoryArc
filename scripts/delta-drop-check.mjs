#!/usr/bin/env node
/**
 * A MODIFIED delta replaces its requirement's **whole block**, so anything the main spec
 * holds and the delta omits is dropped the moment the change is archived. This finds that
 * before the archive does.
 *
 * **`openspec validate` does not catch it, and that is the whole reason this exists.** It has
 * now happened twice in this repository:
 *
 * 1. `quiet-shell-and-search` carried `## MODIFIED` for *Reaching search* against
 *    `navigation-shell`, a capability with **no main spec at all** — it is created by a
 *    sibling change that had not synced. Validate passed. Only `openspec archive` would have
 *    noticed, at the point where the delta could no longer be applied, and by then the change
 *    directory moves and the requirement goes with it.
 * 2. That same change's `library-browsing` delta added a normative sentence and rewrote
 *    *No results*. A sibling's MODIFIED delta on the same requirement was written before the
 *    sync and kept neither. Archiving the sibling would have quietly reverted both. Its
 *    scenarios had been carried across by hand; its **prose had not**, and nothing looked.
 *
 * So this checks three things, in order of how badly each fails:
 *
 * - A MODIFIED requirement that exists in **no** main spec. Nothing to merge into.
 * - A **scenario** the main spec's requirement has and the delta does not.
 * - A **`SHALL` clause** in the main requirement's prose that the delta's prose does not
 *   carry. This is case 2, and it is the one a human reviewer misses, because scenarios are
 *   listed and prose is read.
 *
 * **A deliberate removal is allowed and must be written down.** Record it in
 * `.delta-drops.json` beside this repo's root, with the reason:
 *
 *     {
 *       "quiet-shell-and-search/navigation-shell": {
 *         "Reaching search": { "scenarios": ["Reaching search on iOS"], "reason": "…" }
 *       }
 *     }
 *
 * An entry that no longer matches anything is itself an error, the way
 * `.openspec-guard.json` treats a stale grandfather — so the file drains rather than
 * accumulating permission slips.
 *
 * Usage:
 *   node scripts/delta-drop-check.mjs              check
 *   node scripts/delta-drop-check.mjs --self-test  prove the check can fail
 */
import { existsSync, readFileSync, readdirSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const SPEC_ROOT = 'docs/openspec'
const ALLOWLIST = '.delta-drops.json'

/**
 * Requirements in one spec file, as `{ name: { scenarios, shalls } }`.
 *
 * `section` limits it to one `##` heading, because a delta file holds ADDED and MODIFIED
 * side by side and only the MODIFIED half replaces anything.
 */
function requirements(text, section = null) {
    const found = {}
    let name = null
    let heading = null
    for (const line of text.split('\n')) {
        if (line.startsWith('## ')) {
            heading = line.slice(3).trim()
            name = null
        } else if (line.startsWith('### Requirement:')) {
            if (section && heading !== section) { name = null; continue }
            name = line.split(':').slice(1).join(':').trim()
            found[name] = { scenarios: [], prose: [], shalls: [] }
        } else if (name) {
            if (line.startsWith('#### Scenario:')) {
                found[name].scenarios.push(line.split(':').slice(1).join(':').trim())
            } else if (isProse(line)) {
                found[name].prose.push(line)
            }
        }
    }
    for (const entry of Object.values(found)) entry.shalls = shallSentences(entry.prose)
    return found
}

/**
 * The `SHALL` sentences in a requirement's prose, as whole sentences rather than lines.
 *
 * **Per-line was wrong and its first self-test passed for the wrong reason.** A requirement's
 * prose is hard-wrapped, and a delta legitimately re-wraps it — so comparing lines reported
 * "the app shall present a single library spanning every source, and shall let the" as a
 * dropped clause against a delta that carried the whole sentence with the break one word
 * later. Seven such false positives, all in deltas that had dropped nothing. Joining first
 * and splitting on sentence ends is the only comparison that survives a re-wrap.
 */
function shallSentences(lines) {
    const joined = lines
        .map((line) => clause(line))
        .filter(Boolean)
        .join(' ')
    // Split after `. ` but not inside `e.g.`, a decimal, or a version — a sentence end is a
    // full stop followed by a space and a capital or a quote.
    return joined
        .split(/(?<=\.)\s+(?=[a-z“"'`])/)
        .flatMap((part) => part.split(/(?<=\.)\s+/))
        .map((s) => s.trim())
        .filter((s) => s.includes('shall'))
}

/**
 * Whether a line inside a requirement is part of its normative prose.
 *
 * Three exclusions, each for its own reason:
 *
 * - **A `- ` bullet** belongs to a scenario, and scenarios are compared by name. Counting
 *   their clauses here would report the same omission twice, in the less useful place.
 * - **A `|` table row.** `publication-formats` → *Supported formats* ends its sentence with
 *   a colon and then a table of every format; joining prose across it produced a single
 *   "clause" 400 characters long that no rewording could ever match. The table is data the
 *   scenarios exercise, not a sentence.
 * - **A `>` blockquote.** A note is commentary on the requirement, not the requirement. This
 *   matters more than it looks: a delta that *removes* a clause usually quotes the old
 *   wording in exactly such a note to explain itself, and counting that as carried would
 *   make the gate pass on the one case it exists to catch.
 */
const isProse = (line) => !line.startsWith('####')
    && !line.trimStart().startsWith('- ')
    && !line.trimStart().startsWith('|')
    && !line.trimStart().startsWith('>')

/**
 * A prose line reduced to something two wordings of the same clause compare equal on.
 *
 * Deltas legitimately re-wrap and re-punctuate. What must survive a rewrite is the
 * obligation, so this keeps the words and throws away the typography.
 */
function clause(line) {
    return line
        .replace(/[*`_~]/g, '')
        .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/[—–]/g, '-')
        .replace(/\s+/g, ' ')
        .trim()
        .toLowerCase()
}

/**
 * The delta's prose as one normalised blob, for asking whether a main clause survives in it.
 *
 * **Set membership was wrong too, and for a subtler reason than the re-wrap.** A MODIFIED
 * delta very often *extends* an existing sentence rather than replacing it — `library-browsing`
 * → *Search* keeps the main spec's sentence word for word and appends "and SHALL group results
 * by what the match is rather than by which source answered". Exact-sentence matching called
 * that a drop. Containment does not, and it still catches a sentence that is gone.
 */
const proseBlob = (entry) => entry.prose.map(clause).filter(Boolean).join(' ')

/** Words that carry no obligation, so a rewording is free to change them. */
const STOPWORDS = new Set([
    'a', 'an', 'and', 'any', 'are', 'as', 'at', 'be', 'been', 'by', 'each', 'every', 'for',
    'from', 'in', 'is', 'it', 'its', 'of', 'on', 'or', 'own', 'shall', 'so', 'than', 'that',
    'the', 'their', 'them', 'there', 'they', 'this', 'to', 'was', 'what', 'when', 'where',
    'which', 'while', 'with', 'user', 'reader', 'app',
])

const contentWords = (sentence) =>
    sentence.split(/[^a-z0-9]+/).filter((w) => w.length > 1 && !STOPWORDS.has(w))

/**
 * How much of a main-spec clause has to survive in the delta's prose before it counts.
 *
 * **Tuned to catch absence, not rewording, and that is deliberate.** Both failures this gate
 * exists for were a clause that was simply *not there* — nobody had reworded anything. A
 * rewording is visible to anyone reading the delta; a clause that silently vanished is not.
 * So the threshold sits where a rewording passes and a removal cannot:
 *
 * - `SHALL give the user control` → `SHALL give the reader control … presented inside the
 *   on-device destination`: every content word survives. Passes, and should.
 * - `and SHALL adapt density` → `, SHALL adapt density`: `and` is a stopword. Passes.
 * - `SHALL filter by read state, download state, format, source, …` reworded so that source
 *   becomes "the library a publication came from": 13 of 15 content words survive. Passes,
 *   and the rewording is right there in the delta for a reviewer to see.
 * - The sentence `Search SHALL say what it is about to search, and SHALL let a reader narrow
 *   it to what can be read with no network`, absent from a sibling delta — the real
 *   `library-browsing` failure: **one** content word in common. Fails, which is the point.
 *
 * A tighter threshold would fill `.delta-drops.json` with permission slips for comma changes,
 * and a file nobody can read is a file nobody reviews.
 */
const SURVIVAL = 0.6

/**
 * Whether a main-spec clause survives in the delta's prose.
 *
 * Containment first, because an *extended* sentence — the commonest legitimate modification —
 * keeps the original word for word and appends to it. The trailing full stop goes so the
 * delta's version can continue where the main one stopped. Failing that, content-word
 * overlap, so a rewording is not reported as a removal.
 */
function survives(blob, sentence) {
    const bare = sentence.replace(/\.$/, '')
    if (blob.includes(bare)) return true
    const words = contentWords(bare)
    if (!words.length) return true
    const present = new Set(contentWords(blob))
    const kept = words.filter((w) => present.has(w)).length
    return kept / words.length >= SURVIVAL
}

const problems = []
const usedAllowances = new Set()

function audit(root, allowlist) {
    const changesDir = join(root, 'changes')
    if (!existsSync(changesDir)) return
    for (const change of readdirSync(changesDir)) {
        if (change === 'archive') continue
        const specsDir = join(changesDir, change, 'specs')
        if (!existsSync(specsDir)) continue
        for (const capability of readdirSync(specsDir)) {
            const delta = join(specsDir, capability, 'spec.md')
            if (!existsSync(delta)) continue
            const text = readFileSync(delta, 'utf8')
            if (!text.includes('## MODIFIED Requirements')) continue

            const main = join(root, 'specs', capability, 'spec.md')
            const where = `${change}/${capability}`
            const allowed = allowlist[where] ?? {}

            if (!existsSync(main)) {
                problems.push(
                    `${where}: a MODIFIED delta against a capability with no main spec. `
                    + 'There is nothing to merge into, so archiving carries the requirement '
                    + 'off instead of publishing it. Move it to the change that ADDs the '
                    + 'capability, or make this change ADD it.'
                )
                continue
            }

            const deltaReqs = requirements(text, 'MODIFIED Requirements')
            const mainReqs = requirements(readFileSync(main, 'utf8'))

            for (const [name, entry] of Object.entries(deltaReqs)) {
                const target = mainReqs[name]
                const allowance = allowed[name] ?? {}
                if (allowance.reason) usedAllowances.add(`${where}::${name}`)
                if (!target) {
                    problems.push(
                        `${where}: MODIFIED "${name}", which the main spec does not have. `
                        + `It holds: ${Object.keys(mainReqs).join(', ') || '(nothing)'}.`
                    )
                    continue
                }
                const okScenarios = new Set(allowance.scenarios ?? [])
                const droppedScenarios = target.scenarios
                    .filter((s) => !entry.scenarios.includes(s) && !okScenarios.has(s))
                if (droppedScenarios.length) {
                    problems.push(
                        `${where} → "${name}" would drop ${droppedScenarios.length} scenario(s) `
                        + `on archive: ${droppedScenarios.map((s) => `"${s}"`).join(', ')}. `
                        + 'A MODIFIED requirement replaces the whole block.'
                    )
                }
                const okClauses = new Set((allowance.shalls ?? []).map(clause))
                const blob = proseBlob(entry)
                const droppedClauses = target.shalls
                    .filter((s) => !survives(blob, s) && !okClauses.has(clause(s)))
                if (droppedClauses.length) {
                    problems.push(
                        `${where} → "${name}" would drop ${droppedClauses.length} normative `
                        + `clause(s) on archive:\n      ${droppedClauses.join('\n      ')}\n`
                        + '      Carry the sentence, or record the removal in '
                        + `${ALLOWLIST} with its reason.`
                    )
                }
            }
        }
    }
}

// ── Self-test ────────────────────────────────────────────────────────────────
//
// Six cases, each a mutation of a tree that passes. A check that cannot fail is not a
// check, and this repository has shipped two of those.
if (process.argv.includes('--self-test')) {
    const dir = join(tmpdir(), `delta-drop-selftest-${process.pid}`)
    const cases = []
    const write = (path, body) => {
        mkdirSync(join(dir, path, '..'), { recursive: true })
        writeFileSync(join(dir, path), body)
    }
    const MAIN = [
        '### Requirement: Thing',
        '',
        'The app SHALL do the thing.',
        '',
        'It SHALL also say what it did.',
        '',
        '#### Scenario: It works',
        '- **WHEN** asked',
        '- **THEN** it does',
        '',
        '#### Scenario: It cannot',
        '- **WHEN** unable',
        '- **THEN** it says so',
        '',
    ].join('\n')
    const complete = [
        '## MODIFIED Requirements',
        '',
        '### Requirement: Thing',
        '',
        'The app SHALL do the thing.',
        '',
        'It SHALL also say what it did.',
        '',
        '#### Scenario: It works',
        '- **WHEN** asked',
        '- **THEN** it does',
        '',
        '#### Scenario: It cannot',
        '- **WHEN** unable',
        '- **THEN** it says so',
        '',
    ].join('\n')

    const run = (deltaBody, allowlist = {}) => {
        rmSync(dir, { recursive: true, force: true })
        write('openspec/specs/thing/spec.md', MAIN)
        write('openspec/changes/c/specs/thing/spec.md', deltaBody)
        problems.length = 0
        usedAllowances.clear()
        audit(join(dir, 'openspec'), allowlist)
        return problems.slice()
    }

    cases.push(['a complete MODIFIED block passes', run(complete).length === 0])
    cases.push([
        'a dropped scenario fails',
        run(complete.replace('#### Scenario: It cannot\n- **WHEN** unable\n- **THEN** it says so\n', ''))
            .some((p) => p.includes('would drop 1 scenario') && p.includes('It cannot')),
    ])
    cases.push([
        'a dropped normative clause fails, even with every scenario present',
        run(complete.replace('It SHALL also say what it did.\n\n', ''))
            .some((p) => p.includes('normative clause')),
    ])
    // Two separate cases, and deliberately not joined by `||`. They were, and the re-wrap
    // half was failing while the whitespace half carried the assertion — which is how seven
    // false positives reached a real run.
    cases.push([
        're-wrapped prose still counts as carried',
        run(complete.replace('It SHALL also say what it did.', 'It SHALL\nalso say what\nit did.')).length === 0,
    ])
    cases.push([
        're-punctuated prose still counts as carried',
        run(complete.replace('It SHALL also say what it did.', 'It  **SHALL**  also say what it did.')).length === 0,
    ])
    cases.push([
        'a delta that EXTENDS a main sentence has not dropped it',
        run(complete.replace(
            'The app SHALL do the thing.',
            'The app SHALL do the thing, and SHALL say how long it took.',
        )).length === 0,
    ])
    cases.push([
        'a clause dropped from a multi-sentence paragraph still fails after the re-wrap fix',
        run(complete.replace('The app SHALL do the thing.\n\nIt SHALL also say what it did.', 'The app SHALL do the thing.'))
            .some((p) => p.includes('normative clause') && p.includes('say what it did')),
    ])
    cases.push([
        'a clause quoted only in an explanatory note does NOT count as carried',
        run(complete.replace(
            'It SHALL also say what it did.',
            '> It used to say: "It SHALL also say what it did." That is withdrawn.',
        )).some((p) => p.includes('normative clause')),
    ])
    cases.push([
        'a table inside a requirement is not swallowed into its sentence',
        (() => {
            rmSync(dir, { recursive: true, force: true })
            const tabled = (body) => body.replace(
                'The app SHALL do the thing.',
                'The app SHALL do the thing:\n\n| a | b |\n| --- | --- |\n| one | two |',
            )
            write('openspec/specs/thing/spec.md', tabled(MAIN))
            write('openspec/changes/c/specs/thing/spec.md', tabled(complete).replace('| one | two |', '| one | two |\n| three | four |'))
            problems.length = 0
            usedAllowances.clear()
            audit(join(dir, 'openspec'), {})
            return problems.length === 0
        })(),
    ])
    cases.push([
        'a reworded clause is not reported as a removal',
        run(complete.replace(
            'It SHALL also say what it did.',
            'It SHALL also report, afterwards, exactly what it did and to which thing.',
        )).length === 0,
    ])
    cases.push([
        'a clause replaced by an unrelated one IS reported',
        run(complete.replace(
            'It SHALL also say what it did.',
            'It SHALL instead remain entirely silent about every outcome.',
        )).some((p) => p.includes('normative clause')),
    ])
    cases.push([
        'the real library-browsing shape fails: a sentence absent from a sibling delta',
        (() => {
            rmSync(dir, { recursive: true, force: true })
            write('openspec/specs/thing/spec.md', [
                '### Requirement: Thing',
                '',
                'The app SHALL provide search across titles, series and authors.',
                '',
                'Search SHALL say what it is about to search, and SHALL let a reader narrow it',
                'to what can be read with no network.',
                '',
                '#### Scenario: It works',
                '- **WHEN** asked',
                '- **THEN** it does',
                '',
            ].join('\n'))
            write('openspec/changes/c/specs/thing/spec.md', [
                '## MODIFIED Requirements',
                '',
                '### Requirement: Thing',
                '',
                'The app SHALL provide search across titles, series and authors, and SHALL group',
                'results by what the match is rather than by which source answered.',
                '',
                '#### Scenario: It works',
                '- **WHEN** asked',
                '- **THEN** it does',
                '',
            ].join('\n'))
            problems.length = 0
            usedAllowances.clear()
            audit(join(dir, 'openspec'), {})
            return problems.some((p) => p.includes('normative clause') && p.includes('no network'))
        })(),
    ])
    cases.push([
        'an allowlisted removal passes',
        run(
            complete.replace('#### Scenario: It cannot\n- **WHEN** unable\n- **THEN** it says so\n', ''),
            { 'c/thing': { Thing: { scenarios: ['It cannot'], reason: 'deliberate' } } },
        ).length === 0,
    ])
    cases.push([
        'a MODIFIED requirement the main spec does not have fails',
        run(complete.replace('### Requirement: Thing', '### Requirement: Other'))
            .some((p) => p.includes('which the main spec does not have')),
    ])
    cases.push([
        'a MODIFIED delta against a capability with no main spec fails',
        (() => {
            rmSync(dir, { recursive: true, force: true })
            write('openspec/changes/c/specs/nowhere/spec.md', complete)
            problems.length = 0
            audit(join(dir, 'openspec'), {})
            return problems.some((p) => p.includes('no main spec'))
        })(),
    ])

    rmSync(dir, { recursive: true, force: true })
    let failed = 0
    for (const [name, ok] of cases) {
        console.log(`  ${ok ? 'pass' : 'FAIL'}  ${name}`)
        if (!ok) failed += 1
    }
    console.log(`delta-drop self-test: ${cases.length - failed}/${cases.length} passed`)
    process.exit(failed ? 1 : 0)
}

// ── Check ────────────────────────────────────────────────────────────────────

const allowlist = existsSync(ALLOWLIST) ? JSON.parse(readFileSync(ALLOWLIST, 'utf8')) : {}
audit(SPEC_ROOT, allowlist)

for (const [where, byRequirement] of Object.entries(allowlist)) {
    for (const [name, entry] of Object.entries(byRequirement)) {
        if (!entry.reason) {
            problems.push(`${ALLOWLIST}: ${where} → "${name}" has no reason. An allowance without one is a permission slip nobody can review.`)
        } else if (!usedAllowances.has(`${where}::${name}`)) {
            problems.push(`${ALLOWLIST}: ${where} → "${name}" no longer matches a MODIFIED delta. Delete the entry, so the file drains.`)
        }
    }
}

if (problems.length) {
    console.error(`delta-drop: ${problems.length} problem(s).\n`)
    for (const problem of problems) console.error(`  ${problem}\n`)
    console.error('A MODIFIED delta replaces its requirement\'s whole block. `openspec validate` does not check this.')
    process.exit(1)
}
console.log('delta-drop: no MODIFIED delta would drop a scenario or a normative clause on archive.')
