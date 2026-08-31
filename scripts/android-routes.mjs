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
/**
 * A step's name in each of the four languages this app ships.
 *
 * The route map was English-only, and that is a real limit rather than a tidiness point: it
 * blocked the Spanish captures the chip-row work needed, and `capture-android.mjs` failed at
 * its first step with "could not reach Library" against an app set to Spanish, where the tab
 * reads *Biblioteca*.
 *
 * Every value is read out of the module's own `values-<locale>` string files rather than translated
 * here — the key is named beside each so the next reader can check it, and a walk that
 * invented its own translation would pass against an app that says something else.
 */
const NAMES = {
    home: 'Home|Inicio|Start|Accueil', //                         destination_home
    library: 'Library|Biblioteca|Bibliothek|Bibliothèque', //      destination_library
    downloads: 'Downloads|Descargas|Téléchargements', //           destination_downloads (de is "Downloads")
    search: 'Search|Buscar|Suche|Recherche', //                    destination_search
    more: 'More|Más|Mehr|Plus', //                                 library_more
    settings: 'Settings|Ajustes|Einstellungen|Réglages', //        settings_title
    // A publication nobody has opened offers Read; a part-read one offers Continue. Both keys
    // are `detail_action_*` on the publication page — **not** `library_continue_reading`, whose
    // Spanish is "Continuar leyendo" where the page's button says "Seguir". Using the wrong key
    // cost the two comic-reader routes on the first Spanish walk, and the walk said so by
    // printing the whole alternatives list it could not find.
    read: 'Read|Leer|Lesen|Lire|Continue|Seguir|Weiterlesen|Reprendre', // detail_action_read + detail_action_continue
    appearance: 'Appearance|Apariencia|Erscheinungsbild|Apparence',
    reading: 'Reading|Lectura|Lesen|Lecture',
    privacy: 'Privacy|Privacidad|Datenschutz|Confidentialité',
    about: 'About|Acerca de|Über|À propos',
    language: 'Language|Idioma|Sprache|Langue',
    whatsNew: 'What\u2019s new|Novedades|Neuerungen|Nouveautés', //  whats_new_about
    sources: 'Your libraries|Tus bibliotecas|Ihre Bibliotheken|Vos bibliothèques',
    storage: 'Downloads and storage|Descargas y almacenamiento|Downloads und Speicher|Téléchargements et stockage',
}

export const ROUTES = [
    ['Home', []],
    ['Library', [NAMES.library]],
    ['Downloads', [NAMES.downloads]],
    // Search became a destination with a page behind it in `quiet-shell-and-search`; before
    // that it was a field on the library screen, and there was nothing here to walk to. The
    // page at rest is what this photographs — the bar plus what it offers before a letter is
    // typed. The *expanded* bar is a second condition and still has to be taken by hand: it
    // needs a tap on the field, which is a step this table has no vocabulary for.
    ['Search', [NAMES.search]],
    // A cover leads to the publication's page now, and the page's own action leads to the
    // reader. That is two taps where this list used to have one, and the reason the list
    // said twelve of thirteen routes were unreachable the first time it ran after the
    // navigation rewrite: it was still describing the app as it had been.
    ['Publication page', [NAMES.library, ', CBZ']],
    ['Comic reader', [NAMES.library, ', CBZ', NAMES.read]],
    ['Comic reader > chrome', [NAMES.library, ', CBZ', NAMES.read, '@tap-centre']],
    ['EPUB reader', [NAMES.library, ', EPUB', NAMES.read]],
    // Settings left the browse path in the shell revamp: it is behind the library's
    // overflow, which is why naming it as a first step found nothing.
    ['Settings', [NAMES.library, NAMES.more, NAMES.settings]],
    ['Settings > Appearance', [NAMES.library, NAMES.more, NAMES.settings, NAMES.appearance]],
    ['Settings > Reading', [NAMES.library, NAMES.more, NAMES.settings, NAMES.reading]],
    ['Settings > Privacy', [NAMES.library, NAMES.more, NAMES.settings, NAMES.privacy]],
    ['Settings > About', [NAMES.library, NAMES.more, NAMES.settings, NAMES.about]],
    ['Settings > About > licence', [NAMES.library, NAMES.more, NAMES.settings, NAMES.about, 'Readium Kotlin Toolkit']],
    ['Settings > About > what\u2019s new', [NAMES.library, NAMES.more, NAMES.settings, NAMES.about, NAMES.whatsNew]],
    ['Settings > Your libraries', [NAMES.library, NAMES.more, NAMES.settings, NAMES.sources]],
    ['Settings > Downloads', [NAMES.library, NAMES.more, NAMES.settings, NAMES.storage]],
    ['Settings > Language', [NAMES.library, NAMES.more, NAMES.settings, NAMES.language]],
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
