#!/usr/bin/env node
// Guards the one dependency no scanner can see.
//
// libarchive is vendored as copied sources (third_party/libarchive/VENDORING.md), so it
// has no package manifest, no lockfile entry and no advisory feed pointing at it. The
// consequence showed up on its own: the tree sat at 3.8.1 while THIRD_PARTY_NOTICES.md
// told readers it was 3.7.7, and neither number moved when nine upstream RAR
// memory-safety fixes shipped. A pin nobody can check is not a pin.
//
// So the version lives in one file, `third_party/libarchive/pin.json`, and this script
// is the alarm VENDORING.md's manual procedure never had:
//
//   --check      offline, runs in `pnpm lint`. Every place that states a libarchive
//                version states the same one, and no upstream-owned source has been
//                edited since it was copied.
//   --upstream   online, for a scheduled job. Fails when a newer libarchive release
//                exists than the one pinned.
//   --write      recomputes the source digest after a refresh. Maintainer helper.
//   --self-test  proves --check actually fails on a stale version and a patched source.
//
// Usage:
//   node scripts/libarchive-pin.mjs --check
//   node scripts/libarchive-pin.mjs --upstream
//   node scripts/libarchive-pin.mjs --write
//   node scripts/libarchive-pin.mjs --self-test

import { createHash } from 'node:crypto'
import { cpSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

const RELEASES = 'https://api.github.com/repos/libarchive/libarchive/releases'

/** Every file under `dir`, repository-relative, in a stable order. */
function walk(dir) {
  const out = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) out.push(...walk(path))
    else out.push(path)
  }
  return out.sort()
}

/**
 * One digest over every file libarchive owns.
 *
 * `config.h` and the module map are StoryArc's, written by hand because there is no
 * configure step, so they are excluded by name rather than by guesswork — see
 * `localFiles` in pin.json. The name goes into the hash alongside the bytes, so a
 * renamed or deleted source is caught as well as an edited one.
 */
function sourceDigest(tree, localFiles) {
  const base = join(tree, 'Sources/CLibarchive')
  const local = new Set(localFiles)
  const hash = createHash('sha256')
  for (const path of walk(base)) {
    const name = relative(base, path).split(sep).join('/')
    if (local.has(name)) continue
    hash.update(name)
    hash.update('\0')
    hash.update(readFileSync(path))
  }
  return hash.digest('hex')
}

const parse = (version) => version.split('.').map(Number)

/** -1, 0 or 1, comparing three-part versions numerically rather than as text. */
function compare(a, b) {
  const [x, y] = [parse(a), parse(b)]
  for (let i = 0; i < 3; i += 1) {
    if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) < (y[i] ?? 0) ? -1 : 1
  }
  return 0
}

/** The `ARCHIVE_VERSION_NUMBER` libarchive derives from a release: 3.8.9 -> 3008009. */
const numberFor = (version) => {
  const [major, minor, patch] = parse(version)
  return major * 1000000 + minor * 1000 + patch
}

const readPin = (root) => JSON.parse(readFileSync(join(root, 'third_party/libarchive/pin.json'), 'utf8'))

/**
 * Every failure `--check` can report, as a list rather than a throw, so one run names
 * all of them instead of stopping at the first.
 */
function check(root) {
  const pin = readPin(root)
  const tree = join(root, 'third_party/libarchive')
  const read = (path) => readFileSync(join(tree, path), 'utf8')
  const failures = []

  const digest = sourceDigest(tree, pin.localFiles)
  if (digest !== pin.sourcesSha256) {
    failures.push(
      `the vendored sources do not match the recorded digest for ${pin.version}: ` +
        `expected ${pin.sourcesSha256}, found ${digest}. ` +
        'Either a source was edited in place — which VENDORING.md forbids, because the ' +
        'next refresh would silently drop the edit — or a refresh landed without ' +
        '`node scripts/libarchive-pin.mjs --write`.',
    )
  }

  // Four places state the version, and every one of them has drifted before.
  const stated = [
    ['config.h', 'Sources/CLibarchive/config.h'],
    ['include/archive.h', 'Sources/CLibarchive/include/archive.h'],
    ['include/archive_entry.h', 'Sources/CLibarchive/include/archive_entry.h'],
  ]
  for (const [label, path] of stated) {
    const text = read(path)
    const only = text.match(/ARCHIVE_VERSION_ONLY_STRING\s+"([^"]+)"/)?.[1]
    const number = text.match(/ARCHIVE_VERSION_NUMBER\s+(\d+)/)?.[1]
    if (only && only !== pin.version) {
      failures.push(`${label} says libarchive ${only}, pin.json says ${pin.version}`)
    }
    if (number && Number(number) !== numberFor(pin.version)) {
      failures.push(
        `${label} has ARCHIVE_VERSION_NUMBER ${number}, ${numberFor(pin.version)} for ${pin.version}`,
      )
    }
  }

  const vendoring = read('VENDORING.md')
  if (!vendoring.includes(`version ${pin.version}`)) {
    failures.push(`VENDORING.md does not name version ${pin.version}`)
  }

  // The notices table is generated from this inventory, and it is what a reader of the
  // shipped app is told. It said 3.7.7 while the tree was at 3.8.1.
  const inventory = JSON.parse(readFileSync(join(root, 'packages/licences/notices.json'), 'utf8'))
  const notice = inventory.notices.find((entry) => entry.name === 'libarchive')
  if (!notice) failures.push('packages/licences/notices.json has no libarchive entry')
  else if (notice.version !== pin.version) {
    failures.push(
      `packages/licences/notices.json says libarchive ${notice.version}, pin.json says ${pin.version}`,
    )
  }

  return { pin, failures }
}

