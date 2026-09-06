#!/usr/bin/env node
/**
 * A sentence a reader can be shown, written in a source file instead of a catalogue.
 *
 * `strings:ios` checks that every **key** resolves in four languages. A sentence that never
 * became a key has no key to be missing, so nothing looks at it. That is how thirty English
 * sentences reached a French reader. This looks at the small surface where a literal is drawn
 * straight onto the screen.
 *
 * **What it would have caught, plainly: two of those thirty.** The census taken for
 * `one-vocabulary-in-four-languages` said zero, and the census was wrong on this file. The
 * check reports the refused-file alert's title and its OK button, at
 * `apps/ios/App/RefusedFile.swift:55` and `:58` — two of the six literals that file holds.
 * It is the only automated check that sees them, because both are `Text(verbatim:)`: they
 * never become a key, so `strings:ios` has no key to miss. The other twenty-eight reach a view
 * through a variable from the format layer, and the type change in that change's section 1 is
 * the gate for those. This is a backstop against the next leak, on the surface
 * `RefusedFile.swift` leaked through, and claiming more for it would be the vacuous shape
 * AGENTS.md section 5 catalogues.
 *
 * **The five positions.** `Text(`, `alert(`, a `Button(` label, `accessibilityLabel` and
 * `contentDescription =`. SwiftUI and Compose spell `Text(` the same way, so one pattern set
 * reads both languages. There is no parser and no dependency: `scripts/` checks are plain Node
 * and regular expressions, which is the rung this stops at.
 *
 * **A literal is reported when it reads as a sentence.** Interpolations and format specifiers
 * are removed first, one level of nested parentheses deep. What is left must contain a letter,
 * so a separator (`" · "`), a counter (`"\(index + 1)"`) and an empty string are not
 * sentences. In Swift only, a literal that starts with a dotted lowercase word is a catalogue
 * key rather than prose, and `strings:ios` checks that those resolve. Kotlin gets no such
 * exemption, because Compose reads a catalogue through `stringResource`, never a literal.
 *
 * **What a regex over source cannot see. Named, not hidden:**
 *
 *   - A sentence that reaches a view through a variable. This is the main limit, and it is the
 *     shape twenty-eight of the thirty had.
 *   - A literal that anything except whitespace separates from the call. The call may wrap
 *     onto a later line; it may not pass through a helper or a modifier.
 *   - Any position outside the five above, including a label a helper function builds.
 *   - A comment, but only a line that starts as one. A commented-out `Text("…")` on its own
 *     line is not reported. A comment after a drawing call, on the same line, is read.
 *   - Test sources. `Tests/`, `UITests/`, `src/test/` and `src/androidTest/` assert on drawn
 *     strings and build fixtures; they are not a drawing surface.
 *   - A Swift sentence that begins with a dotted lowercase word, which the key exemption
 *     swallows.
 *
 * Usage:
 *   node scripts/drawn-strings-check.mjs              check
 *   node scripts/drawn-strings-check.mjs --self-test  prove the check can fail
 */
import { existsSync, readFileSync, readdirSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { tmpdir } from 'node:os'

const ROOT = 'apps'

/** Build output and dependency trees hold copies, and a copy reports every problem twice. */
const SKIP = new Set(['.build', '.git', '.gradle', 'build', 'node_modules', 'DerivedData'])

/** A source that draws for a reader, as opposed to one that asserts about drawing. */
const isTestPath = (path) =>
    /(?:^|\/)(?:Tests|UITests|androidTest|test)(?:\/|$)/.test(path) || /Tests?\.(?:swift|kt)$/.test(path)

/**
 * The five drawing positions, each paired with the name the report uses.
 *
 * `Text(` covers SwiftUI's `Text("…")`, its `Text(verbatim: "…")` — which is the only form
 * `strings:ios` cannot see, because it never becomes a key — and Compose's `Text("…")`.
 * `alert(` and `accessibilityLabel` accept a nested `Text(` because SwiftUI takes both.
 */
const POSITIONS = [
    ['Text(', /\bText\(\s*(?:verbatim:\s*)?"((?:[^"\\]|\\.)*)"/g],
    ['alert(', /\balert\(\s*(?:Text\(\s*(?:verbatim:\s*)?)?"((?:[^"\\]|\\.)*)"/g],
    ['Button(', /\bButton\(\s*(?:verbatim:\s*)?"((?:[^"\\]|\\.)*)"/g],
    ['accessibilityLabel', /\baccessibilityLabel\(\s*(?:Text\(\s*(?:verbatim:\s*)?)?"((?:[^"\\]|\\.)*)"/g],
    ['contentDescription', /\bcontentDescription\s*=\s*"((?:[^"\\]|\\.)*)"/g],
]

