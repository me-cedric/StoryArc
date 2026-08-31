#!/usr/bin/env node
/**
 * Walks the app under an expanded pseudo-locale and reports what stops fitting.
 *
 * `localization` asks that "when the app runs under an expanded pseudo-locale, no screen
 * clips, overlaps, or hides a control". German is the longest language that ships and it
 * is not long enough to prove that: `en-XA` accents every letter and pads each string by
 * roughly half again, which is the width a translation is allowed to reach.
 *
 * Two things had to be true before this could test anything. The debug build now sets
 * `isPseudoLocalesEnabled`, without which `en-XA` is not compiled in and the device
 * silently falls back to English — a walk that passes because nothing changed. And the
 * navigation here is by *position*, never by label: under a pseudo-locale "Settings" reads
 * "[Šéttîñgš one]", so a script that finds screens by their text finds nothing.
 *
 * Three checks, all read off the accessibility tree rather than a screenshot, because a
 * screenshot cannot say whether a label was cut or merely short:
 *
 *   OVERFLOW  a node whose bounds leave its parent's. Text that has outgrown its row.
 *   OFFSCREEN an actionable node lying wholly outside the display. A control the reader
 *             cannot reach, which is the "hides a control" clause.
 *   SMALL     an actionable node under the 48dp floor, measured at the device's own
 *             density — the same floor `a11y-scan.mjs` applies, re-checked here because a
 *             longer label can wrap a row into a shape it did not have in English.
 *
 * Usage:
 *   node scripts/pseudo-locale.mjs              walk under en-XA, then restore the locale
 *   node scripts/pseudo-locale.mjs --keep       leave the device in en-XA afterwards
 *   node scripts/pseudo-locale.mjs --self-test  check the checks still fire
 */
import { pathToFileURL } from 'node:url'
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

import { adbRunner, resolveAdb } from './adb.mjs'

const PKG = 'app.storyarc.debug'
const ACTIVITY = `${PKG}/app.storyarc.MainActivity`
const PSEUDO = 'en-XA'
const MIN_DP = 48
const SHOTS = 'artifacts/pseudo-locale'

// Where adb is lives in scripts/adb.mjs, which asks the project's own `sdk.dir` before
// it guesses at an install location.
const adb = resolveAdb()

const sh = adbRunner(adb)

const settle = (ms) => execFileSync(adb, ['shell', `sleep ${ms / 1000}`], { encoding: 'utf8' })

/**
 * The accessibility tree, retried, because a single attempt lies.
 *
 * uiautomator answers `ERROR: null root node returned by UiTestAutomationBridge` and emits
 * nothing whenever it is asked while a window is animating -- and every step here is a tap
 * followed immediately by a read. An empty document parses to zero nodes, and zero nodes
 * reads as "this screen has no navigation on it", which is how a walk that worked reported
 * `expected three bottom destinations, found 0`. Ask again, and give the window a moment.
 */
const tree = () => {
    for (let attempt = 0; attempt < 3; attempt += 1) {
        if (attempt > 0) settle(900)
        const nodes = parse(sh('exec-out', 'uiautomator', 'dump', '/dev/tty'))
        if (nodes.length > 0) return nodes
    }
    throw new Error('uiautomator could not read the screen after three attempts')
}

/** Every node in a uiautomator dump, with its bounds and the flags this cares about. */
export const parse = (xml) => {
    const nodes = []
    const stack = []
    // A hand-rolled scan rather than an XML parser: the dump is one long line of
    // self-closing and nesting `<node>` elements, and the only thing needed from it is the
    // parent of each node, which a stack gives for the cost of reading the tag's tail.
    for (const match of xml.matchAll(/<node\b([^>]*?)(\/?)>|<\/node>/g)) {
        if (match[0] === '</node>') {
            stack.pop()
            continue
        }
        const attributes = Object.fromEntries(
            [...match[1].matchAll(/([\w-]+)="([^"]*)"/g)].map(([, k, v]) => [k, v]),
        )
        const [, l, t, r, b] = /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(attributes.bounds ?? '') ?? []
        const node = {
            text: attributes.text ?? '',
            description: attributes['content-desc'] ?? '',
            clickable: attributes.clickable === 'true' || attributes.checkable === 'true',
            bounds: { left: +l, top: +t, right: +r, bottom: +b },
            parent: stack[stack.length - 1] ?? null,
        }
        nodes.push(node)
        if (!match[2]) stack.push(node)
    }
    return nodes
}

