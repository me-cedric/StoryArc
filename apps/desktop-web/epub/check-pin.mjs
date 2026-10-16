#!/usr/bin/env node
// Guards the one JavaScript dependency the desktop apps ship inside a web view.
//
// ADR-0018 D6: the three desktop web views load one Readium bundle, built here, and the
// bundle is pinned the way libarchive is (scripts/libarchive-pin.mjs). Three files have
// to agree and none of them can see the others: package.json names the versions, the
// lockfile resolves them, and dist/storyarc-epub.js is what the apps actually run. A
// dependabot bump, a `pnpm up`, or a rebuild from a different lockfile moves one of the
// three and nothing else notices — the web views load whatever bytes are in dist/.
//
// So the versions live in one file, `pin.json`, beside the digest of the built file, and
// this script is the alarm:
//
//   --check      offline, runs in `pnpm lint` (task 1.32 wires it). package.json pins
//                exactly what pin.json names, the lockfile resolves exactly that and one
//                copy of each, and the built file's sha256 is the recorded one.
//   --write      recomputes the digest after `pnpm build`. Maintainer helper: bump
//                pin.json and package.json together, install, build, then --write.
//   --self-test  proves --check fails on a bumped version, a range, a second copy of
//                @readium/shared in the lockfile and an edited bundle.
//
// Usage, from anywhere:
//   node apps/desktop-web/epub/check-pin.mjs --check
//   node apps/desktop-web/epub/check-pin.mjs --write
//   node apps/desktop-web/epub/check-pin.mjs --self-test

import { createHash } from 'node:crypto'
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

/** `1.2.3` and nothing else: no caret, no tilde, no tag, no range. */
const EXACT = /^\d+\.\d+\.\d+$/
const SHA256 = /^[0-9a-f]{64}$/

const readJson = (dir, name) => JSON.parse(readFileSync(join(dir, name), 'utf8'))

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

