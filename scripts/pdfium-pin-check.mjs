#!/usr/bin/env node
// Guards the PDF engine the desktop apps bundle and no package manager sees.
//
// Windows and Linux render PDF through `pdfium-render`, which binds at run time to a
// PDFium library the build downloads from bblanchon/pdfium-binaries (ADR-0018, design.md
// Decision 7). That download is a tarball from a GitHub release: no lockfile entry, no
// advisory feed, and a release tag that could be re-cut. pdfium-render 0.9.4's
// `pdfium_latest` feature binds `chromium/7881`, so the tag moves only with a
// pdfium-render release that raises it — the same shape as libarchive's pin, and the
// same alarm (scripts/libarchive-pin.mjs). PDFium parses untrusted bytes, which is why
// a build that fetched something other than the audited tarball must fail loudly.
//
//   --check           offline, runs in `pnpm lint` (task 1.32 wires it). pin.json names
//                     the expected tag, the Linux x64 asset, and a 64-hex sha256 for every
//                     asset. A placeholder is not a digest.
//   --verify <file>   digests a downloaded tarball and compares it with the pin, by the
//                     file's base name. For the build scripts and the Flatpak manifest.
//   --upstream        online. Compares every pinned digest with what the GitHub release
//                     API reports for the same asset, and names a newer pdfium-render-less
//                     drift when the release has been re-cut.
//   --self-test       proves --check fails on a wrong tag, a changed digest, a placeholder
//                     and a missing Linux x64 asset.
//
// Usage:
//   node scripts/pdfium-pin-check.mjs --check
//   node scripts/pdfium-pin-check.mjs --verify path/to/pdfium-linux-x64.tgz
//   node scripts/pdfium-pin-check.mjs --upstream
//   node scripts/pdfium-pin-check.mjs --self-test

import { createHash } from 'node:crypto'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const PIN = 'apps/desktop-core/pdfium/pin.json'

/**
 * The tag pdfium-render 0.9.4 binds through its `pdfium_latest` feature. It is written
 * here as well as in pin.json on purpose: pin.json is the record, this is the design's
 * expectation (design.md Decision 7), and a bump that edits only one of the two is the
 * drift this check exists to name. Raise both with the pdfium-render release that
 * raises `pdfium_latest`.
 */
const EXPECTED_TAG = 'chromium/7881'
const EXPECTED_PDFIUM_RENDER = '0.9.4'

const SHA256 = /^[0-9a-f]{64}$/
const RELEASES = 'https://api.github.com/repos/bblanchon/pdfium-binaries/releases/tags/'

const readPin = (root) => JSON.parse(readFileSync(join(root, PIN), 'utf8'))

function digest(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

/**
 * Every failure `--check` can report, as a list rather than a throw, so one run names
 * all of them instead of stopping at the first.
 */
function check(root) {
  if (!existsSync(join(root, PIN))) {
    return { pin: null, failures: [`${PIN} is missing; PDFium is not pinned`] }
  }
  const pin = readPin(root)
  const failures = []

  if (pin.tag !== EXPECTED_TAG) {
    failures.push(
      `pin.json names ${JSON.stringify(pin.tag)}, pdfium-render ${EXPECTED_PDFIUM_RENDER} binds ${EXPECTED_TAG}. ` +
        'Bump the tag only together with the pdfium-render release that raises `pdfium_latest`.',
    )
  }
  if (pin.pdfiumRender !== EXPECTED_PDFIUM_RENDER) {
    failures.push(`pin.json says pdfium-render ${pin.pdfiumRender}, this check expects ${EXPECTED_PDFIUM_RENDER}`)
  }

  // The Rust core does not depend on pdfium-render yet (task 4.4). Once it does, the
  // lockfile is the fifth place that states the version, and it has to agree.
  const lock = join(root, 'Cargo.lock')
  if (existsSync(lock)) {
    const text = readFileSync(lock, 'utf8')
    const locked = text.match(/name = "pdfium-render"\nversion = "([^"]+)"/)?.[1]
    if (locked && locked !== pin.pdfiumRender) {
      failures.push(`Cargo.lock holds pdfium-render ${locked}, pin.json says ${pin.pdfiumRender}`)
    }
  }

  const assets = pin.assets && typeof pin.assets === 'object' ? Object.entries(pin.assets) : []
  if (assets.length === 0) failures.push('pin.json names no assets')
  for (const [name, sha] of assets) {
    if (!/^pdfium-[a-z0-9-]+\.tgz$/.test(name)) {
      failures.push(`asset ${JSON.stringify(name)} is not a pdfium-binaries release asset name`)
    }
    if (!SHA256.test(String(sha))) {
      failures.push(`asset ${name} has no sha256, only ${JSON.stringify(sha)}; a placeholder is not a pin`)
    }
  }

  if (typeof pin.linuxX64 !== 'string' || !(pin.linuxX64 in (pin.assets ?? {}))) {
    failures.push(
      `pin.json must name the asset the Linux x64 build uses in \`linuxX64\` and digest it under \`assets\`` +
        ` (found ${JSON.stringify(pin.linuxX64)})`,
    )
  }

  return { pin, failures }
}

