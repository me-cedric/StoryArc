#!/usr/bin/env node
/**
 * Checks that every string the iOS app asks for is one its catalogue can answer.
 *
 * Android has this for free: a missing `R.string` does not compile, and `lint` fails a
 * translation gap. iOS has neither. A `LocalizedStringKey` that matches nothing is not an
 * error, not a warning, and not a crash — it renders the key. `localization` asks for a
 * build that "fails if any supported language is missing a key that English defines", and
 * until this existed nothing on the iOS side did.
 *
 * It exists because three shipped strings were doing exactly that. The About screen read
 * `about.version 0.1.0 1` on a booted simulator: the call site interpolates plainly, so
 * SwiftUI derived `about.version %@ %@`, while the catalogue stored the entry
 * positionally as `about.version %1$@ %2$@`. Two more in the EPUB reader were broken the
 * same way. None was visible in a test, and only one was visible in a screenshot anyone
 * had taken.
 *
 * Three checks:
 *
 *   POSITIONAL    a catalogue *key* using `%1$@`-style specifiers. SwiftUI never derives
 *                 one, so nothing can ever look it up. Values may — and should, since a
 *                 translation may need to reorder its arguments. Only the key is wrong.
 *   MISSING       a key a Swift source asks for that the catalogue does not define.
 *   UNTRANSLATED  a key the catalogue defines that some supported language has no
 *                 translated value for.
 *
 * Specifiers are normalised away before a key is compared, so `%@` and `%lld` are the
 * same hole. That is deliberate: telling them apart needs Swift's type checker, and a
 * gate that guesses types would report keys that do exist. What survives normalisation is
 * still exact about the two things that matter — whether a key exists at all, and whether
 * it takes the number of arguments the call site passes.
 *
 * Usage:
 *   node scripts/ios-strings.mjs              check every catalogue
 *   node scripts/ios-strings.mjs --self-test  check the checks still fire
 */
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'

/** The four `localization` names. English is the one every other falls back to. */
const LANGUAGES = ['en', 'fr', 'de', 'es']

/** A key written `%1$@` rather than `%@`. Nothing can look it up. */
const POSITIONAL = /%\d+\$/

/**
 * A localised lookup in Swift source.
 *
 * Matches `Text("…"` and `String(localized: "…"`, which is every way this codebase asks
 * for a string. Deliberately not a Swift parser: the key is always a literal that starts
 * the argument, because a `LocalizedStringKey` built any other way cannot be extracted by
 * Xcode either and would be a defect in its own right.
 */
const LOOKUP = /(?:Text\(\s*|String\(\s*localized:\s*)"((?:[^"\\]|\\.)*)"/g

/** Anything that consumes one argument, positional or not, of any type. */
const SPECIFIER = /%(?:\d+\$)?(?:@|lld|ld|d|f|lf)/g

/** A key with its argument types erased, so `%@` and `%lld` compare equal. */
const skeleton = (key) => key.replace(SPECIFIER, '%')

/**
 * The key SwiftUI derives from an interpolated literal, with types already erased.
 *
 * `"about.version \(a) \(b)"` becomes `about.version % %`. Interpolations nest, so the
 * scan counts parentheses rather than stopping at the first `)` — `\(formatted(bytes))`
 * is one hole, not one hole and a stray `)`.
 */
export const derivedSkeleton = (literal) => {
    let key = ''
    for (let i = 0; i < literal.length; i += 1) {
        if (literal[i] === '\\' && literal[i + 1] === '(') {
            let depth = 1
            let j = i + 2
            for (; j < literal.length && depth > 0; j += 1) {
                if (literal[j] === '(') depth += 1
                else if (literal[j] === ')') depth -= 1
            }
            key += '%'
            i = j - 1
            continue
        }
        key += literal[i]
    }
    // A literal may also carry a specifier written out, which `String(localized:)` does
    // when the result is handed to a formatter rather than shown. Same hole either way.
    return skeleton(key)
}

/** Whether one language has a usable value: a plain one, or every plural form. */
const translated = (entry, language) => {
    const localization = entry.localizations?.[language]
    if (!localization) return false
    if (localization.stringUnit) return localization.stringUnit.state === 'translated'
    const plural = localization.variations?.plural
    if (plural) {
        const forms = Object.values(plural)
        return forms.length > 0 && forms.every((f) => f.stringUnit?.state === 'translated')
    }
    const device = localization.variations?.device
    if (device) {
        const forms = Object.values(device)
        return forms.length > 0 && forms.every((f) => f.stringUnit?.state === 'translated')
    }
    return false
}

const walk = (directory, out = []) => {
    for (const entry of readdirSync(directory)) {
        // `.build` holds copies of the very catalogues being checked, and checking a copy
        // reports every problem twice.
        if (entry === '.build' || entry === 'node_modules' || entry === '.git') continue
        const path = join(directory, entry)
        if (statSync(path).isDirectory()) walk(path, out)
        else out.push(path)
    }
    return out
}