function digest(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

/**
 * What the lockfile says about one package: how the project's own importer resolved it,
 * and every version of it present anywhere in the graph.
 *
 * A text scan rather than a YAML parser, because the two shapes read here are fixed by
 * pnpm's lockfile v9 format and a parser would be the project's first runtime
 * dependency. The importer block is
 *
 *       '@readium/navigator':
 *         specifier: 2.11.1
 *         version: 2.11.1
 *
 * and each resolved package is a top-level key `  '@readium/shared@2.7.0':`, once under
 * `packages:` and once under `snapshots:`, hence the set. Two versions for one name is
 * two copies in the bundle, which is exactly what the override in pnpm-workspace.yaml
 * exists to prevent.
 */
function lockfileEntry(lockfile, name) {
  const importer = lockfile.match(
    new RegExp(`^ {6}'${escapeRegExp(name)}':\\n {8}specifier: (\\S+)\\n {8}version: (\\S+)`, 'm'),
  )
  const keys = lockfile.matchAll(new RegExp(`^ {2}'${escapeRegExp(name)}@([^'(]+)[^']*':`, 'gm'))
  const versions = [...new Set([...keys].map((match) => match[1]))].sort()
  return {
    specifier: importer?.[1],
    version: importer?.[2],
    versions,
  }
}

/**
 * Every failure `--check` can report, as a list rather than a throw, so one run names
 * all of them instead of stopping at the first.
 */
function check(dir) {
  const failures = []
  if (!existsSync(join(dir, 'pin.json'))) {
    return { pin: null, failures: ['pin.json is missing; the bundle is not pinned'] }
  }
  const pin = readJson(dir, 'pin.json')
  const manifest = readJson(dir, 'package.json')
  const lockfile = existsSync(join(dir, 'pnpm-lock.yaml')) ? readFileSync(join(dir, 'pnpm-lock.yaml'), 'utf8') : ''

  const pinned = Object.entries(pin.packages ?? {})
  if (pinned.length === 0) failures.push('pin.json names no packages')

  for (const [name, wanted] of pinned) {
    if (!EXACT.test(String(wanted))) {
      failures.push(`pin.json pins ${name} to "${wanted}", which is not an exact version`)
      continue
    }

    const declared = manifest.dependencies?.[name]
    if (declared === undefined) {
      failures.push(`package.json does not list ${name} as a dependency`)
    } else if (!EXACT.test(declared)) {
      failures.push(
        `package.json pins ${name} to "${declared}", which is a range, not the exact ${wanted}. ` +
          'A range lets `pnpm install` move the bundle without touching pin.json.',
      )
    } else if (declared !== wanted) {
      failures.push(`package.json pins ${name} ${declared}, pin.json says ${wanted}`)
    }

    if (lockfile === '') {
      failures.push('pnpm-lock.yaml is missing; the versions are not resolved anywhere')
    } else {
      const entry = lockfileEntry(lockfile, name)
      if (entry.version !== wanted) {
        failures.push(`pnpm-lock.yaml resolves ${name} to ${entry.version ?? 'nothing'}, pin.json says ${wanted}`)
      }
      if (entry.versions.length !== 1 || entry.versions[0] !== wanted) {
        failures.push(
          `pnpm-lock.yaml holds ${name} at ${entry.versions.join(', ') || 'no version'}; ` +
            `exactly one copy, ${wanted}, is allowed — a second copy ships twice in the bundle`,
        )
      }
    }
  }

  if (typeof pin.file !== 'string' || !SHA256.test(String(pin.sha256))) {
    failures.push('pin.json must name the built `file` and its 64-hex `sha256`')
  } else if (!existsSync(join(dir, pin.file))) {
    failures.push(`${pin.file} is missing; run \`pnpm build\` in apps/desktop-web/epub and commit it`)
  } else {
    const found = digest(join(dir, pin.file))
    if (found !== pin.sha256) {
      failures.push(
        `${pin.file} does not match the recorded digest: expected ${pin.sha256}, found ${found}. ` +
          'Either the bundle was rebuilt without `node check-pin.mjs --write`, or dist/ was ' +
          'edited by hand, which the next build would silently drop.',
      )
    }
  }

  return { pin, failures }
}

const mode = process.argv[2] ?? '--check'

if (mode === '--write') {
  const path = join(HERE, 'pin.json')
  const pin = readJson(HERE, 'pin.json')
  pin.sha256 = digest(join(HERE, pin.file))
  writeFileSync(path, `${JSON.stringify(pin, null, 2)}\n`)
  console.log(`epub bundle pin: ${pin.file} ${pin.sha256}`)
  process.exit(0)
}

if (mode === '--check') {
  const { pin, failures } = check(HERE)
  if (failures.length > 0) {
    for (const failure of failures) console.error(`epub bundle pin: ${failure}`)
    process.exit(1)
  }
  const named = Object.entries(pin.packages)
    .map(([name, version]) => `${name} ${version}`)
    .join(', ')
  console.log(`epub bundle pin: ${named}; ${pin.file} matches ${pin.sha256.slice(0, 12)}…`)
  process.exit(0)
}

if (mode === '--self-test') {
  // A checker that cannot fail is not a check. Each mutation is one way the pin can
  // drift: a bump that touched package.json alone, a range that lets install drift, a
  // lockfile that resolved a second copy, a bundle rebuilt or edited without --write.
  const scratch = mkdtempSync(join(tmpdir(), 'storyarc-epub-pin-'))
  try {
    const copy = (name) => cpSync(join(HERE, name), join(scratch, name), { recursive: true })
    for (const name of ['package.json', 'pin.json', 'pnpm-lock.yaml', 'dist']) copy(name)

    const edit = (name, replace) => {
      const full = join(scratch, name)
      writeFileSync(full, replace(readFileSync(full, 'utf8')))
    }
    const fails = (label) => check(scratch).failures.some((failure) => failure.includes(label))
    const restore = (name) => {
      rmSync(join(scratch, name), { recursive: true, force: true })
      copy(name)
    }

    const checks = [
      ['a clean copy passes', () => check(scratch).failures.length === 0],
      [
        'a bump in package.json alone is caught',
        () => {
          edit('package.json', (text) => text.replace('"@readium/navigator": "2.11.1"', '"@readium/navigator": "2.12.0"'))
          const caught = fails('package.json pins @readium/navigator 2.12.0, pin.json says 2.11.1')
          restore('package.json')
          return caught
        },
      ],
      [
        'a range in package.json is caught',
        () => {
          edit('package.json', (text) => text.replace('"@readium/shared": "2.7.0"', '"@readium/shared": "^2.7.0"'))
          const caught = fails('package.json pins @readium/shared to "^2.7.0", which is a range')
          restore('package.json')
          return caught
        },
      ],
      [
        'a second copy of @readium/shared in the lockfile is caught',
        () => {
          edit('pnpm-lock.yaml', (text) =>
            text.replace(/^packages:\n/m, "packages:\n\n  '@readium/shared@2.6.0':\n    resolution: {integrity: sha512-x}\n"),
          )
          const caught = fails('pnpm-lock.yaml holds @readium/shared at 2.6.0, 2.7.0')
          restore('pnpm-lock.yaml')
          return caught
        },
      ],
      [
        'an edited bundle is caught',
        () => {
          const pin = readJson(scratch, 'pin.json')
          edit(pin.file, (text) => `${text}\n/* patched in place */\n`)
          const caught = fails('does not match the recorded digest')
          restore('dist')
          return caught
        },
      ],
      [
        'a missing bundle is caught',
        () => {
          rmSync(join(scratch, 'dist'), { recursive: true, force: true })
          const caught = fails('is missing; run `pnpm build`')
          restore('dist')
          return caught
        },
      ],
    ]

    const failed = checks.filter(([, holds]) => !holds()).map(([name]) => name)
    if (failed.length > 0) {
      console.error(`epub bundle pin self-test failed: ${failed.join(', ')}`)
      process.exit(1)
    }
    console.log(`epub bundle pin self-test: ${checks.length} checks passed`)
    process.exit(0)
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
}

console.error('usage: node apps/desktop-web/epub/check-pin.mjs --check | --write | --self-test')
process.exit(2)