const contains = (outer, inner) =>
    inner.left >= outer.left && inner.top >= outer.top && inner.right <= outer.right && inner.bottom <= outer.bottom

const overlaps = (a, b) => a.right > b.left && a.left < b.right && a.bottom > b.top && a.top < b.bottom

export const inspect = (nodes, screen, density) => {
    const problems = []
    const dp = (px) => Math.round((px * 160) / density)
    for (const node of nodes) {
        const { bounds } = node
        if (!Number.isFinite(bounds.left) || bounds.right <= bounds.left) continue
        const named = node.text || node.description
        const label = named ? `"${named.slice(0, 40)}"` : '(unnamed)'

        // A row that has outgrown its container. The parent is the row; a child wider than
        // it is text the layout could not absorb.
        if (node.parent && named && !contains(node.parent.bounds, bounds)) {
            problems.push(`OVERFLOW  ${label} leaves its container by ${dp(Math.max(bounds.right - node.parent.bounds.right, node.parent.bounds.left - bounds.left))}dp`)
        }
        if (node.clickable && !overlaps(bounds, screen)) {
            problems.push(`OFFSCREEN  ${label} is a control lying wholly outside the display`)
        }
        if (node.clickable && overlaps(bounds, screen)) {
            const height = dp(bounds.bottom - bounds.top)
            const width = dp(bounds.right - bounds.left)
            if (height < MIN_DP || width < MIN_DP) {
                problems.push(`SMALL  ${label} is ${width}×${height}dp, below the ${MIN_DP}dp floor`)
            }
        }
    }
    return [...new Set(problems)]
}

/**
 * Where to go, by position rather than by name.
 *
 * Each step is an ordinal: `row: n` taps the nth row of the settings list, `gear` taps the
 * last action in the top bar. Nothing here matches text, because under a pseudo-locale
 * there is no text to match.
 */
/**
 * Every route, as positions rather than names.
 *
 * Nothing here is matched by text, and that is the point: this walk runs under `en-XA`,
 * where every string is `[Ĺíbŕáŕý one two]`, so navigation that reads a label cannot work.
 *
 * The shell revamp moved Settings off the browse path -- the app opens on Home now, and
 * Settings sits at the foot of the library's overflow -- so `gear` alone stopped finding
 * anything and this walk failed at its first step with "no action found in the top bar".
 * `to-library` and `overflow-last` are the two hops it grew, and both are positional for
 * the same reason `gear` always was.
 */
const TO_SETTINGS = ['to-library', 'gear', 'overflow-last']

// KNOWN GAP, narrowed 2026-08-31: the walk now reaches **Library** under `en-XA`, which it
// never did before, and `Home` and `Library` both pass. The Settings routes still fail one hop
// later: `gear` finds a clickable node in the top eighth and taps it, and the overflow menu
// does not open, so `overflow-last` never finds an item. What has been ruled out — each by
// measurement under the pseudo-locale, not by reading:
//
//   * It is not the container-vs-destination confusion that was recorded here before. The
//     bottom bar's three destinations are exact thirds of the display under `en-XA` as well
//     as under English, and `tapLibrary` now identifies them by that and lands correctly.
//   * It is not a race. All four positional helpers now read the screen until what they are
//     counting is there, rather than once; four reads a second apart is not enough for a menu
//     that is never opening.
//   * It is not that the current destination is unclickable, which is true and was the reason
//     a clickability filter could never see three of them.
//
// What is left to establish is what the rightmost clickable node in the Library's top eighth
// actually *is* under `en-XA`. Under English it is the overflow at x=944..1070. A one-shot
// dump cannot answer it: every attempt read the screen before the shell had drawn, which is
// the same trap `tapWhenFound` exists for — the diagnostic needs the same patience the walk
// now has.

