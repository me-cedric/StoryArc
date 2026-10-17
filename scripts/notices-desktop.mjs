#!/usr/bin/env node
/**
 * The desktop half of the notices check (task 6.3 of desktop-clients).
 *
 * The iOS and Android entries of `packages/licences/notices.json` are written by hand next
 * to the manifest they describe. The desktop targets pull in 500-odd Rust crates and a few
 * NuGet packages, which nobody writes by hand, so the manifests are read instead:
 *
 *   Cargo.lock                     every crate with a registry or git source
 *   apps/desktop-windows/**.csproj every PackageReference
 *
 * and each must have a row in `packages/licences/desktop-deps.json`, which holds the
 * licence expression. Crate licences come from `cargo metadata --offline` (the crates.io
 * index cache on disk, no network) when `--write` refreshes the table; the check itself
 * only reads the committed table, so it needs neither cargo nor the registry.
 *
 * PDFium and libarchive are in notices.json already; the check here pins their versions to
 * `apps/desktop-core/pdfium/pin.json` and `third_party/libarchive/pin.json`.
 *
 * Usage (normally through scripts/notices.mjs):
 *   node scripts/notices-desktop.mjs --write      refresh the crate rows from cargo
 *   node scripts/notices-desktop.mjs --self-test
 */
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
export const TABLE = join(ROOT, 'packages/licences/desktop-deps.json')

/** `[{ name, version }]` for every crate that is not a workspace member. */
export function parseCargoLock(text) {
  const out = []
  for (const block of text.split(/^\[\[package\]\]\s*$/m).slice(1)) {
    const field = (key) => block.match(new RegExp(`^${key} = "([^"]*)"`, 'm'))?.[1]
    if (field('source')) out.push({ name: field('name'), version: field('version') })
  }
  return out
}

/** `[{ name, version }]` for every PackageReference of a project file. */
export function parseCsproj(xml) {
  return [...xml.matchAll(/<PackageReference\s+Include="([^"]+)"\s+Version="([^"]+)"/g)].map(
    (m) => ({ name: m[1], version: m[2] }),
  )
}

const key = (c) => `${c.name}@${c.version}`

/** The components with no row in the table, as `name@version`, sorted. */
export function unlisted(components, rows) {
  return [...new Set(components.map(key))].filter((k) => !rows[k]?.licence).sort()
}

/** Every problem of the desktop manifests: unlisted crates and packages, stale pins. */
export function problems({ lock, csprojs, table, notices, pdfiumPin, libarchivePin }) {
  const out = []
  for (const k of unlisted(parseCargoLock(lock), table.crates)) {
    out.push(`Rust crate ${k} has no row in packages/licences/desktop-deps.json (run: pnpm notices:write)`)
  }
  for (const k of unlisted(csprojs.flatMap(parseCsproj), table.nuget)) {
    out.push(`NuGet package ${k} has no row in packages/licences/desktop-deps.json`)
  }
  const named = (name) => notices.find((n) => n.name === name)
  const lib = named('libarchive')
  if (!lib) out.push('libarchive is not in notices.json')
  else if (lib.version !== libarchivePin.version) {
    out.push(`libarchive is ${lib.version} in notices.json but ${libarchivePin.version} in its pin`)
  }
  const pdf = named('PDFium')
  if (!pdf) out.push('PDFium is not in notices.json')
  else if (!pdf.version?.includes(pdfiumPin.tag)) {
    out.push(`PDFium is "${pdf.version}" in notices.json but the pin is ${pdfiumPin.tag}`)
  }
  return out
}

/** Every `.csproj` under `dir`, skipping build output. */
function findCsprojs(dir) {
  const out = []
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, e.name)
    if (e.isDirectory() && !['bin', 'obj', 'node_modules'].includes(e.name)) out.push(...findCsprojs(path))
    else if (e.name.endsWith('.csproj')) out.push(path)
  }
  return out
}

/** Reads the manifests off disk and returns the problems and the component count. */
export function checkDesktop(notices) {
  const read = (p) => readFileSync(join(ROOT, p), 'utf8')
  const lock = read('Cargo.lock')
  const csprojs = findCsprojs(join(ROOT, 'apps/desktop-windows')).map((p) => readFileSync(p, 'utf8'))
  const table = JSON.parse(readFileSync(TABLE, 'utf8'))
  const found = problems({
    lock,
    csprojs,
    table,
    notices,
    pdfiumPin: JSON.parse(read('apps/desktop-core/pdfium/pin.json')),
    libarchivePin: JSON.parse(read('third_party/libarchive/pin.json')),
  })
  const count = parseCargoLock(lock).length + csprojs.flatMap(parseCsproj).length
  return { problems: found, count, table }
}