/** Every catalogue, paired with the sources that can reach it. */
const modules = (root) => {
    const files = walk(root)
    return files
        .filter((f) => f.endsWith('Localizable.xcstrings'))
        .map((catalogue) => {
            // A catalogue serves its own target: the directory above `Resources`.
            const target = dirname(dirname(catalogue))
            return {
                catalogue,
                sources: files.filter((f) => f.endsWith('.swift') && f.startsWith(target + '/')),
            }
        })
        .filter((m) => m.sources.length > 0)
}

export const check = (root) => {
    const problems = []
    for (const { catalogue, sources } of modules(root)) {
        const where = relative(root, catalogue)
        const strings = JSON.parse(readFileSync(catalogue, 'utf8')).strings ?? {}
        const defined = new Set(Object.keys(strings).map(skeleton))

        for (const [key, entry] of Object.entries(strings)) {
            if (POSITIONAL.test(key)) {
                problems.push(
                    `POSITIONAL  ${where}\n` +
                        `  key "${key}" uses %1$-style specifiers, which SwiftUI never derives, so nothing can look it up.\n` +
                        `  Write the key as "${key.replace(/%(\d+)\$/g, '%')}". The translations may keep their positional form.`,
                )
            }
            const missing = LANGUAGES.filter((l) => !translated(entry, l))
            if (missing.length > 0) {
                problems.push(`UNTRANSLATED  ${where}\n  key "${key}" has no translated value for: ${missing.join(', ')}`)
            }
        }

        for (const source of sources) {
            const seen = new Set()
            for (const [, literal] of readFileSync(source, 'utf8').matchAll(LOOKUP)) {
                // A literal without a dotted head is a sentence typed inline rather than a
                // key. `Text(verbatim:)` never reaches the catalogue and is already excluded
                // by the pattern; this catches the rest.
                if (!/^[a-z][\w]*\./.test(literal)) continue
                const key = derivedSkeleton(literal)
                if (defined.has(key) || seen.has(key)) continue
                seen.add(key)
                problems.push(`MISSING  ${relative(root, source)}\n  asks for "${key}", which ${where} does not define`)
            }
        }
    }
    return problems
}

const selfTest = () => {
    let ok = true
    const fail = (message) => {
        ok = false
        console.error('  ' + message)
    }

    for (const [literal, expected] of [
        ['about.version \\(a) \\(b)', 'about.version % %'],
        ['settings.reset', 'settings.reset'],
        ['downloads.remove.body \\(download.title)', 'downloads.remove.body %'],
        // A nested call inside an interpolation is one hole, not a hole plus a stray ")".
        ['privacy.cache \\(formattedBytes(cacheBytes))', 'privacy.cache %'],
        // A specifier written out reaches the same skeleton as one interpolated.
        ['kavita.addToList %@', 'kavita.addToList %'],
        ['library.cell.pages %lld', 'library.cell.pages %'],
    ]) {
        const got = derivedSkeleton(literal)
        if (got !== expected) fail(`derivedSkeleton(${literal}) = "${got}", expected "${expected}"`)
    }

    if (POSITIONAL.test('about.version %@ %@')) fail('POSITIONAL fires on a derived key')
    if (!POSITIONAL.test('about.version %1$@ %2$@')) fail('POSITIONAL misses a positional key')
    if (skeleton('a %@ %lld') !== skeleton('a %lld %@')) fail('skeleton does not erase argument types')

    const plural = {
        localizations: Object.fromEntries(
            LANGUAGES.map((l) => [
                l,
                { variations: { plural: { one: { stringUnit: { state: 'translated', value: 'x' } }, other: { stringUnit: { state: 'translated', value: 'y' } } } } },
            ]),
        ),
    }
    if (!LANGUAGES.every((l) => translated(plural, l))) fail('a fully translated plural is reported untranslated')
    const halfPlural = JSON.parse(JSON.stringify(plural))
    halfPlural.localizations.de.variations.plural.other.stringUnit.state = 'new'
    if (translated(halfPlural, 'de')) fail('a plural missing one form is reported translated')

    console.log(ok ? 'self-test passed' : 'self-test FAILED')
    process.exitCode = ok ? 0 : 1
}

const argument = process.argv.slice(2).find((a) => !a.startsWith('--'))
const root = argument ?? 'apps/ios'

if (process.argv.includes('--self-test')) {
    selfTest()
} else {
    const problems = check(root)
    for (const problem of problems) console.error(problem)
    console.log(
        problems.length === 0
            ? `iOS strings: every key resolves, in ${LANGUAGES.join(', ')}.`
            : `iOS strings: ${problems.length} problem(s).`,
    )
    process.exitCode = problems.length > 0 ? 1 : 0
}