/**
 * Swift `\(…)`, Kotlin `${…}` and `$name`. What a value puts in is not what an author wrote.
 * The Swift form allows one nested pair of parentheses, because `\(duration.formatted())` is
 * ordinary; a deeper nest is left in place and reads as a sentence.
 */
const INTERPOLATION = /\\\((?:[^()]|\([^()]*\))*\)|\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*/g

/** `%@`, `%1$@`, `%lld`, `%1$d`: an argument, not a word. */
const SPECIFIER = /%(?:\d+\$)?[@a-zA-Z]+/g

/** A catalogue key: a dotted lowercase word at the start, as `library.skipped %lld` is. */
const KEY_PREFIX = /^[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_]+)+/

/** A line that is only a comment draws nothing. */
const isComment = (line) => /^\s*(?:\/\/|\/\*|\*)/.test(line)

const isSentence = (literal, swift) => {
    if (swift && KEY_PREFIX.test(literal.trim())) return false
    const bare = literal.replace(INTERPOLATION, '').replace(SPECIFIER, '')
    return /\p{L}/u.test(bare)
}

const walk = (directory, out = []) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
        if (SKIP.has(entry.name)) continue
        const path = join(directory, entry.name)
        if (entry.isDirectory()) walk(path, out)
        else if (path.endsWith('.swift') || path.endsWith('.kt')) out.push(path)
    }
    return out
}

/**
 * Every drawn sentence under `root`, with the file and line that holds it.
 *
 * The scan reads a whole file at once, not a line at a time, because a drawing call that ends
 * its line at the open parenthesis is the shape SwiftLint's 120-column rule produces: 53 Swift
 * and 250 Kotlin call sites already wrap that way. Each pattern allows only whitespace between
 * the call and the literal, so a match spans a newline only when the call itself does. The
 * report names the line of the literal, and two positions that reach the same literal — an
 * `alert(` around a `Text(` — report it once.
 */
export function audit(root) {
    const findings = []
    if (!existsSync(root)) return findings
    for (const path of walk(root).sort()) {
        if (isTestPath(path)) continue
        const swift = path.endsWith('.swift')
        const text = readFileSync(path, 'utf8')
        const lines = text.split('\n')
        const hits = []
        const seen = new Set()
        for (const [position, pattern] of POSITIONS) {
            pattern.lastIndex = 0
            let match
            while ((match = pattern.exec(text))) {
                const literal = match[1]
                const line = text.slice(0, match.index + match[0].length - literal.length - 1).split('\n').length
                const key = `${line}\u0000${literal}`
                if (seen.has(key)) continue
                if (isComment(lines[line - 1])) continue
                if (!isSentence(literal, swift)) continue
                seen.add(key)
                hits.push({ path, line, position, literal })
            }
        }
        findings.push(...hits.sort((one, other) => one.line - other.line))
    }
    return findings
}

// ── Self-test ────────────────────────────────────────────────────────────────

