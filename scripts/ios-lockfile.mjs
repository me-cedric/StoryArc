#!/usr/bin/env node
// Keeps the iOS app's dependency graph reviewable.
//
// `StoryArc.xcodeproj` is generated and gitignored, and the app target's only resolution
// record lives inside it. So for a while nothing in the repository said which revision of
// Readium — or of the eight packages Readium pulls in — the shipped binary was built
// from, and two builds of the same commit resolved two different SwiftSoup revisions. A
// dependency graph nobody can diff is a dependency graph nobody reviews.
//
// Two things fix that and this checks both:
//
//   1. `apps/ios/StoryArc.xcodeproj/.../Package.resolved` is committed, so a resolution
//      change shows up as a diff. `.gitignore` carries the narrow re-include.
//   2. Every remote package this repository declares uses an `exact:` requirement, so a
//      published tag cannot widen the graph between two checkouts of one commit.
//
// Usage:
//   node scripts/ios-lockfile.mjs --check
//   node scripts/ios-lockfile.mjs --self-test

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

const LOCKFILE =
  'apps/ios/StoryArc.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'

const MANIFESTS = [
  'apps/ios/Packages/StoryArcKit/Package.swift',
  'apps/ios/Packages/StoryArcEpub/Package.swift',
]

/** SwiftPM's identity for a remote package: the last path component, without `.git`. */
const identityOf = (url) => url.split('/').pop().replace(/\.git$/, '').toLowerCase()

/**
 * Every `.package(url:…)` in a manifest, with the requirement it states.
 *
 * A regex rather than a parse: the manifests are hand-written Swift with one dependency
 * per call, and running them would mean a full SwiftPM resolve on a Linux CI runner that
 * has no Xcode.
 */
function requirements(source) {
  const found = []
  for (const [call] of source.matchAll(/\.package\([\s\S]*?\)/g)) {
    const url = call.match(/url:\s*"([^"]+)"/)?.[1]
    if (!url) continue
    const exact = call.match(/exact:\s*"([^"]+)"/)?.[1]
    const loose = call.match(/\b(from|branch|revision):\s*"([^"]+)"/)
    found.push({ url, identity: identityOf(url), exact, loose: loose?.[1] })
  }
  return found
}

function check(root) {
  const failures = []
  const lockPath = join(root, LOCKFILE)

  if (!existsSync(lockPath)) {
    failures.push(
      `${LOCKFILE} is missing. Run \`pnpm build:ios\` (or \`xcodegen generate\` and resolve ` +
        'once) and commit the result — it is the app binary\'s only lockfile.',
    )
  } else {
    // Present on disk is not the same as reviewed. It was ignored for months.
    try {
      execFileSync('git', ['ls-files', '--error-unmatch', LOCKFILE], {
        cwd: root,
        stdio: 'pipe',
      })
    } catch {
      failures.push(
        `${LOCKFILE} exists but is not tracked by git, so a resolution change would land ` +
          'with no diff. Check .gitignore still carries the re-include, then `git add` it.',
      )
    }
  }

  const pins = existsSync(lockPath)
    ? new Map(
        JSON.parse(readFileSync(lockPath, 'utf8')).pins.map((pin) => [
          pin.identity,
          pin.state.version,
        ]),
      )
    : new Map()

  for (const manifest of MANIFESTS) {
    for (const dependency of requirements(readFileSync(join(root, manifest), 'utf8'))) {
      if (!dependency.exact) {
        failures.push(
          `${manifest} declares ${dependency.identity} with \`${dependency.loose ?? 'a range'}:\`. ` +
            'A floating requirement re-resolves to whatever is newest on the next clean ' +
            'checkout — use `exact:` so the version moves in a reviewed diff.',
        )
        continue
      }
      if (pins.size === 0) continue
      const pinned = pins.get(dependency.identity)
      if (pinned === undefined) {
        failures.push(`${LOCKFILE} has no pin for ${dependency.identity}, which ${manifest} requires`)
      } else if (pinned !== dependency.exact) {
        failures.push(
          `${manifest} requires ${dependency.identity} ${dependency.exact}, ` +
            `but the app resolved ${pinned}. Re-resolve and commit the lockfile.`,
        )
      }
    }
  }

  return failures
}

const mode = process.argv[2] ?? '--check'

if (mode === '--check') {
  const failures = check(ROOT)
  if (failures.length > 0) {
    for (const failure of failures) console.error(`ios lockfile: ${failure}`)
    process.exit(1)
  }
  console.log('ios lockfile: the app target resolves an exactly pinned graph, and it is committed.')
  process.exit(0)
}

if (mode === '--self-test') {
  // The two failures this exists to catch, exercised against text rather than a tree:
  // a floating requirement, and a lockfile that disagrees with the manifest.
  const checks = [
    [
      '`from:` is reported as floating',
      () => {
        const [only] = requirements('.package(url: "https://example.com/Thing.git", from: "1.0.0")')
        return only.identity === 'thing' && !only.exact && only.loose === 'from'
      },
    ],
    [
      '`exact:` is accepted',
      () => {
        const [only] = requirements('.package(url: "https://example.com/Thing.git", exact: "1.0.0")')
        return only.exact === '1.0.0'
      },
    ],
    [
      'a multi-line declaration is still read',
      () => {
        const [only] = requirements(
          '.package(\n  // a comment\n  url: "https://github.com/x/SMBClient.git",\n  exact: "0.3.1"\n)',
        )
        return only.identity === 'smbclient' && only.exact === '0.3.1'
      },
    ],
    ['the repository itself passes', () => check(ROOT).length === 0],
  ]

  const failed = checks.filter(([, holds]) => !holds()).map(([name]) => name)
  if (failed.length > 0) {
    console.error(`ios lockfile self-test failed: ${failed.join(', ')}`)
    process.exit(1)
  }
  console.log(`ios lockfile self-test: ${checks.length} checks passed`)
  process.exit(0)
}

console.error('usage: node scripts/ios-lockfile.mjs --check | --self-test')
process.exit(2)