const ROUTES = [
    ['Home', []],
    ['Library', ['to-library']],
    ['Settings', TO_SETTINGS],
    ['Settings > Sources', [...TO_SETTINGS, { row: 0 }]],
    ['Settings > Appearance', [...TO_SETTINGS, { row: 1 }]],
    ['Settings > Reading', [...TO_SETTINGS, { row: 2 }]],
    ['Settings > Downloads', [...TO_SETTINGS, { row: 3 }]],
    ['Settings > Language', [...TO_SETTINGS, { row: 4 }]],
    ['Settings > Privacy', [...TO_SETTINGS, { row: 5 }]],
    ['Settings > About', [...TO_SETTINGS, { row: 6 }]],
]

/**
 * Reads the tree until it holds the thing being looked for, then taps it.
 *
 * **`tree()` waits for *a* tree, not for *the* tree.** It retries only while the dump comes
 * back empty, and a splash screen is not empty — nor is the screen behind an opening menu.
 * So every positional helper here read once, counted what happened to be on screen, and
 * either threw or tapped the wrong thing. That is one cause behind three separate symptoms:
 * `to-library` landing on a destination with no top bar, the overflow menu appearing to never
 * open, and a settings row index counting rows that had not been drawn yet. Two of the three
 * were recorded as known gaps for a day.
 *
 * A fixed settle cannot fix it, because the wait that is long enough on one machine after a
 * warm start is not long enough on another after a cold one. Asking for what is needed is the
 * only wait that is right by construction.
 *
 * @param find given the tree, the node to tap, or null when it is not there yet.
 * @param what what was being looked for, for the message when it never arrives.
 */
const tapWhenFound = (find, what) => {
    for (let attempt = 0; attempt < 4; attempt += 1) {
        if (attempt > 0) settle(900)
        const found = find(tree())
        if (!found) continue
        const { bounds } = found
        sh('shell', 'input', 'tap', String((bounds.left + bounds.right) >> 1), String((bounds.top + bounds.bottom) >> 1))
        return
    }
    throw new Error(`${what} never appeared, after four reads of the screen a second apart.`)
}

/**
 * Taps the middle of the three bottom destinations, which is the library.
 *
 * By position, like everything else here: under `en-XA` every label reads
 * `[Ĺíbŕáŕý one two]`, so nothing can be found by name.
 *
 * **A destination is identified by its width, not by being clickable.** Two things made the
 * obvious filter wrong, and between them they cost this walk a day of every Settings route
 * failing while Home passed:
 *
 * 1. The bar's own container is clickable and as wide as the display, so it was counted
 *    alongside its children and "the middle of four" was not the middle destination.
 * 2. **The destination the app is already on is not clickable at all.** The shell opens on
 *    Home, Compose gives the selected item `selected="true"` and no click semantic, and so
 *    only ever *two* of the three are clickable. Filtering on clickability can therefore
 *    never see three, whatever else is fixed.
 *
 * The bar divides the display into equal thirds, so a destination is a node at the foot of
 * the screen one third of the display wide. That is a property of what the thing is. The
 * duplicates are nested wrappers sharing a child's bounds, so one per left edge is kept.
 *
 * Read off a real emulator rather than assumed: at 1080 wide the three sit at x=0..360,
 * 360..720 and 720..1080, and the two 1080-wide nodes above them are the bar and the window.
 */
const tapLibrary = () =>
    tapWhenFound((nodes) => {
        const height = Math.max(...nodes.map((n) => n.bounds.bottom).filter(Number.isFinite))
        const width = Math.max(...nodes.map((n) => n.bounds.right).filter(Number.isFinite))
        const third = width / 3
        const byLeft = new Map()
        for (const node of nodes) {
            const { left, right, top } = node.bounds
            if (!Number.isFinite(right) || top <= (height * 7) / 8) continue
            // Within a pixel of a third: the bar's own thirds, and neither the bar nor an icon.
            if (Math.abs(right - left - third) > 1) continue
            if (!byLeft.has(left)) byLeft.set(left, node)
        }
        const bar = [...byLeft.values()].sort((a, b) => a.bounds.left - b.bounds.left)
        return bar.length === 3 ? bar[1] : null
    }, 'the middle of three bottom destinations')