/** Refreshes the crate rows from `cargo metadata --offline`. NuGet rows are kept: no tool lists them offline. */
function writeCrates() {
  const meta = JSON.parse(
    execFileSync('cargo', ['metadata', '--offline', '--format-version', '1', '--locked', '--all-features'], {
      cwd: ROOT,
      maxBuffer: 1 << 29,
      timeout: 120000,
      env: { ...process.env, CARGO_NET_OFFLINE: 'true' },
    }),
  )
  const table = JSON.parse(readFileSync(TABLE, 'utf8'))
  const crates = {}
  for (const p of meta.packages.filter((p) => p.source).sort((a, b) => key(a).localeCompare(key(b)))) {
    // A crate with only a licence file has no expression; `licence` then names the file.
    const licence = p.license ?? (p.license_file ? `SEE ${p.license_file}` : null)
    if (!licence) throw new Error(`${key(p)} declares no licence; add a row by hand`)
    crates[key(p)] = { licence, source: p.repository ?? p.homepage ?? 'https://crates.io/crates/' + p.name }
  }
  writeFileSync(TABLE, JSON.stringify({ ...table, crates }, null, 2) + '\n')
  console.log(`Wrote ${Object.keys(crates).length} crates to packages/licences/desktop-deps.json.`)
}

function selfTest() {
  const lock = [
    'version = 4',
    '[[package]]\nname = "storyarc-core"\nversion = "0.1.0"\n',
    '[[package]]\nname = "serde"\nversion = "1.0.229"\nsource = "registry+https://github.com/rust-lang/crates.io-index"\n',
    '[[package]]\nname = "zune-heic"\nversion = "0.5.0"\nsource = "registry+https://github.com/rust-lang/crates.io-index"\n',
  ].join('\n')
  assert.deepEqual(parseCargoLock(lock).map(key), ['serde@1.0.229', 'zune-heic@0.5.0'], 'workspace members are not components')

  const csproj = '<ItemGroup><PackageReference Include="Foo.Bar" Version="1.2.3" />\n<PackageReference Include="Baz" Version="4.5.6"/></ItemGroup>'
  assert.deepEqual(parseCsproj(csproj).map(key), ['Foo.Bar@1.2.3', 'Baz@4.5.6'])

  const ok = {
    lock,
    csprojs: [csproj],
    table: {
      crates: { 'serde@1.0.229': { licence: 'MIT' }, 'zune-heic@0.5.0': { licence: 'MIT' } },
      nuget: { 'Foo.Bar@1.2.3': { licence: 'MIT' }, 'Baz@4.5.6': { licence: 'MIT' } },
    },
    notices: [
      { name: 'libarchive', version: '3.8.9' },
      { name: 'PDFium', version: 'chromium/7881 (pdfium-binaries)' },
    ],
    pdfiumPin: { tag: 'chromium/7881' },
    libarchivePin: { version: '3.8.9' },
  }
  assert.deepEqual(problems(ok), [], 'a complete fixture passes')

  const without = (tbl, k) => ({ ...tbl, ...{ [k]: Object.fromEntries(Object.entries(tbl[k]).slice(1)) } })
  const crateGone = problems({ ...ok, table: without(ok.table, 'crates') })
  assert.equal(crateGone.length, 1)
  assert.match(crateGone[0], /Rust crate serde@1\.0\.229/, 'a missing crate fails by name')
  const pkgGone = problems({ ...ok, table: without(ok.table, 'nuget') })
  assert.equal(pkgGone.length, 1)
  assert.match(pkgGone[0], /NuGet package Foo\.Bar@1\.2\.3/, 'a missing package fails by name')

  const blank = { ...ok.table, crates: { ...ok.table.crates, 'serde@1.0.229': { licence: '' } } }
  assert.match(problems({ ...ok, table: blank })[0], /serde@1\.0\.229/, 'a row with no licence is no row')

  assert.match(problems({ ...ok, libarchivePin: { version: '3.9.0' } })[0], /libarchive is 3\.8\.9.*3\.9\.0/)
  assert.match(problems({ ...ok, pdfiumPin: { tag: 'chromium/9999' } })[0], /PDFium .*chromium\/9999/)
  assert.match(problems({ ...ok, notices: [] }).join('\n'), /libarchive is not in notices\.json[\s\S]*PDFium is not in/)
  console.log('notices-desktop self-test passed.')
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--self-test')) selfTest()
  else if (process.argv.includes('--write')) writeCrates()
  else {
    console.error('Usage: notices-desktop.mjs --write | --self-test')
    process.exit(1)
  }
}
