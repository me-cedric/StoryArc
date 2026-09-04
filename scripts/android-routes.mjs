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
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const PKG = 'app.storyarc.debug'
export const ACTIVITY = `${PKG}/app.storyarc.MainActivity`

export const sleep = (ms) => execFileSync('/bin/sleep', [String(ms / 1000)])

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

/** Every module that ships strings, and every language the app ships them in. */
const STRING_MODULES = ['app', 'core/playback', 'feature/library', 'feature/reader', 'feature/epubreader', 'feature/settings']
const STRING_LOCALES = ['', '-de', '-es', '-fr']

/**
 * Every `<string>` in the app, by resource name, in all four languages.
 *
 * Read out of the app's own resources rather than copied here. The hand-copied table
 * below carries a long note about why a walk that invents its own translation passes
 * against an app that says something else — and the answer to that is not more care with
 * the copying, it is not copying. A sweep that names sixty controls cannot hand-maintain
 * two hundred and forty translations, and the one it got wrong would be indistinguishable
 * from a control that had moved.
 *
 * Two transformations, both because `centre()` matches a substring of what is on screen:
 *
 *  - `\uXXXX` escapes and XML entities are decoded, because the file holds
 *    `What’s new` and the screen holds `What’s new`.
 *  - Everything from the first format specifier on is dropped, because `Sort: %1$s` never
 *    appears and `Sort: ` always does.
 */