function selfTest() {
    const dir = join(tmpdir(), `drawn-strings-selftest-${process.pid}`)
    const cases = []
    const run = (name, body) => {
        rmSync(dir, { recursive: true, force: true })
        mkdirSync(join(dir, 'App'), { recursive: true })
        writeFileSync(join(dir, 'App', name), body)
        return audit(dir)
    }

    let found = run('Refused.swift', 'alert(\n    Text(verbatim: "Cannot open this file"),\n)\n')
    cases.push(['a bare Swift sentence is reported', found.length === 1])
    cases.push(['it names the line', found[0]?.line === 2])
    cases.push(['it names the file', found[0]?.path.endsWith('Refused.swift')])
    cases.push(['it names the literal', found[0]?.literal === 'Cannot open this file'])

    found = run('Refused.swift', 'Button("OK") { file.wrappedValue = nil }\n')
    cases.push(['a two-letter button label is still a sentence', found.length === 1])

    found = run('Skipped.swift', 'Text("library.skipped \\(count)")\n')
    cases.push(['a Swift catalogue key is not a sentence', found.length === 0])

    found = run('Progress.swift', 'Text(verbatim: " · ")\nText(verbatim: "\\(index + 1)")\nText("")\n')
    cases.push(['a separator, a counter and an empty string are not sentences', found.length === 0])

    found = run('Shelf.kt', 'Text("Loading the shelf")\n')
    cases.push(['a bare Kotlin sentence is reported', found.length === 1])

    found = run('Shelf.kt', 'Text(stringResource(R.string.library_loading))\n')
    cases.push(['a Kotlin resource lookup is not a sentence', found.length === 0])

    found = run('Cover.kt', 'contentDescription = "Cover of this book",\ncontentDescription = null,\n')
    cases.push(['contentDescription is a drawing position', found.length === 1 && found[0].line === 1])

    found = run('Shelf.kt', 'Text("catalogue.error.http")\n')
    cases.push(['Kotlin gets no key exemption, because Compose has no key literals', found.length === 1])

    found = run('Refused.swift', '// Text(verbatim: "Cannot open this file")\n')
    cases.push(['a commented-out literal is not reported', found.length === 0])

    found = run('Refused.swift', 'accessibilityLabel(Text(verbatim: "Cover of this book"))\n')
    cases.push(['a literal in two positions at once is reported once', found.length === 1])

    found = run('Refused.swift', '.alert("Cannot open this file", isPresented: $shown) { }\n')
    cases.push(['an alert title with no Text( around it is reported', found[0]?.position === 'alert('])

    found = run('Cover.swift', '.accessibilityLabel("Cover of this book")\n')
    cases.push([
        'an accessibilityLabel with no Text( around it is reported',
        found[0]?.position === 'accessibilityLabel',
    ])

    found = run('Refused.swift', 'Text(\n    verbatim: "This book is damaged"\n)\n')
    cases.push(['a call wrapped onto the next line is reported', found.length === 1 && found[0]?.line === 2])

    found = run('Player.swift', 'Text("\\(duration.formatted())")\n')
    cases.push(['an interpolation that calls a function is not a sentence', found.length === 0])

    rmSync(dir, { recursive: true, force: true })
    mkdirSync(join(dir, 'Tests'), { recursive: true })
    writeFileSync(join(dir, 'Tests', 'ShelfTests.swift'), 'Text(verbatim: "Cannot open this file")\n')
    cases.push(['a test source is not a drawing surface', audit(dir).length === 0])

    rmSync(dir, { recursive: true, force: true })
    cases.push(['a tree with no sources passes', audit(dir).length === 0])

    let failed = 0
    for (const [name, ok] of cases) {
        console.log(`  ${ok ? 'pass' : 'FAIL'}  ${name}`)
        if (!ok) failed += 1
    }
    console.log(`drawn-strings self-test: ${cases.length - failed}/${cases.length} passed`)
    process.exit(failed ? 1 : 0)
}

// ── Check ────────────────────────────────────────────────────────────────────

function check() {
    const findings = audit(ROOT)
    if (findings.length) {
        console.error(`drawn-strings: ${findings.length} drawn sentence(s) that no catalogue holds.\n`)
        for (const finding of findings) {
            console.error(`  ${finding.path}:${finding.line}  ${finding.position}  "${finding.literal}"`)
        }
        console.error(
            '\nA sentence a reader can be shown belongs in a catalogue in all four languages.'
            + ' `strings:ios` cannot see one, because it was never a key.'
        )
        process.exit(1)
    }
    console.log(`drawn-strings: no bare sentence in a drawing position under ${ROOT}/.`)
}

// Guarded, so the proof of 5.2 and any other script can import `audit` without running the
// check, the way `a11y-scan.mjs` guards its own entry point.
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
    if (process.argv.includes('--self-test')) selfTest()
    else check()
}
