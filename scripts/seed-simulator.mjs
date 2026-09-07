// Puts a downloaded publication on a simulator, so an audit measures a populated screen.
//
// `AccessibilityAuditTests.testDownloadsPassesTheAudit` audits the Downloads screen. On a
// clean device that screen holds nothing, so the audit measures nothing and the test's own
// `XCTExpectFailure` goes unsatisfied, which is a failure. Every CI run is a clean device.
//
// Two things are written, because the app needs both. `DownloadStore` keeps the record in
// `UserDefaults` under `app.storyarc.downloads` and the bytes at
// `<application support>/Downloads/<id>/<title>.<extension>`. A record with no file draws a
// cover and opens nothing; a file with no record is not in the library at all.
//
// **This cannot seed an audiobook, and the twelve player tests still fail without one.**
// `PublicationFormat.init(mediaType:)` maps no audio type, and `PublicationFormat.mediaType`
// answers nil for `.audiobook`, so an audiobook cannot round-trip through a download record.
// `AudiobookWalk` also looks on the Library tab, and a download is drawn on the Downloads
// tab. Section A of `docs/mvp-device-checklist.md` carries both.

import { execFileSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const BUNDLE = 'app.storyarc.StoryArc'

const TITLE = 'Harbour Lights'
const ID = 'seed-harbour-lights'
const MEDIA_TYPE = 'application/vnd.comicbook+zip'
// `DownloadStore.extension(for:)` asks `PublicationFormat`, whose raw value for a CBZ is
// `cbz`. The name is the store's, not the fixture's: the reader asks the store where the
// file is, and the store computes this name from the media type.
const EXTENSION = 'cbz'
const FIXTURE = join(ROOT, 'packages/test-fixtures/comics/data-descriptor.cbz')

const run = (args) => execFileSync('xcrun', args, { encoding: 'utf8' }).trim()

const chosen = () => {
  const at = process.argv.indexOf('--device')
  if (at >= 0 && process.argv[at + 1]) return process.argv[at + 1]
  const booted = run(['simctl', 'list', 'devices', 'booted'])
  const match = booted.match(/\(([0-9A-F-]{36})\) \(Booted\)/)
  if (!match) {
    console.error('No booted simulator. Boot one, or pass --device <name or udid>.')
    process.exit(1)
  }
  return match[1]
}

const udid = chosen()

// The container exists only after an install. Seeding before `xcodebuild` has put the app on
// the device is the easy mistake, so it is named rather than swallowed.
let container
try {
  container = run(['simctl', 'get_app_container', udid, BUNDLE, 'data'])
} catch {
  console.error(`${BUNDLE} is not installed on ${udid}. Install the app, then seed.`)
  process.exit(1)
}

if (!existsSync(FIXTURE)) {
  console.error(`Missing fixture: ${FIXTURE}`)
  process.exit(1)
}

// `DownloadStore.safe` keeps `A-Za-z0-9._ -` and replaces every other character.
const safe = (text) => text.replace(/[^A-Za-z0-9._ -]/g, '-')

const folder = join(container, 'Library/Application Support/Downloads', safe(ID))
const file = join(folder, `${safe(TITLE).trim()}.${EXTENSION}`)
mkdirSync(folder, { recursive: true })
copyFileSync(FIXTURE, file)

// `StoredDownload` as `JSONEncoder` writes it. A date is seconds since the Apple reference
// date, 2001-01-01, which is what `JSONDecoder` reads back with its default strategy.
const REFERENCE = Date.UTC(2001, 0, 1) / 1000
const record = [{
  id: ID,
  sourceID: null,
  title: TITLE,
  remote: `https://example.invalid/${ID}.cbz`,
  mediaType: MEDIA_TYPE,
  expectedBytes: null,
  downloadedBytes: 0,
  completedAt: Math.floor(Date.now() / 1000) - REFERENCE,
  isFinished: true,
  failure: null,
  attempts: 0,
  verificationFailures: 0,
  pause: null,
}]

// The old-style plist spelling of `Data`, which is what `UserDefaults.data(forKey:)` reads.
// Anything else arrives as a string, `DownloadStore` reads it as absent, and that looks
// exactly like a seed that was ignored.
const hex = Buffer.from(JSON.stringify(record), 'utf8').toString('hex')
run(['simctl', 'spawn', udid, 'defaults', 'write', BUNDLE, 'app.storyarc.downloads', '-data', hex])

console.log(`Seeded ${TITLE} on ${udid}`)
console.log(`  file   <container>${file.slice(container.length)}`)
console.log(`  record app.storyarc.downloads, ${record.length} entry`)