const STRINGS = (() => {
    const decode = (value) =>
        value
            .replaceAll(/\\u([0-9a-fA-F]{4})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
            .replaceAll('\\n', '\n')
            .replaceAll("\\'", "'")
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#8230;', '…')
            .replaceAll('&amp;', '&')
    const table = new Map()
    for (const module of STRING_MODULES) {
        for (const locale of STRING_LOCALES) {
            const file = join(ROOT, `apps/android/${module}/src/main/res/values${locale}/strings.xml`)
            if (!existsSync(file)) continue
            for (const [, name, body] of readFileSync(file, 'utf8').matchAll(/<string name="([\w.]+)"[^>]*>([\s\S]*?)<\/string>/g)) {
                // A step matches on the literal part, so a placeholder ends the useful prefix.
                const value = decode(body).split('%')[0].trim()
                if (value.length < 2) continue
                if (!table.has(name)) table.set(name, new Set())
                table.get(name).add(value)
            }
        }
    }
    return table
})()

/**
 * One step naming a control, in every language the app draws it in.
 *
 * Throws on a name the app does not define, which is the point: a renamed resource fails
 * the route table at import rather than one screenshot at 3am, and a typo cannot quietly
 * become "could not reach".
 */
export function named(resource) {
    const values = STRINGS.get(resource)
    if (!values) throw new Error(`No <string name="${resource}"> in any Android module — the route table names one that does not exist.`)
    return [...values].join('|')
}

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
    ['Comic reader > chrome', [NAMES.library, ', CBZ', NAMES.read, '!@tap-centre']],
    // Named, rather than "the first thing labelled EPUB". The corpus's first EPUB by title
    // is `Bright Panels`, which `corpus.mjs` builds `fixed: true` — a pre-paginated book
    // opens in the *comic* reader, not the EPUB activity. So this route was photographing
    // the comic reader under a name that says EPUB, which is precisely the confusion the
    // header above says a shared route table exists to prevent.
    //
    // `Glasshouse` is no better and was the second wrong guess: `spineCoverEpub` writes
    // `rendition:layout pre-paginated` too. Two of the corpus's four EPUBs are fixed-layout,
    // and they are the two a route reaching for "the first EPUB" finds first. So the book
    // is named, and the name is one `corpus.mjs` builds from chapters of prose.
    ['EPUB reader', [NAMES.library, 'Harbour Lights 01', NAMES.read, '!@tap-centre']],
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

    // ---------------------------------------------------------------------------------
    // Below here: the states a destination can be *in*, rather than the destinations.
    //
    // Added for the 2026-09-02 sweep, whose brief was every surface and every state of
    // it. The eighteen routes above reach eighteen screens and photograph each of them
    // at rest — which left every menu, every sheet, every dialog, every empty state and
    // every failure notice in this app unphotographed, and a surface nobody looks at is
    // a surface that gets no design feedback. Names come from `named()`, so each step is
    // the app's own string in all four languages and a renamed resource fails at import.
    // ---------------------------------------------------------------------------------

    // --- Library: the chip row, the menus behind it, and what narrowing produces ------
    ['Library > list layout', [NAMES.library, named('library_layout_list')]],
    // The shelf opens narrowed to what is on the device. Tapping the chip widens it.
    ['Library > everywhere', [NAMES.library, named('source_on_this_device')]],
    ['Library > sort menu', [NAMES.library, named('library_sort_chip')]],
    ['Library > filter menu', [NAMES.library, named('library_filter')]],
    ['Library > filter values', [NAMES.library, named('library_filter'), named('library_filter_read_state')]],
    ['Library > filter active', [NAMES.library, named('library_filter'), named('library_filter_read_state'), named('library_read_state_in_progress'), '@back']],
    ['Library > overflow menu', [NAMES.library, NAMES.more]],
    ['Library > add source menu', [NAMES.library, named('library_add_source')]],
    // Everything the shelf holds is a local file, so "not downloaded" matches nothing —
    // which is the only way to reach the narrowed-to-nothing state without inventing data.
    ['Library > nothing matches', [NAMES.library, named('library_filter'), named('library_filter_download'), named('library_filter_download_no'), '@back']],
    ['Library > skipped list', [NAMES.library, named('library_skipped_list')]],
    // Selection mode is the app's own overflow entry, not a long press, and it opens with
    // nothing selected — a state of its own, and the one the bar is designed around.
    ['Library > selection none', [NAMES.library, NAMES.more, named('library_select')]],
    ['Library > selection two', [NAMES.library, NAMES.more, named('library_select'), 'Fine Print', 'Foreign Codec']],
    // The one bulk action that is a word rather than a glyph. A top app bar's action slot
    // has no room for *Add to…* at any width, so it is an overflow row with its name
    // showing — and a row nobody photographs is a row nobody can check the wording of.
    // The last step is the selection bar's own overflow: in this mode it is the only
    // control on screen described as `library_more`, because the bar has replaced the
    // library's own.
    ['Library > selection overflow', [NAMES.library, NAMES.more, named('library_select'), 'Fine Print', 'Foreign Codec', NAMES.more]],
    ['Library > add to shelf', [NAMES.library, '@long Fine Print']],

    // --- The publication page, in the three shapes its own layout has ----------------
    ['Publication page > overflow', [NAMES.library, ', CBZ', named('detail_more')]],
    ['Publication page > add to shelf', [NAMES.library, ', CBZ', named('detail_more'), named('detail_add_to_shelf')]],
    ['Publication page > PDF', [NAMES.library, ', PDF']],
    ['Publication page > series', [NAMES.library, 'Tidal Reach #2']],

    // --- The comic reader ------------------------------------------------------------
    ['Comic reader > menu', [NAMES.library, ', CBZ', NAMES.read, '@tap-centre', named('reader_menu')]],
    ['Comic reader > pages', [NAMES.library, ', CBZ', NAMES.read, '@tap-centre', named('reader_menu'), named('reader_menu_contents')]],
    ['Comic reader > adjustments', [NAMES.library, ', CBZ', NAMES.read, '@tap-centre', named('reader_menu'), named('reader_menu_themes')]],
    // The outer edge of the width turns a page, so four taps there run off the end of a
    // three-page fixture and land on the finished screen.
    ['Comic reader > end', [NAMES.library, ', CBZ', NAMES.read, '@tap 0.95,0.5', '@tap 0.95,0.5', '@tap 0.95,0.5', '@tap 0.95,0.5']],
    ['Comic reader > bad page', [NAMES.library, 'Foreign Codec', NAMES.read]],

    // --- The EPUB reader, which is a second activity ---------------------------------
    // Reversed from what the comic reader needs. The EPUB reader opens with its chrome up
    // and keeps it there, so the chrome shot is the plain arrival and the *page* shot is
    // the one that needs a tap -- which hides it. Photographed the other way round, the
    // file named `chrome` held a page and the file named `page` held the chrome.
    ['EPUB reader > chrome', [NAMES.library, 'Harbour Lights 01', NAMES.read]],
    ['EPUB reader > menu', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu')]],
    ['EPUB reader > themes', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_themes')]],
    // The preset sheet opens at its smaller detent; the second one is a drag, not a tap.
    ['EPUB reader > themes expanded', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_themes'), '@drag-sheet-up']],
    ['EPUB reader > axes', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_themes'), named('theme_customise')]],
    ['EPUB reader > contents', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_contents')]],
    ['EPUB reader > bookmarks', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_bookmarks')]],
    ['EPUB reader > search', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_search')]],
    ['EPUB reader > search typed', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('reader_menu_search'), '@type the']],
    ['EPUB reader > notes', [NAMES.library, 'Harbour Lights 01', NAMES.read, named('epub_menu'), named('annotations_title')]],

    // --- Search ----------------------------------------------------------------------
    // The bar at rest is the `Search` route above. Tapping it is a second condition, and
    // the note on that route says this table had no vocabulary for it. Now it does.
    ['Search > expanded', [NAMES.search, named('library_search')]],
    ['Search > mid query', [NAMES.search, named('library_search'), '@type harb']],
    ['Search > no results', [NAMES.search, named('library_search'), '@type zzzqqq']],
    ['Search > on this device', [NAMES.search, named('source_on_this_device')]],
    ['Search > add source menu', [NAMES.search, named('library_add_source')]],

    // --- Downloads -------------------------------------------------------------------
    ['Downloads > remove dialog', [NAMES.downloads, '@long Bright Panels', named('downloads_remove_action')]],
    // The undo bar lasts a few seconds, so the removal itself is the last thing done.
    ['Downloads > undo', [NAMES.downloads, '@long Bright Panels', named('downloads_remove_action'), '!' + named('downloads_remove')]],

    // --- Shelves ---------------------------------------------------------------------
    ['Shelves', [NAMES.library, NAMES.more, named('shelves_title')]],
    ['Shelves > new menu', [NAMES.library, NAMES.more, named('shelves_title'), named('shelves_new')]],
    ['Shelves > create dialog', [NAMES.library, NAMES.more, named('shelves_title'), named('shelves_new'), named('shelves_new_collection')]],

    // --- Settings: the states the seven groups can be in -----------------------------
    ['Settings > reset dialog', [NAMES.library, NAMES.more, NAMES.settings, named('settings_reset')]],
    ['Settings > search results', [NAMES.library, NAMES.more, NAMES.settings, named('settings_search'), '@type icon']],
    ['Settings > search empty', [NAMES.library, NAMES.more, NAMES.settings, named('settings_search'), '@type zzzqqq']],
    ['Settings > app icon', [NAMES.library, NAMES.more, NAMES.settings, NAMES.appearance, '@swipe-up', '@swipe-up']],
    ['Settings > Reading defaults', [NAMES.library, NAMES.more, NAMES.settings, NAMES.reading, '@swipe-up', '@swipe-up']],
    ['Settings > Privacy diagnostic', [NAMES.library, NAMES.more, NAMES.settings, NAMES.privacy, named('privacy_diagnostic_show')]],
    ['Settings > Privacy clear history', [NAMES.library, NAMES.more, NAMES.settings, NAMES.privacy, named('privacy_clear_history')]],
    ['Settings > About acknowledgements', [NAMES.library, NAMES.more, NAMES.settings, NAMES.about, '@swipe-up', '@swipe-up']],

    // --- Reachable only once an audiobook is in the library --------------------------
    // Android's player is a destination rather than a sheet, on purpose:
    // `named-failures-and-quieter-chrome` section 3.3 records the divergence.
    ['Audiobook page', [NAMES.library, 'Audiobook folder|, M4B']],
    ['Player', [NAMES.library, 'Audiobook folder|, M4B', NAMES.read]],
    ['Player > chapters', [NAMES.library, 'Audiobook folder|, M4B', NAMES.read, '@swipe-up', '@swipe-up']],
    ['Player > compact bar', [NAMES.library, 'Audiobook folder|, M4B', NAMES.read, named('player_play'), NAMES.home]],

    // --- Reachable only once a source list is not empty ------------------------------
    ['Settings > source detail', [NAMES.library, NAMES.more, NAMES.settings, NAMES.sources, 'Audiobooks']],
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
/**
 * Where a scroll starts and ends, as a fraction of the window.
 *
 * **Both used to be inside the chrome on a short window, and a route that needed to scroll
 * there reported a working screen as unreachable.** At 800 x 360 dp the navigation bar and
 * its gesture inset are the bottom 88 dp — a quarter of the window — so a swipe beginning at
 * 0.78 began inside it and moved nothing; the old target of 0.33 was inside the app bar for
 * the same reason. Six attempts of a gesture that cannot touch the content is what the
 * September sweep recorded as "six scroll attempts moved nothing" on the publication page.
 *
 * These two clear both bands at every window this app supports and still travel far enough
 * on a tall one: on a 2400 px phone they are a 960 px drag, and on a 1080 px landscape
 * window a 432 px one that starts 60 px above the navigation bar.
 */
const SCROLL_FROM = 0.70
const SCROLL_TO = 0.30

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

    const swipe = ([x1, y1], [x2, y2], ms = 260) => {
        sh('shell', 'input', 'swipe', String(x1), String(y1), String(x2), String(y2), String(ms))
        sleep(1200)
    }

    /**
     * The window, in pixels, as the device reports it.
     *
     * Asked for rather than assumed because this sweep varies it. `wm size` prints
     * `Physical size: 1080x2400` and, once overridden, an `Override size:` line as well —
     * the override is the one the app is laid out in, so the *last* match wins. Every
     * coordinate below is a fraction of this, which is the difference between a step that
     * survives `wm size 1280x576` and one that taps 260 pixels past the right edge. The
     * old `@tap-centre` was the literal pair `540, 1200`; at the large breakpoint that is
     * off-screen, and an off-screen tap does nothing and reports nothing.
     */
    const window = () => {
        // `app=2400x1080` in the display dump is the rectangle the app is actually laid out
        // in: it carries the density override *and* the rotation. `wm size` carries neither
        // — it answers `Physical size: 1080x2400` in landscape as well, so a centre tap
        // computed from it lands 1300 pixels below a rotated screen, does nothing, and
        // reports nothing.
        const app = /\bapp=(\d+)x(\d+)/.exec(sh('shell', 'dumpsys', 'window', 'displays'))
        if (app) return [Number(app[1]), Number(app[2])]
        const sizes = [...sh('shell', 'wm', 'size').matchAll(/(\d+)x(\d+)/g)]
        const last = sizes.at(-1)
        return last ? [Number(last[1]), Number(last[2])] : [1080, 2400]
    }

    /** A fresh launch, so no route depends on where the previous one left the app. */
    const launch = () => {
        sh('shell', 'am', 'force-stop', PKG)
        sh('shell', 'am', 'start', '-n', ACTIVITY)
        sleep(3500)
    }

    /**
     * Performs a list of steps on the app as it stands. Returns the step it could not
     * reach, or null.
     *
     * Scrolls and retries before giving up: a control below the fold is present and simply
     * not on screen, and reporting that as unreachable is how this reported a working app
     * as broken.
     */
    const perform = (steps) => {
        const [width, height] = window()
        // A fraction of the window, so one step reads the same at 360 dp and at 1280 dp.
        const at = (fx, fy) => [Math.round(width * fx), Math.round(height * fy)]

        /**
         * A step that is a gesture rather than a name, or null when the step is a name.
         *
         * Selection mode, a typed query, the second level of a sheet and the state left
         * behind by a Back are all real conditions of this app, and none of them is a tap on
         * a named control. Driving them from the shell instead put coordinates in a
         * screenshot log, where they are correct exactly once — the day the layout moves,
         * the picture is of the wrong thing and nothing says so. A named route is
         * repeatable; a coordinate is a claim about a layout.
         */
        const gesture = (step) => {
            const [verb, argument = ''] = step.split(/\s+(.*)/s)
            switch (verb) {
                // Revealing the reader chrome is a tap on the page, not on a named control.
                case '@tap-centre':
                    return () => tap(...at(0.5, 0.5))
                // `@tap 0.5,0.86` — the last resort, and it says which corner it means.
                case '@tap':
                    return () => tap(...at(...argument.split(',').map(Number)))
                case '@back':
                    return () => {
                        sh('shell', 'input', 'keyevent', 'KEYCODE_BACK')
                        sleep(1700)
                    }
                // The soft keyboard is already up: the step before this one focused a field.
                case '@type':
                    return () => {
                        sh('shell', 'input', 'text', argument.replaceAll(' ', '%s'))
                        sleep(2000)
                    }
                // A press held long enough to mean "select", which is how this app's
                // selection mode opens and the only way in.
                case '@long':
                    return () => {
                        const spot = centre(dump(), argument)
                        if (!spot) return false
                        sh('shell', 'input', 'swipe', String(spot[0]), String(spot[1]), String(spot[0]), String(spot[1]), '800')
                        sleep(1700)
                        return true
                    }
                case '@swipe-up':
                    return () => swipe(at(0.5, SCROLL_FROM), at(0.5, SCROLL_TO))
                case '@swipe-down':
                    return () => swipe(at(0.5, SCROLL_TO), at(0.5, SCROLL_FROM))
                // A sheet that opens at one detent and has a second one is dragged, not tapped.
                case '@drag-sheet-up':
                    return () => swipe(at(0.5, 0.55), at(0.5, 0.12), 500)
                case '@wait':
                    return () => sleep(2500)
                default:
                    return null
            }
        }

        for (const raw of steps) {
            const act = gesture(raw)
            if (act) {
                // A gesture that had to find something may fail, and then the route failed.
                if (act() === false) return raw
                continue
            }
            // `?Name` is a step that may legitimately not be there — a one-time notice, a
            // control that only appears once something is downloaded. Absent is not a
            // failure; carrying on and photographing the screen behind it would be.
            const optional = raw.startsWith('?')
            const step = optional ? raw.slice(1) : raw
            // Any one of the alternatives will do, and each is tried against the same
            // tree before scrolling: a page offering *Continue* is not a page missing *Read*.
            const wanted = step.split('|')
            let spot = null
            // Six scrolls rather than three. At `font_scale 2.0` a shelf shows roughly half
            // as many cells, so a cover three rows down at the default size is six rows down
            // there — and the walk gave up at three and called a present control missing.
            for (let attempt = 0; attempt < (optional ? 1 : 6) && !spot; attempt += 1) {
                const tree = dump()
                for (const name of wanted) {
                    spot = centre(tree, name)
                    if (spot) break
                }
                if (!spot && !optional) swipe(at(0.5, SCROLL_FROM), at(0.5, SCROLL_TO))
            }
            if (!spot) {
                if (optional) continue
                return step
            }
            tap(...spot)
        }
        return null
    }

    /** A fresh launch, then the whole route. What the crash walk and the a11y scan want. */
    const walk = (steps) => {
        launch()
        return perform(steps)
    }

    return { dump, tap, launch, walk, perform, window }
}

/**
 * A route split at its first `!` step, into what may be done early and what may not.
 *
 * Some conditions perish. The comic reader's chrome hides itself four seconds after the
 * tap that revealed it (`CHROME_TIMEOUT_MILLIS` in `ReaderScreen.kt`), and an undo bar
 * goes the same way. `capture-android.mjs` spends about four seconds between the last
 * step and the shutter — a `uiautomator` read to prove the screen drew, then a settle —
 * so the committed `Comic reader > chrome` route lost that race and filed a picture of a
 * bare page under a name that says chrome. Nothing failed; the file was simply wrong,
 * which is the one failure this whole harness exists to prevent.
 *
 * So a route may mark its last steps `!`, and the capture does them *after* it has
 * proved the screen drew, immediately before the shutter. A walk that only asks whether
 * the screen crashed does not care and runs the lot in order.
 */
export function splitLate(steps) {
    const at = steps.findIndex((step) => step.startsWith('!'))
    if (at === -1) return [steps, []]
    return [steps.slice(0, at), steps.slice(at).map((step) => step.slice(1))]
}