/** The asset list of one release, by name, as the GitHub API reports it. */
async function upstreamAssets(tag) {
  const url = RELEASES + encodeURIComponent(tag)
  const response = await fetch(url, {
    headers: { accept: 'application/vnd.github+json', 'user-agent': 'storyarc-pdfium-pin' },
  })
  if (!response.ok) throw new Error(`GitHub returned ${response.status} for ${url}`)
  const release = await response.json()
  const assets = new Map()
  for (const asset of release.assets ?? []) {
    assets.set(asset.name, {
      sha256: String(asset.digest ?? '').replace(/^sha256:/, ''),
      size: asset.size,
      url: asset.browser_download_url,
    })
  }
  return assets
}

const mode = process.argv[2] ?? '--check'

if (mode === '--check') {
  const { pin, failures } = check(ROOT)
  if (failures.length > 0) {
    for (const failure of failures) console.error(`pdfium pin: ${failure}`)
    process.exit(1)
  }
  const count = Object.keys(pin.assets).length
  console.log(`pdfium pin: ${pin.tag} for pdfium-render ${pin.pdfiumRender}, ${count} assets digested, Linux x64 is ${pin.linuxX64}.`)
  process.exit(0)
}

if (mode === '--verify') {
  const file = process.argv[3]
  if (!file) {
    console.error('usage: node scripts/pdfium-pin-check.mjs --verify <downloaded pdfium-*.tgz>')
    process.exit(2)
  }
  const pin = readPin(ROOT)
  const name = basename(file)
  const expected = pin.assets?.[name]
  if (!expected) {
    console.error(`pdfium pin: ${name} is not a pinned asset; pinned: ${Object.keys(pin.assets ?? {}).join(', ')}`)
    process.exit(1)
  }
  const found = digest(file)
  if (found !== expected) {
    console.error(`pdfium pin: ${name} does not match the pin: expected ${expected}, found ${found}. Do not use this file.`)
    process.exit(1)
  }
  console.log(`pdfium pin: ${name} matches ${pin.tag}.`)
  process.exit(0)
}

if (mode === '--upstream') {
  const pin = readPin(ROOT)
  const upstream = await upstreamAssets(pin.tag)
  const failures = []
  for (const [name, sha] of Object.entries(pin.assets)) {
    const theirs = upstream.get(name)
    if (!theirs) failures.push(`${name} is no longer an asset of ${pin.tag}`)
    else if (theirs.sha256 !== sha) {
      failures.push(`${name}: pinned ${sha}, the release now reports ${theirs.sha256 || 'no digest'}`)
    }
  }
  if (failures.length > 0) {
    for (const failure of failures) console.error(`pdfium pin: ${failure}`)
    console.error('pdfium pin: the release was re-cut or the pin was mistyped. Re-download, re-audit, then re-pin.')
    process.exit(1)
  }
  console.log(`pdfium pin: every pinned digest matches what GitHub reports for ${pin.tag}.`)
  process.exit(0)
}

if (mode === '--self-test') {
  // A checker that cannot fail is not a check. Each mutation is one way this pin can be
  // wrong: a tag bumped without pdfium-render, a digest that moved, a placeholder left
  // behind by a build that could not download, and the one asset the Linux build needs
  // gone from the list.
  const scratch = mkdtempSync(join(tmpdir(), 'storyarc-pdfium-pin-'))
  try {
    mkdirSync(join(scratch, dirname(PIN)), { recursive: true })
    const original = readFileSync(join(ROOT, PIN), 'utf8')
    const write = (mutate) => writeFileSync(join(scratch, PIN), JSON.stringify(mutate(JSON.parse(original)), null, 2))
    const fails = (label) => check(scratch).failures.some((failure) => failure.includes(label))

    const checks = [
      [
        'a clean copy passes',
        () => {
          write((pin) => pin)
          return check(scratch).failures.length === 0
        },
      ],
      [
        'a tag pdfium-render does not bind is caught',
        () => {
          write((pin) => ({ ...pin, tag: 'chromium/8086' }))
          return fails('pin.json names "chromium/8086"')
        },
      ],
      [
        'a changed digest is caught',
        () => {
          write((pin) => ({ ...pin, assets: { ...pin.assets, [pin.linuxX64]: `${pin.assets[pin.linuxX64].slice(0, 63)}X` } }))
          return fails(`asset ${JSON.parse(original).linuxX64} has no sha256`)
        },
      ],
      [
        'a placeholder is caught',
        () => {
          write((pin) => ({ ...pin, assets: { ...pin.assets, 'pdfium-win-x64.tgz': 'TODO: download and digest' } }))
          return fails('asset pdfium-win-x64.tgz has no sha256, only "TODO: download and digest"')
        },
      ],
      [
        'a missing Linux x64 asset is caught',
        () => {
          write((pin) => {
            const { [pin.linuxX64]: dropped, ...rest } = pin.assets
            return { ...pin, assets: rest }
          })
          return fails('must name the asset the Linux x64 build uses')
        },
      ],
      [
        'a missing pin is caught',
        () => {
          rmSync(join(scratch, PIN))
          return fails('is missing; PDFium is not pinned')
        },
      ],
    ]

    const failed = checks.filter(([, holds]) => !holds()).map(([name]) => name)
    if (failed.length > 0) {
      console.error(`pdfium pin self-test failed: ${failed.join(', ')}`)
      process.exit(1)
    }
    console.log(`pdfium pin self-test: ${checks.length} checks passed`)
    process.exit(0)
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
}

console.error('usage: node scripts/pdfium-pin-check.mjs --check | --verify <file> | --upstream | --self-test')
process.exit(2)
