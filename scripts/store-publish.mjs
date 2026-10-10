#!/usr/bin/env node
// Updates the store listings from files on this Mac. It never talks to a store itself.
//
// Usage: pnpm store:publish                       Play: check, zip, send, ask CI to VALIDATE
//        pnpm store:publish --dry                 Play: check and zip only, no network
//        pnpm store:publish --publish             Play: the same, then CI WRITES the live listing
//        pnpm store:publish --track alpha         Play: name a track that holds a release (default internal)
//        pnpm store:publish --platform appstore   App Store: check and zip, then stop
//        pnpm store:publish --platform appstore --upload   ...then send it and ask CI to upload
//        pnpm store:publish --self-test           the pure parts, no network
//
// **Where the inputs come from.** Texts: `docs/designs/store/{android,ios}/listing/*.md`.
// Images: `.build/store/play/<locale>/images/` (fastlane supply layout) and
// `.build/store/appstore/<locale>/*.png`. The screenshot run writes the images.
//
// **What it does.** Checks every text against the store's limit and every image against
// the store's size rules, and refuses with the full list before it writes or sends anything.
// Then it writes the fastlane layout, zips it (`.build/store/play.zip`, `appstore.zip`),
// attaches the zip to the DRAFT release `store-assets`, and starts `android-listing.yml` or
// `ios-listing.yml`. The store keys are repository secrets and never come to this Mac, so
// the upload runs in CI.
//
// **Validate is the default.** Play checks the listing and changes nothing. Apple has no
// such mode for metadata, so the App Store workflow only proves that the key works until
// `--upload` is given. A real update is the owner's decision (AGENTS.md section 10).

