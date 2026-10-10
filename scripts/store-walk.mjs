#!/usr/bin/env node
/**
 * The store screenshot walk, as data: the frames, the device buckets, the words each step
 * taps, the output paths and the rules of both stores. Nothing here touches a device.
 * `store-capture.mjs` drives the devices with it, and `--self-test` checks it.
 *
 * Usage: node scripts/store-walk.mjs --self-test
 */
import { closeSync, existsSync, openSync, readFileSync, readSync, readdirSync, statSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { namedIn } from './android-routes.mjs'
import { png } from './png.mjs'
import { SHOWCASE } from './store-showcase.mjs'

export const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
export const OUT = join(ROOT, '.build/store')

/** The four languages the apps ship, and the folder name both stores give each one. */
export const LOCALES = { en: 'en-US', de: 'de-DE', es: 'es-ES', fr: 'fr-FR' }

/** The six frames, in the order the listing shows them. */
export const FRAMES = [
  { id: '01', name: 'library' },
  { id: '02', name: 'publication' },
  { id: '03', name: 'comic-reader' },
  { id: '04', name: 'reading-themes' },
  { id: '05', name: 'audiobook-player' },
  { id: '06', name: 'home' },
]

/**
 * Play's three screenshot slots, all from one emulator.
 *
 * A Compose layout changes with the window in dp, and `wm size` and `wm density` set that
 * directly. Each size is exactly 9:16: Play refuses 1080x2400, the size of every stock
 * phone AVD in this SDK.
 *
 * `split` marks a library drawn beside an empty detail pane.
 */
export const ANDROID_BUCKETS = {
  phone: { size: [1080, 1920], density: 420, folder: 'phoneScreenshots', min: 320, max: 3840 },
  tablet7: { size: [1080, 1920], density: 280, folder: 'sevenInchScreenshots', min: 320, max: 3840 },
  tablet10: { size: [1440, 2560], density: 240, folder: 'tenInchScreenshots', min: 1080, max: 7680, split: true },
}

/**
 * App Store Connect's two slots. Each size is a simulator's native resolution.
 *
 * `menuRow` is where the EPUB reader's menu sheet draws *Reading themes*, as a fraction of
 * the screen. The walk taps it by position because agent-device 0.21.22 does not see that
 * sheet in its accessibility snapshot (the sheet sits over the Readium view), so no
 * selector can reach the row. `split` means what it means for Play.
 */
export const IOS_BUCKETS = {
  'iphone-6.9': { device: 'iPhone 17 Pro Max', size: [1320, 2868], scale: 3, menuRow: [0.33, 0.949] },
  'ipad-13': { device: 'iPad Pro 13-inch', size: [2064, 2752], scale: 2, menuRow: [0.35, 0.779], split: true },
}

/** The corpus files that make a tidy shelf. The refusal fixtures stay out of a listing. */
const CORPUS_FILES = [
  'Bright Panels.epub', 'Field Notes.pdf', 'Fine Print.cbz', 'Glasshouse.epub',
  'Harbour Lights 01.epub', 'Harbour Lights 02.epub', 'Paper Lanterns.cbt', 'Quiet Machines.cbz',
  'Salt and Iron', 'Sea Room.m4b', 'The Long Field.epub', 'Tidal Reach 01.cbz',
  'Tidal Reach 02.cbz', 'Tidal Reach 03.cbz',
]

/**
 * What each frame opens, per library. `landmark` is words that the first screen of the
 * shelf shows at every size. `comicTurns` and `ebookTurns` are page turns before
 * the frame: page 2 of *The Boys #1* is its cast page, and the third turn in the Laura
 * Palmer EPUB shows the first page of its foreword. On the 10-inch window and the iPad,
 * Readium sets two columns and one turn moves two pages. There a fourth turn shows the
 * short last page of a letter: one column of text and three empty quarters.
 */
export const LIBRARIES = {
  showcase: {
    folder: 'Showcase',
    files: SHOWCASE.map((item) => item.as),
    landmark: 'The Boys',
    series: 'The Boys',
    comic: 'The Boys #1',
    comicTurns: 1,
    ebook: 'The Secret Diary of Laura Palmer',
    ebookTurns: 3,
    audiobook: 'Dungeon Crawler Carl',
  },
  corpus: {
    folder: 'Corpus',
    files: CORPUS_FILES,
    landmark: 'Bright Panels',
    series: null,
    comic: 'Quiet Machines',
    comicTurns: 2,
    ebook: 'The Long Field',
    ebookTurns: 1,
    audiobook: 'Sea Room',
  },
}

// ---------------------------------------------------------------------------------------
// The app's own words. A renamed key fails here, by name, before a device boots.
// ---------------------------------------------------------------------------------------

/** Android: resource names, read through `namedIn()` in `android-routes.mjs`. */
const ANDROID_KEYS = {
  home: ['destination_home'],
  keepReading: ['home_keep_reading'],
  library: ['destination_library'],
  read: ['detail_action_read', 'detail_action_continue'],
  listen: ['detail_action_listen', 'detail_action_continue_listening'],
  menu: ['reader_menu'],
  close: ['reader_close'],
  epubMenu: ['epub_menu'],
  themes: ['reader_menu_themes'],
  presets: ['theme_presets'],
  pause: ['player_pause'],
  play: ['player_play'],
}

/** iOS: `<table>:<key>`, where the table is the folder that owns `Resources/Localizable.xcstrings`. */
const IOS_KEYS = {
  home: ['App:tab.home'],
  keepReading: ['LibraryFeature:library.continueReading'],
  library: ['App:tab.library'],
  read: ['LibraryFeature:catalogue.detail.read', 'LibraryFeature:library.continueReading'],
  listen: ['LibraryFeature:detail.listen', 'LibraryFeature:detail.continueListening'],
  menu: ['ReaderFeature:reader.menu'],
  close: ['ReaderFeature:reader.close'],
  epubMenu: ['EpubReaderFeature:epub.menu'],
  pause: ['PlayerFeature:player.pause'],
  play: ['PlayerFeature:player.play'],
  openPlayer: ['PlayerFeature:player.open'],
  speed: ['PlayerFeature:player.speed'],
}

let catalogues = null

/** Every `.xcstrings` under `apps/ios`, by table name, read once. */
function iosCatalogues() {
  if (catalogues) return catalogues
  catalogues = new Map()
  const walkDir = (at) => {
    for (const entry of readdirSync(at, { withFileTypes: true })) {
      const path = join(at, entry.name)
      if (entry.isDirectory() && entry.name !== 'build' && entry.name !== '.build') walkDir(path)
      else if (entry.name === 'Localizable.xcstrings') {
        catalogues.set(basename(dirname(dirname(path))), JSON.parse(readFileSync(path, 'utf8')))
      }
    }
  }
  walkDir(join(ROOT, 'apps/ios'))
  return catalogues
}

/** One iOS key's words in one language. Throws on a missing table, key or translation. */
export function iosWords(spec, locale) {
  const [table, key] = spec.split(':')
  const value = iosCatalogues().get(table)?.strings?.[key]?.localizations?.[locale]?.stringUnit?.value
  if (!value) throw new Error(`No "${key}" in ${locale} in apps/ios/**/${table}/Resources/Localizable.xcstrings.`)
  return value
}

/** Every label the walk taps, in one language, as lists of words. */
export function labels(platform, locale) {
  const keys = platform === 'ios' ? IOS_KEYS : ANDROID_KEYS
  const lookup = platform === 'ios'
    ? (spec) => [iosWords(spec, locale)]
    : (name) => namedIn(name, locale)
  return Object.fromEntries(Object.entries(keys).map(([name, specs]) => [
    name, [...new Set(specs.flatMap(lookup))],
  ]))
}

/** An agent-device selector for any of these words. iOS names the role: a label repeats. */
export function selector(platform, words) {
  const role = platform === 'ios' ? 'role=button ' : ''
  return words.map((word) => `${role}label="${word.replaceAll('"', '\\"')}"`).join(' || ')
}

// ---------------------------------------------------------------------------------------
// The walk.
// ---------------------------------------------------------------------------------------

/**
 * The walk for one device and one language, as one list of steps.
 *
 * Frames 01 to 04 follow one path. The app then starts again: the iOS themes sheet is not in
 * the accessibility snapshot, so no step can close it, and the agent-device runner refused
 * steps for seconds after it. Frame 05 opens the audiobook, and frame 06 is Home, whose
 * *Continue reading* holds the comic, the ebook and the audiobook that the walk opened.
 *
 * Each chunk is one frame: the steps that reach it and take it, what it `needs` (the chunks
 * that must run first; the walk goes on from the screen of the last one when it is the
 * chunk just before), and the `exit` to a screen with the tab bar. A chunk runs when its
 * frame is selected or when a selected chunk needs it. Steps after the last selected frame
 * do not run.
 *
 * Step kinds: `tap` (find a node by its words and press its centre; when absent, `scroll`),
 * `press` (a selector), `point` (a fraction of the screen), `wait`, `waitAbsent`,
 * `waitText`, `reveal` (show the reader chrome when it is hidden), `until` (press until a
 * selector shows), `scroll`, `swipe`, `stable` (the screen stops moving), `relaunch` (start
 * the app again), `pause` (a fixed wait, only with a `why`) and `shot`.
 */
export function walk({ platform, bucket, library: lib, labels: L, frames }) {
  const ios = platform === 'ios'
  const s = (name) => selector(platform, L[name])
  // A cold device can take a while to draw the first screen after a launch.
  const launched = { wait: s('library'), timeoutMs: 60000 }
  const toLibrary = [{ tap: L.library, exact: true }]
  const turns = (count) => Array.from({ length: count }, () => ({ point: [0.93, 0.5], settle: true }))
  const themes = ios
    ? [
        { pause: 1000, why: 'the menu sheet is not in the accessibility snapshot' },
        { point: bucket.menuRow },
        { pause: 3000, why: 'the themes sheet and its preview are not in the accessibility snapshot' },
      ]
    // On a phone the themes sheet stays at its small detent, the one height that leaves the
    // page in view. A wider window draws a popover beside the page. The live preview reads
    // the page's own words a moment after the sheet opens.
    : [{ tap: L.themes, exact: true, scroll: true, settle: true }, { waitText: L.presets[0] }, { stable: true }]
  const chunks = [
    {
      id: '01',
      needs: [],
      steps: [
        ...toLibrary, { waitText: lib.landmark },
        // A wide library draws an empty pane beside the shelf until a cover is chosen.
        ...(bucket.split ? [{ tap: `${lib.audiobook},`, scroll: true }, { wait: s('listen') }, { stable: true }] : []),
        { shot: '01' },
      ],
      exit: [],
    },
    {
      id: '02',
      needs: ['01'],
      steps: [
        ...(lib.series ? [{ tap: `${lib.series},`, scroll: true }, { waitText: lib.comic }] : []),
        { tap: `${lib.comic},`, scroll: true }, { wait: s('read') }, { shot: '02' },
      ],
      exit: [],
    },
    {
      id: '03',
      needs: ['02'],
      steps: [
        // The reader opens with its chrome up, and a tap in the middle toggles it. The walk
        // hides it, turns the page, and shows it again: the frame is then taken inside the
        // few seconds before the chrome hides itself. A turn can leave the chrome on its way
        // out, and a plain tap then hid it in one English iPad frame, so `reveal` shows it.
        { press: s('read') }, { wait: s('menu') }, { point: [0.5, 0.5] }, { waitAbsent: s('menu') },
        ...turns(lib.comicTurns), { reveal: s('menu') }, { shot: '03' },
      ],
      exit: [{ reveal: s('close') }, { press: s('close') }],
    },
    {
      id: '04',
      needs: [],
      steps: [
        ...toLibrary, { tap: `${lib.ebook},`, scroll: true }, { wait: s('read') }, { press: s('read') },
        // The iOS reader shows its chrome about two seconds before it draws the book, under a
        // spinner, and a turn in that time is lost.
        { wait: s('epubMenu') }, ...(ios ? [{ waitAbsent: 'role=activity-indicator' }] : []), ...turns(lib.ebookTurns), { reveal: s('epubMenu') }, { press: s('epubMenu') },
        ...themes, { shot: '04' },
      ],
      exit: [{ relaunch: true }, launched],
    },
    {
      id: '05',
      needs: [],
      steps: [
        ...toLibrary, { tap: `${lib.audiobook},`, scroll: true }, { wait: s('listen') }, { press: s('listen') },
        // The player starts on its own. A press on Pause while it still prepares does
        // nothing, so the step presses until Play shows.
        { wait: s('pause') }, { until: s('play'), press: s('pause') },
        ...(ios ? [{ press: s('openPlayer') }, { wait: s('speed') }] : []),
        { shot: '05' },
      ],
      exit: [],
    },
    {
      id: '06',
      needs: ['03', '04', '05'],
      steps: [
        // The iOS player is a sheet over the tab bar, and a drag down closes it. Android
        // draws its navigation beside the player.
        ...(ios ? [{ swipe: [[0.5, 0.3], [0.5, 0.95]] }, { waitAbsent: s('speed') }] : []),
        { tap: L.home, exact: true }, { waitText: L.keepReading[0] }, { stable: true }, { shot: '06' },
      ],
      exit: [],
    },
  ]
  return [launched, ...assemble(chunks, frames)]
}

/** The steps of the chunks a selection needs, in order, cut after the last selected shot. */
function assemble(chunks, frames) {
  const included = new Set()
  for (let at = chunks.length - 1; at >= 0; at -= 1) {
    const chunk = chunks[at]
    if (frames.includes(chunk.id) || included.has(chunk.id)) {
      included.add(chunk.id)
      for (const id of chunk.needs) included.add(id)
    }
  }
  const order = chunks.filter((chunk) => included.has(chunk.id))
  const steps = []
  order.forEach((chunk, at) => {
    steps.push(...chunk.steps.filter((step) => !step.shot || frames.includes(step.shot)))
    const next = order[at + 1]
    if (next && !next.needs.includes(chunk.id)) steps.push(...chunk.exit)
  })
  const last = steps.findLastIndex((step) => step.shot)
  return last === -1 ? [] : steps.slice(0, last + 1)
}

// ---------------------------------------------------------------------------------------
// Where the files go: fastlane's layouts, so an upload is one command.
// ---------------------------------------------------------------------------------------

export function shotPath(platform, bucketName, locale, frameId) {
  const frame = FRAMES.find((f) => f.id === frameId)
  const store = LOCALES[locale]
  return platform === 'android'
    ? join(OUT, 'play', store, 'images', ANDROID_BUCKETS[bucketName].folder, `${frame.id}-${frame.name}.png`)
    : join(OUT, 'appstore', store, `${frame.id}-${frame.name}-${bucketName}.png`)
}

export const graphicPath = (locale, file) => join(OUT, 'play', LOCALES[locale], 'images', file)

// ---------------------------------------------------------------------------------------
// The stores' rules.
// ---------------------------------------------------------------------------------------

/** A PNG's pixel size, from its IHDR. */
export function pngSize(head) {
  if (head.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error('not a PNG')
  return [head.readUInt32BE(16), head.readUInt32BE(20)]
}

export function pngFileSize(file) {
  const fd = openSync(file, 'r')
  try {
    const head = Buffer.alloc(24)
    readSync(fd, head, 0, 24, 0)
    return pngSize(head)
  } finally {
    closeSync(fd)
  }
}

/** Why Play refuses a screenshot: 9:16 or 16:9 to a pixel, sides in range, 8 MB at most. */
export function playProblems([width, height], bytes, bucket) {
  const problems = []
  const ratio = width / height
  if (Math.abs(ratio - 9 / 16) > 0.002 && Math.abs(ratio - 16 / 9) > 0.002) problems.push(`${width}x${height} is not 9:16`)
  for (const side of [width, height]) {
    if (side < bucket.min || side > bucket.max) problems.push(`${side} px is outside ${bucket.min}-${bucket.max} px`)
  }
  if (bytes > 8 << 20) problems.push(`${(bytes / (1 << 20)).toFixed(1)} MB is over 8 MB`)
  return problems
}

/** Why App Store Connect refuses a screenshot: the slot takes one size. */
export function appStoreProblems([width, height], bucket) {
  const [w, h] = bucket.size
  return width === w && height === h ? [] : [`${width}x${height}, the slot takes ${w}x${h}`]
}

export const PLAY_TEXT = { 'App name': 30, 'Short description': 80, 'Full description': 4000 }
export const APP_STORE_TEXT = { 'App name': 30, Subtitle: 30, 'Promotional text': 170, Keywords: 100, Description: 4000 }

/** The fenced value under one `## ` heading of a listing file. */
export function section(markdown, heading) {
  const at = markdown.indexOf(`\n## ${heading}\n`)
  if (at === -1) return null
  const body = markdown.slice(at + heading.length + 5)
  const open = body.indexOf('```')
  const close = open === -1 ? -1 : body.indexOf('```', open + 3)
  if (close === -1) return null
  return body.slice(body.indexOf('\n', open) + 1, close).trim()
}

export function textProblems(markdown, limits) {
  return Object.entries(limits).flatMap(([heading, limit]) => {
    const value = section(markdown, heading)
    if (value === null) return [`no "## ${heading}" with a fenced value`]
    return value.length > limit ? [`${heading} is ${value.length} characters, limit ${limit}`] : []
  })
}

/** Every asset a selection should have produced, checked against its store. */
export function verify({ locales, frames, androidBuckets, iosBuckets }) {
  const failures = []
  let counted = 0
  const check = (file, problemsOf) => {
    const name = file.slice(OUT.length + 1)
    if (!existsSync(file)) return failures.push(`${name} is missing`)
    counted += 1
    for (const problem of problemsOf(pngFileSize(file), statSync(file).size)) failures.push(`${name}: ${problem}`)
  }
  for (const locale of locales) {
    for (const frame of frames) {
      for (const name of androidBuckets) check(shotPath('android', name, locale, frame), (size, bytes) => playProblems(size, bytes, ANDROID_BUCKETS[name]))
      for (const name of iosBuckets) check(shotPath('ios', name, locale, frame), (size) => appStoreProblems(size, IOS_BUCKETS[name]))
    }
    if (androidBuckets.length > 0) {
      check(graphicPath(locale, 'featureGraphic.png'), ([w, h], bytes) => (w === 1024 && h === 500 && bytes <= 15 << 20 ? [] : [`${w}x${h}, ${bytes} bytes: Play wants 1024x500, 15 MB at most`]))
      check(graphicPath(locale, 'icon.png'), ([w, h], bytes) => (w === 512 && h === 512 && bytes <= 1 << 20 ? [] : [`${w}x${h}, ${bytes} bytes: Play wants 512x512, 1 MB at most`]))
    }
    for (const [store, limits] of [['android', PLAY_TEXT], ['ios', APP_STORE_TEXT]]) {
      const file = join(ROOT, `docs/designs/store/${store}/listing/${locale}.md`)
      counted += 1
      if (!existsSync(file)) failures.push(`docs/designs/store/${store}/listing/${locale}.md is missing`)
      else for (const problem of textProblems(readFileSync(file, 'utf8'), limits)) failures.push(`${store}/listing/${locale}.md: ${problem}`)
    }
  }
  if (iosBuckets.length > 0) {
    const icon = join(ROOT, 'apps/ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
    counted += 1
    if (!existsSync(icon)) failures.push('the App Store icon AppIcon-1024.png is missing: run pnpm brand:build')
    else if (pngFileSize(icon).join('x') !== '1024x1024') failures.push('the App Store icon is not 1024x1024')
  }
  return { counted, failures }
}

// ---------------------------------------------------------------------------------------
// Self-test: each check is a rule that a mutation of the code above makes fail.
// ---------------------------------------------------------------------------------------

function selfTest() {
  const all = FRAMES.map((f) => f.id)
  const shots = (steps) => steps.filter((st) => st.shot).map((st) => st.shot)
  const taps = (steps, words) => steps.some((st) => st.tap === words)
  const context = (platform, frames) => ({
    platform,
    bucket: platform === 'ios' ? IOS_BUCKETS['iphone-6.9'] : ANDROID_BUCKETS.phone,
    library: LIBRARIES.showcase,
    labels: labels(platform, 'de'),
    frames,
  })
  const throws = (fn) => { try { fn(); return false } catch { return true } }
  const checks = [
    ['every Play bucket passes Play', () => Object.values(ANDROID_BUCKETS).every((b) => playProblems(b.size, 1, b).length === 0)],
    ['Play refuses 1080x2400', () => playProblems([1080, 2400], 1, ANDROID_BUCKETS.phone).length > 0],
    ['Play refuses a 9 MB file', () => playProblems([1080, 1920], 9 << 20, ANDROID_BUCKETS.phone).length > 0],
    ['each iOS slot is whole points at its scale', () => Object.values(IOS_BUCKETS).every((b) => b.size.every((side) => side % b.scale === 0))],
    ['the App Store refuses a frame of the wrong size', () => appStoreProblems([1290, 2796], IOS_BUCKETS['iphone-6.9']).length > 0],
    ['every label resolves in every language', () => Object.keys(LOCALES).every((l) => ['ios', 'android'].every((p) => Object.values(labels(p, l)).every((w) => w.length > 0)))],
    ['a missing iOS key fails by name', () => throws(() => iosWords('App:no.such.key', 'en'))],
    ['a missing Android key fails by name', () => throws(() => namedIn('no_such_key', 'en'))],
    ['German labels are German', () => labels('ios', 'de').library[0] === 'Bibliothek' && labels('android', 'de').library[0] === 'Bibliothek'],
    ['an iOS selector names the button role', () => selector('ios', ['A', 'B']) === 'role=button label="A" || role=button label="B"'],
    ['Play layout', () => shotPath('android', 'tablet7', 'de', '01') === join(OUT, 'play/de-DE/images/sevenInchScreenshots/01-library.png')],
    ['App Store layout', () => shotPath('ios', 'ipad-13', 'fr', '04') === join(OUT, 'appstore/fr-FR/04-reading-themes-ipad-13.png')],
    ['all frames: six shots in order', () => ['ios', 'android'].every((p) => shots(walk(context(p, all))).join() === '01,02,03,04,05,06')],
    ['one frame: one shot', () => shots(walk(context('android', ['03']))).join() === '03'],
    ['frame 03 alone walks through 01 and 02', () => taps(walk(context('android', ['03'])), 'The Boys #1,')],
    ['frame 04 alone skips the comic', () => !taps(walk(context('ios', ['04'])), 'The Boys #1,')],
    ['frame 05 alone skips the comic and the ebook', () => { const w = walk(context('ios', ['05'])); return !taps(w, 'The Boys #1,') && !taps(w, 'The Secret Diary of Laura Palmer,') }],
    ['frame 06 alone opens all three first', () => { const w = walk(context('android', ['06'])); return shots(w).join() === '06' && ['The Boys #1,', 'The Secret Diary of Laura Palmer,', 'Dungeon Crawler Carl,'].every((t) => taps(w, t)) }],
    ['the walk starts the app again after the ebook', () => ['ios', 'android'].every((p) => walk(context(p, ['04', '05'])).some((st) => st.relaunch))],
    ['the walk ends at its last shot', () => walk(context('android', ['01'])).at(-1).shot === '01'],
    ['a frame after the comic leaves the reader', () => walk(context('android', ['03', '04'])).some((st) => st.press === selector('android', labels('android', 'de').close))],
    ['a fixed wait carries its reason', () => ['ios', 'android'].every((p) => walk(context(p, all)).every((st) => !st.pause || st.why))],
    ['a listing heading is read', () => section('x\n## Subtitle\n\n```\nRead it all\n```\n', 'Subtitle') === 'Read it all'],
    ['an over-long field fails', () => textProblems('\n## App name\n```\n' + 'x'.repeat(31) + '\n```\n', { 'App name': 30 }).length === 1],
    ['a PNG header is measured', () => pngSize(png(7, 3, [0, 0, 0])).join('x') === '7x3'],
  ]
  let failed = 0
  for (const [name, check] of checks) {
    let ok = false
    try { ok = check() } catch (error) { console.error(`  ${name}: ${error.message}`) }
    if (!ok) { failed += 1; console.error(`FAIL ${name}`) }
  }
  console.log(`store-walk self-test: ${checks.length - failed}/${checks.length} checks passed`)
  process.exit(failed === 0 ? 0 : 1)
}

if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv.includes('--self-test')) selfTest()
