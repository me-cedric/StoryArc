/**
 * How a script reaches a screen on a connected Android device, and the list of screens.
 *
 * Extracted from `smoke-android.mjs` when a second script needed the same thing. Reaching a
 * screen is one problem with one answer: a route is a list of names to tap, each matched
 * against a node's text or its content description, so the list reads as what a person would
 * do. The crash walk and the screenshot capture disagreeing about how to reach Settings is
 * how one of them silently starts photographing Home — which has happened on the other
 * platform, and is why `AuditWalk.swift` says the same thing about iOS.
 *
 * Nothing here judges a screen. `smoke-android.mjs` asks whether it crashed, `a11y-scan.mjs`
 * asks whether it is usable, `capture-android.mjs` photographs it.
 */
import { execFileSync } from 'node:child_process'

export const PKG = 'app.storyarc.debug'
export const ACTIVITY = `${PKG}/app.storyarc.MainActivity`

export const sleep = (ms) => execFileSync('/bin/sleep', [String(ms / 1000)])

/**
 * Every route worth reaching, as the taps that reach it.
 *
 * A route is a list of names to tap in order. Each is matched against a node's text or
 * its content description, so the list reads as what a person would do.
 *
 * A step may name alternatives with `|`, and the reader's action needs it: a publication
 * nobody has opened offers **Read** and one that is part-read offers **Continue**, so a map
 * naming only one of them stops walking the moment somebody reads a page. That is not
 * hypothetical — it took this walk from 16 of 16 to 14 of 16 an hour after a fixture was
 * read for an unrelated screenshot, and `AuditWalk.swift` carries the same note about the
 * same defect on iOS, where it had already cost a suite its meaning.
 */
export const ROUTES = [
    ['Home', []],
    ['Library', ['Library']],
    ['Downloads', ['Downloads']],
    // A cover leads to the publication's page now, and the page's own action leads to the
    // reader. That is two taps where this list used to have one, and the reason the list
    // said twelve of thirteen routes were unreachable the first time it ran after the
    // navigation rewrite: it was still describing the app as it had been.
    ['Publication page', ['Library', ', CBZ']],
    ['Comic reader', ['Library', ', CBZ', 'Read|Continue']],
    ['Comic reader > chrome', ['Library', ', CBZ', 'Read|Continue', '@tap-centre']],
    ['EPUB reader', ['Library', ', EPUB', 'Read|Continue']],
    // Settings left the browse path in the shell revamp: it is behind the library's
    // overflow, which is why naming it as a first step found nothing.
    ['Settings', ['Library', 'More', 'Settings']],
    ['Settings > Appearance', ['Library', 'More', 'Settings', 'Appearance']],
    ['Settings > Reading', ['Library', 'More', 'Settings', 'Reading']],
    ['Settings > Privacy', ['Library', 'More', 'Settings', 'Privacy']],
    ['Settings > About', ['Library', 'More', 'Settings', 'About']],
    ['Settings > About > licence', ['Library', 'More', 'Settings', 'About', 'Readium Kotlin Toolkit']],
    ['Settings > Your libraries', ['Library', 'More', 'Settings', 'Your libraries']],
    ['Settings > Downloads', ['Library', 'More', 'Settings', 'Downloads and storage']],
    ['Settings > Language', ['Library', 'More', 'Settings', 'Language']],
]

/**
 * The centre of the first node whose text or description contains `needle`, or null.
 */
export function centre(xml, needle) {
    for (const [tag] of xml.matchAll(/<node\b[^>]*?\/?>/g)) {
        const attrs = Object.fromEntries(
            [...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([, key, value]) => [key, value])
        )
        const name = `${attrs['content-desc'] ?? ''}\0${attrs.text ?? ''}`
        if (!name.toLowerCase().includes(needle.toLowerCase())) continue
        const box = /\[(\d+),(\d+)]\[(\d+),(\d+)]/.exec(attrs.bounds ?? '')
        if (box) {
            const [l, t, r, b] = box.slice(1).map(Number)
            return [Math.round((l + r) / 2), Math.round((t + b) / 2)]
        }
    }
    return null
}

/**
 * The tapping half, bound to one `adb` runner.
 *
 * Returned as a bundle rather than exported one by one because every one of them needs the
 * runner, and threading it through four call sites is how two of them end up talking to
 * different devices.
 */
export function navigator(sh) {
    /**
     * The accessibility tree, retried, because a single attempt lies.
     *
     * uiautomator answers `ERROR: null root node returned by UiTestAutomationBridge` and
     * writes nothing whenever it is asked while a window is animating -- which, in a script
     * whose every step is a tap followed immediately by a read, is most of the time. The
     * caller then saw an empty document, concluded the control it wanted was absent,
     * scrolled looking for it, and eventually reported the route unreachable. Thirteen of
     * sixteen routes failed that way against an app where every one of them worked.
     *
     * So: ask again, and give the window a moment first. Three attempts is enough for a
     * transition; a screen that cannot be read after that is genuinely not there.
     */
    const dump = () => {
        for (let attempt = 0; attempt < 3; attempt += 1) {
            if (attempt > 0) sleep(900)
            const dumped = sh('shell', 'uiautomator', 'dump', '/sdcard/smoke.xml')
            if (!/dumped to/.test(dumped)) continue
            const xml = sh('shell', 'cat', '/sdcard/smoke.xml')
            if (xml.includes('<?xml')) return xml.slice(xml.indexOf('<?xml'))
        }
        return ''
    }

    const tap = (x, y) => {
        sh('shell', 'input', 'tap', String(x), String(y))
        sleep(1700)
    }

    /** A fresh launch, so no route depends on where the previous one left the app. */
    const launch = () => {
        sh('shell', 'am', 'force-stop', PKG)
        sh('shell', 'am', 'start', '-n', ACTIVITY)
        sleep(3500)
    }

    /**
     * Walks one route from a fresh launch. Returns the step it could not reach, or null.
     *
     * Scrolls and retries before giving up: a control below the fold is present and simply
     * not on screen, and reporting that as unreachable is how this reported a working app
     * as broken.
     */
    const walk = (steps) => {
        launch()
        for (const step of steps) {
            if (step === '@tap-centre') {
                // Revealing the reader chrome is a tap on the page, not on a named control.
                tap(540, 1200)
                continue
            }
            // Any one of the alternatives will do, and each is tried against the same
            // tree before scrolling: a page offering *Continue* is not a page missing *Read*.
            const wanted = step.split('|')
            let spot = null
            for (let attempt = 0; attempt < 3 && !spot; attempt += 1) {
                const tree = dump()
                for (const name of wanted) {
                    spot = centre(tree, name)
                    if (spot) break
                }
                if (!spot) {
                    sh('shell', 'input', 'swipe', '540', '1800', '540', '800', '260')
                    sleep(1200)
                }
            }
            if (!spot) return step
            tap(...spot)
        }
        return null
    }

    return { dump, tap, launch, walk }
}