/**
 * Taps the last item of an open dropdown, which is Settings.
 *
 * Last rather than named, for the locale reason, and last rather than first because the
 * overflow builds Select, Shelves and Settings in that order and drops any of the first two
 * that has nothing to do -- so counting from the top would land somewhere different on an
 * empty library than on a full one. Counting from the bottom lands on Settings either way.
 */
/**
 * Taps the last item of the overflow menu, which is Settings.
 *
 * **Waits for the menu rather than for a tree.** `tree()` retries only while the dump comes
 * back *empty*, and the screen behind an opening menu is not empty — so the first read
 * returned the library, found no menu item, and threw. The step before this one has a 1200 ms
 * settle after it and that was not always enough. Every Settings route in this walk failed
 * that way for a day while Home and Library passed, which is the shape of a wait that is
 * long enough on the machine it was written on.
 *
 * So it asks for what it needs, three times, and says what it saw when it gives up. The
 * menu's items are in the top half of the display because the overflow it hangs from is in
 * the top bar; measured on an emulator they sit at y=296..422, 422..548 and 548..674 of 2400.
 */
const tapLastMenuItem = () =>
    tapWhenFound((nodes) => {
        const height = Math.max(...nodes.map((n) => n.bounds.bottom).filter(Number.isFinite))
        const items = nodes
            .filter((n) => n.clickable && Number.isFinite(n.bounds.bottom) && n.bounds.bottom < height / 2)
            .sort((a, b) => a.bounds.top - b.bounds.top)
        return items.at(-1) ?? null
    }, 'the last item of the overflow menu')

const tapGear = () =>
    tapWhenFound((nodes) => {
        // The rightmost clickable node in the top eighth of the display. Position, not name.
        const height = Math.max(...nodes.map((n) => n.bounds.bottom).filter(Number.isFinite))
        const top = nodes
            .filter((n) => n.clickable && n.bounds.top < height / 8 && Number.isFinite(n.bounds.right))
            .sort((a, b) => b.bounds.right - a.bounds.right)
        return top[0] ?? null
    }, 'an action in the top bar')

/**
 * Taps the nth row of a settings list.
 *
 * A row is identified by spanning the full width, which is the one thing that separates it
 * from the search field and the back button — Compose merges a row's labels into
 * descendants, so the clickable node itself carries no text at all, in any locale. That is
 * a happy accident here: navigation that cannot read text cannot be broken by translating
 * it.
 */
const tapRow = (index) =>
    tapWhenFound((nodes) => {
        const width = Math.max(...nodes.map((n) => n.bounds.right).filter(Number.isFinite))
        const rows = nodes
            .filter(
                (n) =>
                    n.clickable &&
                    Number.isFinite(n.bounds.top) &&
                    n.bounds.left <= 8 &&
                    n.bounds.right >= width - 8,
            )
            .sort((a, b) => a.bounds.top - b.bounds.top)
        return rows[index] ?? null
    }, `row ${index} of the settings list`)

const walk = () => {
    const density = Number(/\d+/.exec(sh('shell', 'wm', 'density'))?.[0] ?? 160)
    const [, w, h] = /(\d+)x(\d+)/.exec(sh('shell', 'wm', 'size').split('\n').at(-2) ?? '') ?? []
    const screen = { left: 0, top: 0, right: +w || 1080, bottom: +h || 2340 }
    mkdirSync(SHOTS, { recursive: true })

    const found = []
    for (const [name, steps] of ROUTES) {
        sh('shell', 'am', 'force-stop', PKG)
        sh('shell', 'am', 'start', '-n', ACTIVITY)
        settle(2500)
        for (const step of steps) {
            if (step === 'to-library') tapLibrary()
            else if (step === 'gear') tapGear()
            else if (step === 'overflow-last') tapLastMenuItem()
            else tapRow(step.row)
            settle(1200)
        }
        const nodes = tree()
        const problems = inspect(nodes, screen, density)
        writeFileSync(join(SHOTS, `${name.replace(/[^\w]+/g, '-')}.png`), execFileSync(adb, ['exec-out', 'screencap', '-p'], { maxBuffer: 1 << 28 }))
        for (const problem of problems) found.push(`${name}: ${problem}`)
        console.log(`${problems.length === 0 ? '  ok' : 'FAIL'}  ${name}`)
    }
    return found
}

