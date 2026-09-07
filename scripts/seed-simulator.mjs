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
// **This seeds a comic only, and the twelve player tests still fail without an audiobook.**
// The format table is no longer the reason. `PublicationFormat` splits the audio containers,
// so `audio/mpeg` round-trips and the store names the file `<title>.mp3`; what remains is
// this script's own fixture and media type, and that `AudiobookWalk` looks on the Library tab
// while a download is drawn on the Downloads tab. Section A of
// `docs/mvp-device-checklist.md` carries the second half.

import { execFileSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const BUNDLE = 'app.storyarc.StoryArc'

// What gets seeded. Each entry becomes one record and one file.
//
// The comic is for the Downloads audit, which measures nothing on an empty screen. The
// audiobook is for the twelve player walks, which fail at `AudiobookWalk.swift` with "No
// audiobook on this device's shelf" and had no way to be given one until an audiobook could
// carry a media type.
//
// The extension is the store's, not the fixture's: `DownloadStore.location` computes it from
// the media type, and the reader asks the store where the file is.
const SEEDS = [
  {
    id: 'seed-harbour-lights',
    title: 'Harbour Lights',
    mediaType: 'application/vnd.comicbook+zip',
    extension: 'cbz',
    fixture: 'packages/test-fixtures/comics/data-descriptor.cbz',
  },
  {
    // `AudiobookWalk` matches a cover whose label contains this title.
    id: 'seed-sea-room',
    title: 'Sea Room',
    mediaType: 'audio/mp4',
    extension: 'm4b',
    fixture: 'packages/test-fixtures/audiobooks/chaptered.m4b',
  },
]

// An audiobook gets a folder of its own inside the download's folder. A comic does not.
//
// `LibraryScanner` indexes a lone audio file as the folder that holds it. An audiobook written
// beside its record therefore becomes the publication `seed-sea-room`, and the parent directory
// of that publication is the downloads root. `DownloadStore.download(forFileAt:in:)` matches a
// record by that parent directory. No record matches the downloads root, so
// `LibraryModel.adoptDownloads` drops the publication and no shelf draws it. One directory
// deeper, the publication is `Sea Room` and its parent is the record's own folder, so the
// record matches. A comic indexes as the file itself, so it stays beside its record.
const needsOwnFolder = (seed) => seed.mediaType.startsWith('audio/')

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

const REFERENCE = Date.UTC(2001, 0, 1) / 1000

// `DownloadStore.safe` keeps `A-Za-z0-9._ -` and replaces every other character.
const safe = (text) => text.replace(/[^A-Za-z0-9._ -]/g, '-')

const record = []
for (const seed of SEEDS) {
  const fixture = join(ROOT, seed.fixture)
  if (!existsSync(fixture)) {
    console.error(`Missing fixture: ${fixture}`)
    process.exit(1)
  }
  const name = safe(seed.title).trim()
  const recordFolder = join(container, 'Library/Application Support/Downloads', safe(seed.id))
  const folder = needsOwnFolder(seed) ? join(recordFolder, name) : recordFolder
  const file = join(folder, `${name}.${seed.extension}`)
  mkdirSync(folder, { recursive: true })
  copyFileSync(fixture, file)

  // `StoredDownload` as `JSONEncoder` writes it. A date is seconds since the Apple reference
  // date, 2001-01-01, which is what `JSONDecoder` reads back with its default strategy.
  record.push({
    id: seed.id,
    sourceID: null,
    title: seed.title,
    remote: `https://example.invalid/${seed.id}.${seed.extension}`,
    mediaType: seed.mediaType,
    expectedBytes: null,
    downloadedBytes: 0,
    completedAt: Math.floor(Date.now() / 1000) - REFERENCE,
    isFinished: true,
    failure: null,
    attempts: 0,
    verificationFailures: 0,
    pause: null,
  })
  console.log(`  ${seed.title}  <container>${file.slice(container.length)}`)
}

// The old-style plist spelling of `Data`, which is what `UserDefaults.data(forKey:)` reads.
// Anything else arrives as a string, `DownloadStore` reads it as absent, and that looks
// exactly like a seed that was ignored.
const hex = Buffer.from(JSON.stringify(record), 'utf8').toString('hex')
run(['simctl', 'spawn', udid, 'defaults', 'write', BUNDLE, 'app.storyarc.downloads', '-data', hex])

console.log(`Seeded ${record.length} publications on ${udid}`)
