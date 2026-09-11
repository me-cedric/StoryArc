#!/usr/bin/env node
/**
 * Where the two catalogues say different things about the same state.
 *
 * `localization` / One state, one name binds both platforms: "the same state is shown on iOS
 * and on Android, and both state it in the same words, allowing only for a difference the
 * platform itself forces". Nothing measured that. `strings:ios` asks whether an iOS key
 * resolves in four languages and Android's `lint` asks the same of a translation, and neither
 * one has ever compared the two apps to each other.
 *
 * This is a **report, not a gate.** It prints what differs and marks each row, and it is wired
 * into no `pnpm lint` chain, because a row can be deliberate — see the mark below — and a
 * check that fails on a deliberate difference is a check somebody switches off.
 *
 * Keys pair by name with the separators and the format specifiers taken out, so
 * `library.cell.progress %lld` pairs with `library_cell_progress`. Each row is marked:
 *
 *   wording             the two platforms word the state differently. This is the group
 *                       `localization` asks to be reconciled.
 *   punctuation         the same words, a different apostrophe, quotation mark or space.
 *   placeholder syntax  the same words, and iOS's `%@` / `%lld` against Android's
 *                       `%1$s` / `%1$d`. Each platform's own format spelling, and not
 *                       something a reader can see.
 *
 * **Four things it cannot see, stated rather than hidden:**
 *
 * 1. **English only.** It compares the `en` value. A French value that drifted while English
 *    held still is invisible here.
 * 2. **A sentence one platform composes.** iOS draws the list of formats it reads through a
 *    placeholder and Android writes the list into the sentence, so the two values differ as
 *    text while the reader sees the same words. Such a row is reported as *wording* and needs
 *    a person.
 * 3. **A pair that is not named the same.** The publication page states its availability in
 *    two clauses on iOS and four whole sentences on Android, so it pairs on no key and does
 *    not appear at all.
 * 4. **A key only one platform has.** Out of scope: this is about the words two platforms use
 *    for one state, not about what each platform has a key for.
 *
 * Usage:
 *   node scripts/catalogue-divergence.mjs           every row, grouped by mark
 *   node scripts/catalogue-divergence.mjs --count   the four figures only
 */
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

/** Anything that consumes one argument, on either platform. */
const SPECIFIER = /%(?:\d+\$)?(?:@|lld|ld|d|f|lf|s)/g

/** A key with its specifiers and its separators taken out, so the two spellings pair. */
const paired = (key) => key.replace(SPECIFIER, '').replace(/[^a-z0-9]/gi, '').toLowerCase()

const files = (dir, out = []) => {
    for (const entry of readdirSync(dir)) {
        if (entry === '.build' || entry === 'build' || entry === '.git') continue
        const path = join(dir, entry)
        if (statSync(path).isDirectory()) files(path, out)
        else out.push(path)
    }
    return out
}

const shorten = (path) => path.slice(ROOT.length + 1)

/** One row per paired name, holding every key and every distinct value under it. */
const row = (table, name) => {
    if (!table.has(name)) table.set(name, { keys: new Set(), values: new Set(), files: new Set() })
    return table.get(name)
}

/**
 * The English of every iOS key.
 *
 * A plural or a substituted count is flattened to its cases, so the comparison sees the words
 * rather than the machinery. `%#@name@` names a substitution block beside the value, and a
 * reader is shown one of its forms.
 */
const readIos = () => {
    const table = new Map()
    for (const file of files(join(ROOT, 'apps/ios')).filter((p) => p.endsWith('Localizable.xcstrings'))) {
        const catalogue = JSON.parse(readFileSync(file, 'utf8'))
        for (const [key, entry] of Object.entries(catalogue.strings ?? {})) {
            const english = entry.localizations?.en
            const cases = (block) =>
                Object.entries(block ?? {})
                    .map(([category, unit]) => `${category}: ${unit.stringUnit?.value}`)
                    .join(' | ')
            let value = english?.stringUnit?.value ?? key
            if (english?.variations?.plural) value = cases(english.variations.plural)
            for (const [name, block] of Object.entries(english?.substitutions ?? {})) {
                value += `  {${name}: ${cases(block.variations?.plural)}}`
            }
            const held = row(table, paired(key))
            held.keys.add(key)
            held.values.add(value)
            held.files.add(shorten(file))
        }
    }
    return table
}

/** XML and Android's own escapes undone, so a `é` compares equal to an `é`. */
const plain = (value) =>
    value
        .replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
        .replace(/\\'/g, "'")
        .replace(/\\n/g, '\n')
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .trim()

/** The English of every Android string and plural, from the default `values/` of each module. */
const readAndroid = () => {
    const table = new Map()
    for (const file of files(join(ROOT, 'apps/android')).filter((p) => p.endsWith('/values/strings.xml'))) {
        const xml = readFileSync(file, 'utf8')
        const add = (name, value) => {
            const held = row(table, paired(name))
            held.keys.add(name)
            held.values.add(value)
            held.files.add(shorten(file))
        }
        for (const [, name, value] of xml.matchAll(/<string name="([^"]+)"[^>]*>([\s\S]*?)<\/string>/g)) {
            add(name, plain(value))
        }
        for (const [, name, body] of xml.matchAll(/<plurals name="([^"]+)">([\s\S]*?)<\/plurals>/g)) {
            const cases = [...body.matchAll(/<item quantity="(\w+)">([\s\S]*?)<\/item>/g)]
                .map(([, category, value]) => `${category}: ${plain(value)}`)
                .join(' | ')
            add(name, cases)
        }
    }
    return table
}

const joined = (values) => [...values].sort().join(' / ')
const withoutSpecifiers = (value) => value.replace(SPECIFIER, '%')
const withoutTypography = (value) =>
    withoutSpecifiers(value)
        .replace(/[‘’']/g, "'")
        .replace(/[“”„«»"]/g, '"')
        .replace(/\s+/g, ' ')

/** Every paired name whose English differs, with the mark that says what kind of difference. */
export const divergences = () => {
    const ios = readIos()
    const android = readAndroid()
    const rows = []
    let pairs = 0
    for (const [name, left] of ios) {
        const right = android.get(name)
        if (!right) continue
        pairs += 1
        const iosValue = joined(left.values)
        const androidValue = joined(right.values)
        if (iosValue === androidValue) continue
        const mark =
            withoutSpecifiers(iosValue) === withoutSpecifiers(androidValue)
                ? 'placeholder syntax'
                : withoutTypography(iosValue) === withoutTypography(androidValue)
                  ? 'punctuation'
                  : 'wording'
        rows.push({ name, mark, ios: left, android: right, iosValue, androidValue })
    }
    return { iosKeys: ios.size, androidKeys: android.size, pairs, rows }
}

const report = divergences()
console.log(
    `iOS keys ${report.iosKeys} · Android keys ${report.androidKeys} · paired ${report.pairs}` +
        ` · identical English ${report.pairs - report.rows.length} · differ ${report.rows.length}`
)
for (const mark of ['wording', 'punctuation', 'placeholder syntax']) {
    const marked = report.rows.filter((entry) => entry.mark === mark)
    console.log(`\n=== ${mark} — ${marked.length} ===`)
    if (process.argv.includes('--count')) continue
    for (const entry of marked) {
        console.log(`- iOS      ${joined(entry.ios.keys)}  [${joined(entry.ios.files)}]`)
        console.log(`           ${JSON.stringify(entry.iosValue)}`)
        console.log(`  Android  ${joined(entry.android.keys)}  [${joined(entry.android.files)}]`)
        console.log(`           ${JSON.stringify(entry.androidValue)}`)
    }
}