const selfTest = () => {
    let ok = true
    const fail = (m) => {
        ok = false
        console.error('  ' + m)
    }
    const screen = { left: 0, top: 0, right: 1080, bottom: 2340 }

    const dump =
        '<hierarchy><node bounds="[0,0][1080,200]" text="" clickable="false">' +
        '<node bounds="[0,0][1200,200]" text="Ovérflówîñg" clickable="false" />' +
        '</node>' +
        '<node bounds="[0,300][100,330]" text="Tiny" clickable="true" />' +
        '<node bounds="[2000,400][2100,500]" text="Gone" clickable="true" />' +
        '<node bounds="[0,600][200,800]" text="Fine" clickable="true" />' +
        '</hierarchy>'
    const problems = inspect(parse(dump), screen, 160)
    if (!problems.some((p) => p.startsWith('OVERFLOW'))) fail('OVERFLOW did not fire on a child wider than its parent')
    if (!problems.some((p) => p.startsWith('SMALL'))) fail('SMALL did not fire on a 100x30dp control')
    if (!problems.some((p) => p.startsWith('OFFSCREEN'))) fail('OFFSCREEN did not fire on a control off the display')
    if (problems.some((p) => p.includes('Fine'))) fail('a node that fits was reported')

    if (parse(dump).filter((n) => n.parent !== null).length !== 1) fail('parent tracking is wrong')

    console.log(ok ? 'self-test passed' : 'self-test FAILED')
    process.exitCode = ok ? 0 : 1
}

/**
 * Run only when run, so `parse` can be imported without walking a device.
 *
 * `parse` is exported and a diagnostic that imported it for that alone found itself driving
 * the emulator, changing the app's locale and force-stopping it — the same wart
 * `a11y-scan.mjs` already grew this guard for, in the same words.
 */
const isMain = import.meta.url === pathToFileURL(process.argv[1] ?? '').href

if (!isMain) {
    // Imported for `parse`. Nothing to do.
} else if (process.argv.includes('--self-test')) {
    selfTest()
} else {
    try {
        // Per-app locale rather than the system one: `persist.sys.locale` is a protected
        // property that a non-root shell cannot set, and rooting the device to run a
        // layout check is a large hammer. `cmd locale` has existed since Android 13 and
        // this app's floor is 12 — but the *check* only has to run somewhere, and the
        // emulator it runs on is API 36.
        sh('shell', 'cmd', 'locale', 'set-app-locales', PKG, '--locales', PSEUDO)
        // The locale is read at process start, so the app has to go before it is honoured.
        sh('shell', 'am', 'force-stop', PKG)
        settle(1500)
        const problems = walk()
        for (const problem of problems) console.error(problem)
        console.log(
            problems.length === 0
                ? `pseudo-locale (${PSEUDO}): every screen fits. Screenshots in ${SHOTS}/.`
                : `pseudo-locale (${PSEUDO}): ${problems.length} problem(s). Screenshots in ${SHOTS}/.`,
        )
        process.exitCode = problems.length > 0 ? 1 : 0
    } finally {
        if (!process.argv.includes('--keep')) {
            // An empty locale list is what "follow the system again" means to `cmd locale`.
            sh('shell', 'cmd', 'locale', 'set-app-locales', PKG, '--locales', '')
            sh('shell', 'am', 'force-stop', PKG)
        }
    }
}