/** The newest published libarchive release, ignoring drafts and pre-releases. */
async function latestRelease() {
  const response = await fetch(RELEASES, {
    headers: { accept: 'application/vnd.github+json', 'user-agent': 'storyarc-libarchive-pin' },
  })
  if (!response.ok) throw new Error(`GitHub returned ${response.status} for ${RELEASES}`)
  const releases = await response.json()
  const tags = releases
    .filter((release) => !release.draft && !release.prerelease)
    .map((release) => String(release.tag_name).replace(/^v/, ''))
    .filter((tag) => /^\d+\.\d+\.\d+$/.test(tag))
  if (tags.length === 0) throw new Error('no published libarchive release found')
  return tags.sort(compare).at(-1)
}

const mode = process.argv[2] ?? '--check'

if (mode === '--write') {
  const path = join(ROOT, 'third_party/libarchive/pin.json')
  const pin = readPin(ROOT)
  pin.sourcesSha256 = sourceDigest(join(ROOT, 'third_party/libarchive'), pin.localFiles)
  writeFileSync(path, `${JSON.stringify(pin, null, 2)}\n`)
  console.log(`libarchive pin: ${pin.version}, sources ${pin.sourcesSha256}`)
  process.exit(0)
}

if (mode === '--check') {
  const { pin, failures } = check(ROOT)
  if (failures.length > 0) {
    for (const failure of failures) console.error(`libarchive pin: ${failure}`)
    process.exit(1)
  }
  console.log(`libarchive pin: ${pin.version} consistent across 5 places, sources unmodified.`)
  process.exit(0)
}

if (mode === '--upstream') {
  const pin = readPin(ROOT)
  const latest = await latestRelease()
  if (compare(latest, pin.version) > 0) {
    console.error(
      `libarchive pin: vendored ${pin.version}, upstream has ${latest}. ` +
        'Refresh with third_party/libarchive/VENDORING.md and read the release notes for ' +
        'the RAR readers first — those two files parse untrusted bytes from the internet.',
    )
    process.exit(1)
  }
  console.log(`libarchive pin: ${pin.version} is the newest release (upstream ${latest}).`)
  process.exit(0)
}

if (mode === '--self-test') {
  // A checker that cannot fail is not a check. Each mutation is one of the ways the pin
  // has actually drifted, or could: a stale version left behind in one of the files, a
  // source edited in place, an inventory nobody updated.
  const scratch = mkdtempSync(join(tmpdir(), 'storyarc-libarchive-pin-'))
  try {
    cpSync(join(ROOT, 'third_party'), join(scratch, 'third_party'), { recursive: true })
    cpSync(join(ROOT, 'packages/licences'), join(scratch, 'packages/licences'), { recursive: true })

    const edit = (path, replace) => {
      const full = join(scratch, path)
      writeFileSync(full, replace(readFileSync(full, 'utf8')))
    }
    const fails = (label) => {
      const { failures } = check(scratch)
      return failures.some((failure) => failure.includes(label))
    }

    const checks = [
      ['a clean copy passes', () => check(scratch).failures.length === 0],
      [
        'a stale version in config.h is caught',
        () => {
          edit('third_party/libarchive/Sources/CLibarchive/config.h', (text) =>
            text.replace(/ARCHIVE_VERSION_ONLY_STRING "[^"]+"/, 'ARCHIVE_VERSION_ONLY_STRING "3.8.1"'),
          )
          return fails('config.h says libarchive 3.8.1')
        },
      ],
      [
        'an edited source is caught',
        () => {
          edit(
            'third_party/libarchive/Sources/CLibarchive/archive_read_support_format_rar.c',
            (text) => `${text}\n/* patched in place */\n`,
          )
          return fails('do not match the recorded digest')
        },
      ],
      [
        'a stale notices inventory is caught',
        () => {
          edit('packages/licences/notices.json', (text) => text.replace(/"3\.8\.\d+"/, '"3.7.7"'))
          return fails('notices.json says libarchive 3.7.7')
        },
      ],
    ]

    const failed = checks.filter(([, holds]) => !holds()).map(([name]) => name)
    if (failed.length > 0) {
      console.error(`libarchive pin self-test failed: ${failed.join(', ')}`)
      process.exit(1)
    }
    console.log(`libarchive pin self-test: ${checks.length} checks passed`)
    process.exit(0)
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
}

console.error('usage: node scripts/libarchive-pin.mjs --check | --upstream | --write | --self-test')
process.exit(2)
