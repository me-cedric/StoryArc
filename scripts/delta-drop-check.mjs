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
            found[name] = { scenarios: [], bullets: {}, prose: [], shalls: [] }
        } else if (name) {
            if (line.startsWith('#### Scenario:')) {
                const title = line.split(':').slice(1).join(':').trim()
                found[name].scenarios.push(title)
                found[name].bullets[title] = []
            } else if (OBLIGATION.test(line)) {
                // Belongs to the scenario most recently opened. A bullet before any scenario
                // heading has no scenario to be compared within, and there are none in this
                // repository.
                const current = found[name].scenarios.at(-1)
                if (current) {
                    found[name].bullets[current].push(clause(line.replace(OBLIGATION, '')))
                }
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
/**
 * A bullet that promises something, as opposed to one that says when.
 *
 * `shallSentences` already ends with `.filter((s) => s.includes('shall'))` — this file has
 * always compared only text that carries an *obligation*, never every sentence. Bullets do not
 * say SHALL; Gherkin's `THEN` and `AND` are the bullet-level marker for the same thing, and a
 * `WHEN` states the circumstance a requirement applies under. Re-framing a circumstance is what
 * a MODIFIED delta is *for*, and nothing is promised to a reader by a WHEN.
 *
 * Measured before it was chosen: comparing **every** bullet flags eleven rows across the
 * corpus, and five are pure noise — every one of them a trigger renamed while the obligation
 * beneath it was carried intact, three scoring at or below 0.50 on three or four content words,
 * where no threshold separates them from a real drop. Filtering by role takes that to zero.
 */
const OBLIGATION = /^-\s*\*\*(THEN|AND)\*\*\s*/

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
const usedCollisions = new Set()

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
                // **The bullets inside a scenario the delta *does* carry.**
                //
                // A MODIFIED block replaces the whole requirement, so a bullet the delta leaves
                // out is deleted on merge exactly as a whole scenario is — and the name check
                // above cannot see it, because the name matched. That is not hypothetical: on
                // 2026-09-05 `native-experience`'s *Tablet and large screens* lost "with the
                // content area showing the continue row and the cover grid", unnoted and
                // unreplaced, and this gate passed.
                //
                // Scenario-scoped rather than requirement-scoped: a bullet whose words survive
                // in a *different* scenario has still been moved out of the one that promised
                // it. A scenario the delta drops entirely is skipped here, because the check
                // above already reports it and reporting it twice is what `isProse`'s own
                // comment warns against.
                for (const title of target.scenarios) {
                    if (!entry.scenarios.includes(title) || okScenarios.has(title)) continue
                    const okBullets = new Set((allowance.bullets?.[title] ?? []).map(clause))
                    const carried = (entry.bullets[title] ?? []).join(' ')
                    const dropped = (target.bullets[title] ?? [])
                        .filter((b) => !survives(carried, b) && !okBullets.has(b))
                    if (!dropped.length) continue
                    problems.push(
                        `${where} → "${name}" / "${title}" would drop ${dropped.length} `
                        + `bullet(s) on archive:\n      ${dropped.join('\n      ')}\n`
                        + '      A MODIFIED requirement replaces the whole block. Carry the '
                        + `bullet, or record the removal in ${ALLOWLIST} with its reason.`
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

/**
 * Two active changes MODIFYing the *same* requirement, with different blocks.
 *
 * **This is case 2 of the docstring above, and the original check could not see it.** That
 * case was a sibling's MODIFIED delta on a requirement this change had also modified, keeping
 * neither of its additions — and everything `audit()` compares is a delta against the **main
 * spec**. Two deltas are each perfectly clean against main and lethal to each other: whichever
 * syncs second replaces the whole block and takes the first's scenarios with it. Nothing looks,
 * because by then the first change's delta has been archived and its additions live only in the
 * main spec the second one is about to overwrite.
 *
 * The gate was written from that incident and left the hazard open. When this check was first
 * run it found **four** live instances, one of them on a requirement about to be synced.
 *
 * **Identical blocks are fine and are not reported.** Two changes that carry the same block
 * are two changes that agree; order cannot matter. It is a difference in either direction that
 * is a hazard — a superset is safe only if it syncs last, and no tool can know the order, so
 * any difference is reported with the scenarios each side holds alone. That list is the merge
 * instruction: put the union in whichever delta syncs first.
 *
 * Prose is compared too, and by the same ``survives`` rule as the main-spec check, so a
 * re-wrap is not a difference and a vanished sentence is.
 */
function collisions(root, recorded = {}) {
    const changesDir = join(root, 'changes')
    if (!existsSync(changesDir)) return
    const held = new Map()
    for (const change of readdirSync(changesDir).sort()) {
        if (change === 'archive') continue
        const specsDir = join(changesDir, change, 'specs')
        if (!existsSync(specsDir)) continue
        for (const capability of readdirSync(specsDir)) {
            const delta = join(specsDir, capability, 'spec.md')
            if (!existsSync(delta)) continue
            const reqs = requirements(readFileSync(delta, 'utf8'), 'MODIFIED Requirements')
            for (const [name, entry] of Object.entries(reqs)) {
                const key = `${capability} → "${name}"`
                if (!held.has(key)) held.set(key, [])
                held.get(key).push({ change, entry })
            }
        }
    }

    for (const [key, holders] of held) {
        if (holders.length < 2) continue
        for (let i = 0; i < holders.length; i += 1) {
            for (let j = i + 1; j < holders.length; j += 1) {
                const [a, b] = [holders[i], holders[j]]
                const onlyA = a.entry.scenarios.filter((s) => !b.entry.scenarios.includes(s))
                const onlyB = b.entry.scenarios.filter((s) => !a.entry.scenarios.includes(s))
                const blobA = proseBlob(a.entry)
                const blobB = proseBlob(b.entry)
                const clauseOnlyA = a.entry.shalls.filter((s) => !survives(blobB, s))
                const clauseOnlyB = b.entry.shalls.filter((s) => !survives(blobA, s))
                if (!onlyA.length && !onlyB.length && !clauseOnlyA.length && !clauseOnlyB.length) {
                    continue
                }

                // **A recorded order can save a nested pair, and nothing saves a disjoint
                // one.** If the block that syncs first holds nothing the later one lacks, the
                // later block is a superset and replacing with it loses nothing — so the pair
                // is safe *in that order only*, which is why the order has to be written down
                // rather than inferred. When each side holds something the other does not, no
                // order helps: one of them is always overwritten, and the entry is refused so
                // it cannot be used to wave the hazard through.
                const order = recorded[key]
                if (order?.order) {
                    usedCollisions.add(key)
                    const [first, second] = order.order
                    const firstHolds = first === a.change
                        ? { scenarios: onlyA, clauses: clauseOnlyA }
                        : { scenarios: onlyB, clauses: clauseOnlyB }
                    if (![first, second].every((c) => c === a.change || c === b.change)) {
                        problems.push(
                            `${ALLOWLIST}: collision "${key}" records an order `
                            + `[${order.order.join(', ')}] that does not name this pair `
                            + `(${a.change}, ${b.change}).`
                        )
                        continue
                    }
                    if (!firstHolds.scenarios.length && !firstHolds.clauses.length) continue
                    problems.push(
                        `${key}: the recorded order puts ${first} first, but ${first}'s block `
                        + 'holds something the later one lacks, so no order saves this pair — '
                        + 'the blocks are disjoint rather than nested. Merge them instead.'
                    )
                    continue
                }
                const side = (change, scenarios, clauses) => {
                    const parts = []
                    if (scenarios.length) parts.push(`scenario(s) ${scenarios.map((s) => `"${s}"`).join(', ')}`)
                    if (clauses.length) parts.push(`clause(s) ${clauses.map((s) => `"${s}"`).join(', ')}`)
                    return parts.length ? `        ${change} alone holds ${parts.join('; ')}` : ''
                }
                problems.push(
                    `${key} is MODIFIED by two active changes with different blocks: `
                    + `${a.change} and ${b.change}.\n`
                    + [side(a.change, onlyA, clauseOnlyA), side(b.change, onlyB, clauseOnlyB)]
                        .filter(Boolean).join('\n')
                    + '\n      Whichever syncs second replaces the whole block and drops the '
                    + "other's. Put the union in the one that syncs first."
                )
            }
        }
    }
}

// ── Self-test ────────────────────────────────────────────────────────────────
//
// Each case is a mutation of a tree that passes. A check that cannot fail is not a check,
// and this repository has shipped two of those. The last four cover the collision half,
// which was added on 2026-09-04 and found four live instances on its first run.
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
        '#### Scenario: It reports',
        '- **WHEN** it has finished',
        '- **THEN** it names what it did',
        '- **AND** it says how long the work took, in whole seconds',
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
        '#### Scenario: It reports',
        '- **WHEN** it has finished',
        '- **THEN** it names what it did',
        '- **AND** it says how long the work took, in whole seconds',
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
    // **The bullets inside a scenario the delta keeps.** The name matches, so every check
    // above passes, and the clause is deleted on merge regardless — which is exactly how
    // `native-experience` lost "with the content area showing the continue row and the cover
    // grid" on 2026-09-05 with this gate green.
    const withoutTheAnd = complete.replace(
        '- **AND** it says how long the work took, in whole seconds\n',
        ''
    )
    cases.push([
        'a bullet dropped from a scenario the delta keeps fails',
        run(withoutTheAnd).some(
            (p) => p.includes('would drop 1 bullet') && p.includes('how long the work took')
        ),
    ])
    // The other half, and the one that decides whether anyone leaves the gate switched on: a
    // reworded obligation is not a removal. Same promise, different words, above SURVIVAL.
    cases.push([
        'a reworded bullet passes',
        run(
            complete.replace(
                'it says how long the work took, in whole seconds',
                'it says how long the work took, counted in whole seconds'
            )
        ).length === 0,
    ])
    // The role filter. A `WHEN` states the circumstance a requirement applies under, and
    // re-framing one is what a MODIFIED delta is for — five of the eleven rows a naive
    // every-bullet comparison flagged on the real corpus were triggers renamed while the
    // obligation beneath was carried word for word.
    cases.push([
        'a rewritten WHEN passes while its obligations are carried',
        run(complete.replace('- **WHEN** it has finished', '- **WHEN** the work is over')).length === 0,
    ])
    // An obligation demoted to a trigger has not survived. Without this the blob would rescue
    // it, and a promise would quietly become a precondition.
    cases.push([
        'an obligation that survives only inside a WHEN still fails',
        run(
            withoutTheAnd.replace(
                '- **WHEN** it has finished',
                '- **WHEN** it has finished and says how long the work took, in whole seconds'
            )
        ).some((p) => p.includes('would drop 1 bullet')),
    ])
    cases.push([
        'a recorded bullet removal passes',
        run(withoutTheAnd, {
            'c/thing': {
                Thing: {
                    bullets: { 'It reports': ['it says how long the work took, in whole seconds'] },
                    reason: 'deliberate',
                },
            },
        }).length === 0,
    ])
    // Reported once, in the more useful place. A scenario the delta drops entirely is already
    // named by the scenario check; adding its bullets would be the double-report `isProse`'s
    // own comment warns against.
    cases.push([
        'a scenario dropped whole is reported as a scenario and not again as bullets',
        (() => {
            const found = run(
                complete.replace(
                    '#### Scenario: It reports\n- **WHEN** it has finished\n'
                        + '- **THEN** it names what it did\n'
                        + '- **AND** it says how long the work took, in whole seconds\n',
                    ''
                )
            )
            return found.some((p) => p.includes('would drop 1 scenario'))
                && !found.some((p) => p.includes('bullet(s)'))
        })(),
    ])
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

    // ── The collision half ───────────────────────────────────────────────────
    //
    // Two changes, one requirement. `runPair` writes both deltas and asks only the collision
    // check, so a failure here cannot be an artefact of the main-spec comparison.
    const runPair = (bodyA, bodyB, recorded = {}) => {
        rmSync(dir, { recursive: true, force: true })
        write('openspec/specs/thing/spec.md', MAIN)
        write('openspec/changes/one/specs/thing/spec.md', bodyA)
        write('openspec/changes/two/specs/thing/spec.md', bodyB)
        problems.length = 0
        usedCollisions.clear()
        collisions(join(dir, 'openspec'), recorded)
        return problems.slice()
    }
    const KEY = 'thing → "Thing"'
    const withScenario = complete.replace(
        '#### Scenario: It works',
        '#### Scenario: Only mine\n- **WHEN** x\n- **THEN** y\n\n#### Scenario: It works',
    )
    cases.push([
        'two changes modifying one requirement identically pass',
        runPair(complete, complete).length === 0,
    ])
    cases.push([
        'a scenario only one side holds fails, and names it',
        (() => {
            const found = runPair(complete, withScenario)
            return found.length === 1
                && found[0].includes('"Only mine"')
                && found[0].includes('two alone holds')
        })(),
    ])
    cases.push([
        'a re-wrap of the same prose is not a difference',
        runPair(complete, complete.replace('The app SHALL do\nthe thing.', 'The app\nSHALL do the thing.')).length === 0,
    ])
    cases.push([
        'a nested pair passes with the subset recorded first',
        runPair(complete, withScenario, {
            [KEY]: { order: ['one', 'two'], reason: 'test' },
        }).length === 0,
    ])
    cases.push([
        'the same nested pair fails with the superset recorded first',
        runPair(withScenario, complete, {
            [KEY]: { order: ['one', 'two'], reason: 'test' },
        }).some((problem) => problem.includes('no order saves this pair')),
    ])
    cases.push([
        'an order naming a change that is not in the pair fails',
        runPair(complete, withScenario, {
            [KEY]: { order: ['one', 'elsewhere'], reason: 'test' },
        }).some((problem) => problem.includes('does not name this pair')),
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
// `collisions` is a reserved top-level key rather than a `change/capability`, so the drain
// loop below has to skip it or it reports every recorded order as a malformed allowance.
const { collisions: recordedCollisions = {}, ...perChange } = allowlist
audit(SPEC_ROOT, perChange)
collisions(SPEC_ROOT, recordedCollisions)

for (const [key, entry] of Object.entries(recordedCollisions)) {
    if (!entry.reason) {
        problems.push(`${ALLOWLIST}: collision "${key}" has no reason. An allowance without one is a permission slip nobody can review.`)
    } else if (!Array.isArray(entry.order) || entry.order.length !== 2) {
        problems.push(`${ALLOWLIST}: collision "${key}" needs an \`order\` naming the two changes, earliest first.`)
    } else if (!usedCollisions.has(key)) {
        problems.push(`${ALLOWLIST}: collision "${key}" no longer matches two active MODIFIED deltas. Delete the entry, so the file drains.`)
    }
}

for (const [where, byRequirement] of Object.entries(perChange)) {
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
console.log('delta-drop: no MODIFIED delta would drop a scenario or a normative clause on archive, and no two active changes modify one requirement differently.')