import { execFileSync } from 'node:child_process'
import {
  closeSync, copyFileSync, existsSync, mkdirSync, openSync, readFileSync, readSync,
  readdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs'
import { basename, dirname, join, relative } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const STORE = join(ROOT, '.build/store')
const LISTING = join(ROOT, 'docs/designs/store')
const RELEASE = 'store-assets'
const WORKFLOW = { play: 'android-listing.yml', appstore: 'ios-listing.yml' }

/** The listing file name stem, and the locale folder both stores and fastlane use for it. */
export const LOCALES = { en: 'en-US', de: 'de-DE', es: 'es-ES', fr: 'fr-FR' }

/** One listing field: the `## ` heading in the md, the fastlane file stem, the store's limit. */
export const PLAY_TEXTS = [
  { heading: 'App name', file: 'title', limit: 30 },
  { heading: 'Short description', file: 'short_description', limit: 80 },
  { heading: 'Full description', file: 'full_description', limit: 4000 },
]
export const APPLE_TEXTS = [
  { heading: 'App name', file: 'name', limit: 30 },
  { heading: 'Subtitle', file: 'subtitle', limit: 30 },
  { heading: 'Promotional text', file: 'promotional_text', limit: 170 },
  { heading: 'Keywords', file: 'keywords', limit: 100 },
  { heading: 'Description', file: 'description', limit: 4000 },
]

/** Play's screenshot shelves. `side` is the allowed range of each side in pixels. */
export const PLAY_SHELVES = {
  phoneScreenshots: { min: 2, max: 8, side: [320, 3840] },
  sevenInchScreenshots: { min: 0, max: 8, side: [320, 3840] },
  tenInchScreenshots: { min: 0, max: 8, side: [1080, 7680] },
}
const PLAY_SCREENSHOT_MAX_BYTES = 8 << 20
export const PLAY_SINGLES = {
  featureGraphic: { size: [1024, 500], maxBytes: 15 << 20 },
  icon: { size: [512, 512], maxBytes: 1 << 20 },
}

/** App Store Connect takes 1 to 10 screenshots for each display size. */
export const APPLE_DISPLAYS = [
  { name: 'iPhone 6.9-inch', size: [1320, 2868] },
  { name: 'iPad 13-inch', size: [2064, 2752] },
]
const APPLE_SCREENSHOTS = { min: 1, max: 10 }

const chars = (text) => [...text].length
const rel = (path) => relative(ROOT, path)

// ---------------------------------------------------------------------------------------
// Texts.
// ---------------------------------------------------------------------------------------

/** The first fenced value under one `## ` heading, trimmed. Null when there is none. */
export function section(markdown, heading) {
  const lines = markdown.replaceAll('\r\n', '\n').split('\n')
  const start = lines.findIndex((line) => line.trim() === `## ${heading}`)
  if (start < 0) return null
  let open = -1
  for (let at = start + 1; at < lines.length; at += 1) {
    if (open < 0) {
      if (lines[at].startsWith('## ')) return null
      if (lines[at].startsWith('```')) open = at
    } else if (lines[at].startsWith('```')) {
      return lines.slice(open + 1, at).join('\n').trim()
    }
  }
  return null
}

/** The fields of one listing file, and the reasons a store would refuse any of them. */
export function extractTexts(locale, markdown, fields) {
  const texts = {}
  const problems = []
  for (const { heading, file, limit } of fields) {
    const value = section(markdown, heading)
    if (value === null || value === '') {
      problems.push(`${locale} ${file}: no "## ${heading}" section with a fenced value`)
    } else if (chars(value) > limit) {
      problems.push(`${locale} ${file}: ${chars(value)} characters, limit ${limit}`)
    } else {
      texts[file] = value
    }
  }
  return { texts, problems }
}

function loadTexts(platform) {
  const [folder, fields] = platform === 'play' ? ['android', PLAY_TEXTS] : ['ios', APPLE_TEXTS]
  return Object.entries(LOCALES).map(([stem, locale]) => {
    const path = join(LISTING, folder, 'listing', `${stem}.md`)
    if (!existsSync(path)) return { locale, texts: {}, problems: [`${locale}: ${rel(path)} is missing`] }
    return { locale, ...extractTexts(locale, readFileSync(path, 'utf8'), fields) }
  })
}

// ---------------------------------------------------------------------------------------
// Images. An image is { name, width, height, bytes } or { name, error }.
// ---------------------------------------------------------------------------------------

/** Width and height out of the first 24 bytes of a PNG. */
export function pngSize(head) {
  if (head.length < 24 || head.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' || head.subarray(12, 16).toString() !== 'IHDR') {
    throw new Error('is not a PNG')
  }
  return [head.readUInt32BE(16), head.readUInt32BE(20)]
}

function readImage(path) {
  const name = basename(path)
  const head = Buffer.alloc(24)
  const fd = openSync(path, 'r')
  try {
    readSync(fd, head, 0, 24, 0)
    const [width, height] = pngSize(head)
    return { name, width, height, bytes: statSync(path).size }
  } catch (error) {
    return { name, error: error.message }
  } finally {
    closeSync(fd)
  }
}

const visible = (dir) => (existsSync(dir) ? readdirSync(dir).filter((name) => !name.startsWith('.')).sort() : [])
const listImages = (dir) => visible(dir).map((name) => readImage(join(dir, name)))

const megabytes = (bytes) => `${(bytes / (1 << 20)).toFixed(1)} MB`

/** Play: 9:16 or 16:9, each side inside the shelf's range, at most 8 MB. */
function playScreenshotProblems(image, { side }) {
  if (image.error) return [image.error]
  const problems = []
  const ratio = image.width / image.height
  if (Math.abs(ratio - 9 / 16) > 0.002 && Math.abs(ratio - 16 / 9) > 0.002) {
    problems.push(`${image.width}x${image.height} is neither 16:9 nor 9:16`)
  }
  for (const length of [image.width, image.height]) {
    if (length < side[0] || length > side[1]) problems.push(`${length} px is outside ${side[0]}-${side[1]} px`)
  }
  if (image.bytes > PLAY_SCREENSHOT_MAX_BYTES) problems.push(`${megabytes(image.bytes)} is over the 8 MB limit`)
  return problems
}

function exactSizeProblems(image, { size, maxBytes }) {
  if (image.error) return [image.error]
  const problems = []
  if (image.width !== size[0] || image.height !== size[1]) {
    problems.push(`${image.width}x${image.height}, Play wants ${size[0]}x${size[1]}`)
  }
  if (maxBytes && image.bytes > maxBytes) problems.push(`${megabytes(image.bytes)} is over the ${megabytes(maxBytes)} limit`)
  return problems
}

/** Everything wrong with `{ shelves: { shelf: image[] }, singles: { name: image|null } }` of one language. */
function playLocaleProblems(locale, images) {
  if (images === null) return [`${locale}: the images folder is missing`]
  const problems = []
  for (const [shelf, rule] of Object.entries(PLAY_SHELVES)) {
    const found = images.shelves[shelf] ?? []
    if (found.length < rule.min || found.length > rule.max) {
      problems.push(`${locale} ${shelf}: ${found.length} image(s), Play takes ${rule.min}-${rule.max}`)
    }
    for (const image of found) {
      problems.push(...playScreenshotProblems(image, rule).map((p) => `${locale} ${shelf}/${image.name}: ${p}`))
    }
  }
  for (const [name, rule] of Object.entries(PLAY_SINGLES)) {
    const image = images.singles[name]
    if (!image) problems.push(`${locale} ${name}.png: missing`)
    else problems.push(...exactSizeProblems(image, rule).map((p) => `${locale} ${name}.png: ${p}`))
  }
  return problems
}

/** `tree` maps each locale to its images, or to null when its folder is missing. */
export function playImageProblems(tree) {
  return Object.entries(tree).flatMap(([locale, images]) => playLocaleProblems(locale, images))
}

/** fastlane reads every folder in the metadata path as a language, so a stray one fails the run. */
export function strayProblems(names, locales) {
  return names
    .filter((name) => !name.startsWith('.') && !locales.includes(name))
    .map((name) => `play/${name}: not a language folder, and fastlane would read it as one`)
}

/** `tree` maps each locale to the images of its folder. */
export function appleImageProblems(tree) {
  return Object.entries(tree).flatMap(([locale, images]) => {
    const counts = APPLE_DISPLAYS.map(() => 0)
    const problems = images.flatMap((image) => {
      if (image.error) return [`${locale} ${image.name}: ${image.error}`]
      const at = APPLE_DISPLAYS.findIndex(({ size }) => size[0] === image.width && size[1] === image.height)
      if (at < 0) {
        const wanted = APPLE_DISPLAYS.map(({ name, size }) => `${size[0]}x${size[1]} (${name})`).join(' or ')
        return [`${locale} ${image.name}: ${image.width}x${image.height}, App Store wants ${wanted}`]
      }
      counts[at] += 1
      return []
    })
    APPLE_DISPLAYS.forEach(({ name }, at) => {
      if (counts[at] < APPLE_SCREENSHOTS.min || counts[at] > APPLE_SCREENSHOTS.max) {
        problems.push(`${locale} ${name}: ${counts[at]} screenshot(s), App Store takes ${APPLE_SCREENSHOTS.min}-${APPLE_SCREENSHOTS.max}`)
      }
    })
    return problems
  })
}

function readPlayTree(root) {
  const entries = Object.values(LOCALES).map((locale) => {
    const images = join(root, locale, 'images')
    if (!existsSync(images)) return [locale, null]
    const shelves = Object.fromEntries(Object.keys(PLAY_SHELVES).map((shelf) => [shelf, listImages(join(images, shelf))]))
    const singles = Object.fromEntries(Object.keys(PLAY_SINGLES).map((name) => {
      const path = join(images, `${name}.png`)
      return [name, existsSync(path) ? readImage(path) : null]
    }))
    return [locale, { shelves, singles }]
  })
  return Object.fromEntries(entries)
}

const readAppleTree = (root) =>
  Object.fromEntries(Object.values(LOCALES).map((locale) => [locale, listImages(join(root, locale))]))

// ---------------------------------------------------------------------------------------
// Arguments.
// ---------------------------------------------------------------------------------------

export function parseArgs(argv) {
  const options = { platform: 'play', dry: false, publish: false, upload: false, selfTest: false, track: 'internal' }
  for (let at = 0; at < argv.length; at += 1) {
    const arg = argv[at]
    if (arg === '--platform') options.platform = argv[(at += 1)]
    else if (arg === '--dry') options.dry = true
    else if (arg === '--publish') options.publish = true
    else if (arg === '--track') options.track = argv[(at += 1)]
    else if (arg === '--upload') options.upload = true
    else if (arg === '--self-test') options.selfTest = true
    else throw new Error(`Unknown argument "${arg}".`)
  }
  if (!(options.platform in WORKFLOW)) throw new Error('--platform is play or appstore.')
  if (options.publish && options.platform !== 'play') throw new Error('--publish is for --platform play. The App Store takes --upload.')
  if (options.upload && options.platform !== 'appstore') throw new Error('--upload is for --platform appstore. Play takes --publish.')
  return options
}

// ---------------------------------------------------------------------------------------
// The run.
// ---------------------------------------------------------------------------------------

function refuse(problems) {
  if (problems.length === 0) return
  console.error(`The listing is not ready. ${problems.length} problem(s):`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}

function zip(folder, archive) {
  rmSync(join(STORE, archive), { force: true })
  execFileSync('zip', ['-qr', archive, folder, '-x', '*.DS_Store'], { cwd: STORE })
  console.log(`zipped ${rel(join(STORE, archive))} (${megabytes(statSync(join(STORE, archive)).size)})`)
  return join(STORE, archive)
}

function writeTexts(base, rows) {
  for (const { locale, texts } of rows) {
    const dir = join(base, locale)
    mkdirSync(dir, { recursive: true })
    for (const [file, value] of Object.entries(texts)) writeFileSync(join(dir, `${file}.txt`), value)
  }
}

function gh(...args) {
  try {
    return execFileSync('gh', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (error) {
    throw new Error(`gh ${args.join(' ')}\n${error.stderr || error.message}`)
  }
}

/** The draft release that carries the zips. It stays a draft: nobody publishes it. */
function ensureDraftRelease() {
  try {
    gh('release', 'view', RELEASE)
  } catch (error) {
    if (!/release not found/i.test(error.message)) throw error
    gh('release', 'create', RELEASE, '--draft', '--title', 'Store assets',
      '--notes', 'Store listing files for the listing workflows. Keep this release a draft.')
    console.log(`created the draft release ${RELEASE}`)
  }
}

function send(platform, archive, inputs) {
  ensureDraftRelease()
  gh('release', 'upload', RELEASE, archive, '--clobber')
  console.log(`attached ${basename(archive)} to the draft release ${RELEASE}`)
  try {
    const out = gh('workflow', 'run', WORKFLOW[platform], ...Object.entries(inputs).flatMap(([k, v]) => ['-f', `${k}=${v}`]))
    console.log(out.trim())
  } catch (error) {
    throw new Error(`${error.message}\nThe zip is attached. GitHub runs only a workflow file that is on the default branch: merge and push ${WORKFLOW[platform]}, then run this again.`)
  }
  console.log(`Watch it: gh run list --workflow ${WORKFLOW[platform]} --limit 1, then gh run watch <id> --exit-status`)
}

function runPlay({ dry, publish, track }) {
  const rows = loadTexts('play')
  const root = join(STORE, 'play')
  const imageProblems = existsSync(root)
    ? [...strayProblems(readdirSync(root), Object.values(LOCALES)), ...playImageProblems(readPlayTree(root))]
    : [`${rel(root)} is missing. The screenshot run writes it.`]
  refuse([...rows.flatMap((row) => row.problems), ...imageProblems])
  writeTexts(root, rows)
  console.log(`Play: ${rows.length} language(s) checked, texts written into ${rel(root)}`)
  const archive = zip('play', 'play.zip')
  if (dry) return console.log('--dry: nothing was sent.')
  send('play', archive, { validateOnly: !publish, track })
  console.log(publish ? 'The workflow WRITES the live listing.' : 'The workflow only VALIDATES. Run again with --publish to write it.')
}

function runAppStore({ dry, upload }) {
  const rows = loadTexts('appstore')
  const source = join(STORE, 'appstore')
  const tree = existsSync(source) ? readAppleTree(source) : null
  refuse([
    ...rows.flatMap((row) => row.problems),
    ...(tree ? appleImageProblems(tree) : [`${rel(source)} is missing. The screenshot run writes it.`]),
  ])
  const layout = join(STORE, 'appstore-deliver')
  rmSync(layout, { recursive: true, force: true })
  writeTexts(join(layout, 'metadata'), rows)
  for (const [locale, images] of Object.entries(tree)) {
    mkdirSync(join(layout, 'screenshots', locale), { recursive: true })
    for (const { name } of images) copyFileSync(join(source, locale, name), join(layout, 'screenshots', locale, name))
  }
  console.log(`App Store: ${rows.length} language(s) checked, layout written into ${rel(layout)}`)
  const archive = zip('appstore-deliver', 'appstore.zip')
  if (dry) return console.log('--dry: nothing was sent.')
  if (!upload) return console.log('Stopped before sending. Add --upload to send it and start ios-listing.yml.')
  send('appstore', archive, { upload: true })
  console.log('The workflow UPLOADS the metadata and screenshots to App Store Connect. It submits nothing.')
}

// ---------------------------------------------------------------------------------------
// The checks of the checks.
// ---------------------------------------------------------------------------------------

function selfTest() {
  const assert = (condition, what) => {
    if (!condition) throw new Error(`self-test: ${what}`)
  }
  const refused = (problems, ...needles) => problems.length > 0 && needles.every((n) => problems.join('\n').includes(n))

  const md = '# t\n\n## App name\n\n```\nStoryArc\n```\n\n## Promotional text\n\n`170 characters.`\n\n```\nHello\r\nthere  \n```\n\n## Empty\n\nno fence here\n\n## Last\n\n```\nx\n```\n'
  assert(section(md, 'App name') === 'StoryArc', 'a fenced value is read')
  assert(section(md, 'Promotional text') === 'Hello\nthere', 'inline code is skipped, CRLF and trailing space are trimmed')
  assert(section(md, 'Empty') === null, 'a heading with no fence before the next heading has no value')
  assert(section(md, 'Missing') === null, 'a missing heading has no value')
  assert(section(md, 'Last') === 'x', 'the last section is read')
  assert(section(md, 'App') === null, 'a heading is matched whole, not by prefix')

  assert(Object.values(LOCALES).join() === 'en-US,de-DE,es-ES,fr-FR', 'the four languages map to the store locales')
  assert(Object.keys(LOCALES).join() === 'en,de,es,fr', 'the listing file stems are the four languages')

  const fields = [{ heading: 'App name', file: 'title', limit: 8 }]
  assert(extractTexts('en-US', md, fields).texts.title === 'StoryArc', 'a value at the limit passes')
  assert(refused(extractTexts('de-DE', md, [{ ...fields[0], limit: 7 }]).problems, 'de-DE', 'title', '8 characters, limit 7'), 'a value over the limit names its language and field')
  assert(refused(extractTexts('fr-FR', md, [{ heading: 'Nope', file: 'subtitle', limit: 9 }]).problems, 'fr-FR', 'subtitle'), 'a missing field names its language and field')
  assert(chars('a\u{1F600}') === 2, 'characters are counted as characters, not code units')

  for (const platform of ['play', 'appstore']) {
    const rows = loadTexts(platform)
    assert(rows.map((row) => row.locale).join() === 'en-US,de-DE,es-ES,fr-FR', `${platform}: the four listing files are read in order`)
    const structural = rows.flatMap((row) => row.problems).filter((p) => /no "## |is missing/.test(p))
    assert(structural.length === 0, `${platform}: the committed listing has every heading: ${structural.join('; ')}`)
  }
  assert(PLAY_TEXTS.map((f) => f.limit).join() === '30,80,4000' && APPLE_TEXTS.map((f) => f.limit).join() === '30,30,170,100,4000', 'the store limits are the documented ones')

  const header = Buffer.alloc(24)
  Buffer.from('89504e470d0a1a0a', 'hex').copy(header)
  header.write('IHDR', 12)
  header.writeUInt32BE(1320, 16)
  header.writeUInt32BE(2868, 20)
  assert(pngSize(header).join('x') === '1320x2868', 'a PNG header is read')
  let threw = false
  try { pngSize(Buffer.alloc(24)) } catch { threw = true }
  assert(threw, 'a file that is not a PNG is refused')

  const shot = (width = 1080, height = 1920, name = '01-a.png', bytes = 1000) => ({ name, width, height, bytes })
  const shots = (count, width = 1080, height = 1920) =>
    Array.from({ length: count }, (_, i) => shot(width, height, `0${i + 1}-a.png`))
  const locale = () => ({
    shelves: { phoneScreenshots: shots(6), sevenInchScreenshots: shots(6), tenInchScreenshots: shots(6, 1440, 2560) },
    singles: { featureGraphic: shot(1024, 500, 'featureGraphic.png'), icon: shot(512, 512, 'icon.png') },
  })
  const withShelf = (shelf, images) => ({ shelves: { ...locale().shelves, [shelf]: images }, singles: locale().singles })
  const withSingle = (name, image) => ({ shelves: locale().shelves, singles: { ...locale().singles, [name]: image } })
  const play = (entry) => playImageProblems({ 'de-DE': entry })

  assert(play(locale()).length === 0, 'a complete Play language passes')
  assert(play({ shelves: { ...locale().shelves, sevenInchScreenshots: [], tenInchScreenshots: [] }, singles: locale().singles }).length === 0, 'tablet shelves are optional')
  assert(refused(play(withShelf('phoneScreenshots', shots(1))), 'de-DE', 'phoneScreenshots', '1 image(s)'), 'one phone screenshot is refused')
  assert(play(withShelf('phoneScreenshots', shots(8))).length === 0 && refused(play(withShelf('phoneScreenshots', shots(9))), '9 image(s)'), 'eight phone screenshots pass and nine do not')
  assert(refused(play(withShelf('tenInchScreenshots', shots(2, 900, 1600))), 'tenInchScreenshots', '900 px is outside 1080-7680'), 'a ten-inch side under 1080 is refused')
  assert(refused(play(withShelf('phoneScreenshots', shots(2, 1080, 2400))), '1080x2400 is neither 16:9 nor 9:16'), 'a 20:9 screenshot is refused')
  assert(refused(play(withShelf('phoneScreenshots', [shot(), { ...shot(1080, 1920, '02-b.png'), bytes: 9 << 20 }])), '02-b.png', '8 MB'), 'a screenshot over 8 MB is refused')
  assert(refused(play(withShelf('phoneScreenshots', [shot(), { name: '02-b.png', error: 'is not a PNG' }])), '02-b.png', 'is not a PNG'), 'an unreadable image is refused')
  assert(refused(play(withSingle('featureGraphic', shot(1024, 501, 'featureGraphic.png'))), 'featureGraphic.png', '1024x501, Play wants 1024x500'), 'a feature graphic one pixel tall is refused')
  assert(refused(play(withSingle('icon', shot(512, 512, 'icon.png', 2 << 20))), 'icon.png', 'over the 1.0 MB limit'), 'an icon over 1 MB is refused')
  assert(refused(play(withSingle('icon', null)), 'icon.png: missing'), 'a missing icon is refused')
  assert(refused(playImageProblems({ 'fr-FR': null }), 'fr-FR', 'images folder is missing'), 'a language without an images folder is refused')
  assert(refused(strayProblems(['en-US', 'tmp', '.DS_Store'], Object.values(LOCALES)), 'play/tmp') && strayProblems(['en-US', '.DS_Store'], Object.values(LOCALES)).length === 0, 'a stray folder is refused and a hidden file is not')

  const phone = (name) => shot(1320, 2868, name)
  const pad = (name) => shot(2064, 2752, name)
  const apple = (images) => appleImageProblems({ 'es-ES': images })
  assert(apple([phone('01.png'), pad('01-ipad.png')]).length === 0, 'one iPhone and one iPad screenshot pass')
  assert(refused(apple([phone('01.png')]), 'es-ES', 'iPad 13-inch', '0 screenshot(s)'), 'a missing iPad set is refused')
  assert(refused(apple([phone('01.png'), pad('a.png'), shot(1290, 2796, 'old.png')]), 'old.png', '1290x2796'), 'an iPhone 6.7-inch size is refused')
  assert(refused(apple([...Array.from({ length: 11 }, (_, i) => phone(`${i}.png`)), pad('a.png')]), 'iPhone 6.9-inch', '11 screenshot(s)'), 'eleven screenshots are refused')

  assert(parseArgs([]).platform === 'play' && parseArgs(['--dry']).dry, 'play is the default platform')
  assert(parseArgs(['--platform', 'appstore', '--upload']).upload, 'the App Store takes --upload')
  const bad = (...args) => { try { parseArgs(args); return false } catch { return true } }
  assert(bad('--platform', 'ios') && bad('--bogus') && bad('--platform', 'appstore', '--publish') && bad('--upload'), 'a wrong platform, flag or flag pair is refused')

  console.log('store-publish.mjs self-test: all pass')
}

function main() {
  let options
  try {
    options = parseArgs(process.argv.slice(2))
  } catch (error) {
    console.error(`${error.message}\nUsage: store-publish.mjs [--platform play|appstore] [--dry] [--publish | --upload] [--track <name>] [--self-test]`)
    process.exit(2)
  }
  if (options.selfTest) return selfTest()
  try {
    return options.platform === 'play' ? runPlay(options) : runAppStore(options)
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
