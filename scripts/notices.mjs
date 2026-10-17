#!/usr/bin/env node
/**
 * Generates THIRD_PARTY_NOTICES.md from the licence inventory.
 *
 * The file already told readers to "edit that and regenerate rather than editing this
 * file", and there was nothing to regenerate it with. So the table drifted from
 * `notices.json` the moment either changed, and a notices file that disagrees with what
 * the app ships is worse than none.
 *
 * The prose below the table is not generated. It holds judgements — the per-file
 * libarchive audit, what the platform SDKs are excluded for — and a generator has no
 * business rewriting a judgement. Everything between the markers is generated; everything
 * outside them is kept.
 *
 * Usage:
 *   node scripts/notices.mjs           rewrite the file
 *   node scripts/notices.mjs --check   fail if the file is out of date
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkDesktop } from './notices-desktop.mjs'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const INVENTORY = join(ROOT, 'packages/licences/notices.json')
const TARGET = join(ROOT, 'THIRD_PARTY_NOTICES.md')

const BEGIN = '<!-- generated:notices -->'
const END = '<!-- /generated:notices -->'

const PLATFORM_NAMES = { ios: 'iOS', android: 'Android', macos: 'macOS', windows: 'Windows', linux: 'Linux' }

const { notices } = JSON.parse(readFileSync(INVENTORY, 'utf8'))

// Escaped because a `why` may hold a pipe, and one pipe silently splits a table cell.
const cell = (text) => String(text).replaceAll('|', '\\|')

// The desktop manifests (Cargo.lock, the .csproj files) are read, not hand-listed; a component
// with no row in desktop-deps.json fails the check by name. See scripts/notices-desktop.mjs.
const desktop = checkDesktop(notices)
const DESKTOP_BEGIN = '<!-- generated:desktop -->'
const DESKTOP_END = '<!-- /generated:desktop -->'
const desktopRows = [
  ...Object.entries(desktop.table.nuget).map(([k, v]) => [`NuGet ${k.replace('@', ' ')}`, v]),
  ...Object.entries(desktop.table.crates).map(([k, v]) => [`Rust ${k.replace('@', ' ')}`, v]),
].map(([name, v]) => `| [${cell(name)}](${v.source}) | \`${cell(v.licence)}\` |`)
const desktopBlock = [
  DESKTOP_BEGIN,
  '| Component | Licence |',
  '| --- | --- |',
  ...desktopRows,
  DESKTOP_END,
].join('\n')

const platformsOf = (notice) =>
  notice.platforms?.length
    ? notice.platforms.map((p) => PLATFORM_NAMES[p] ?? p).join(', ')
    : 'iOS, Android'

const titleOf = (notice) =>
  notice.version ? `${notice.name} ${notice.version}` : notice.name

const rows = notices.map(
  (notice) =>
    `| [${cell(titleOf(notice))}](${notice.url}) | \`${notice.licence}\` | ` +
    `${platformsOf(notice)} | ${cell(notice.copyright ?? '—')} | ${cell(notice.why)} |`,
)

const missing = notices.filter((notice) => !notice.copyright).map((notice) => notice.name)

const table = [
  '| Component | Licence | Platform | Copyright | Why it is in the app |',
  '| --- | --- | --- | --- | --- |',
  ...rows,
].join('\n')

const generated = `${BEGIN}\n${table}\n${END}`

const current = readFileSync(TARGET, 'utf8')
const begins = current.indexOf(BEGIN)
const ends = current.indexOf(END)

let next
if (begins >= 0 && ends > begins) {
  next = current.slice(0, begins) + generated + current.slice(ends + END.length)
} else {
  // First run: replace whatever table is there, keeping the prose on both sides.
  const lines = current.split('\n')
  const first = lines.findIndex((line) => line.startsWith('| Component'))
  if (first < 0) {
    console.error(`No table found in ${TARGET}. Add the ${BEGIN} markers by hand once.`)
    process.exit(1)
  }
  let last = first
  while (last + 1 < lines.length && lines[last + 1].startsWith('|')) last += 1
  next = [...lines.slice(0, first), generated, ...lines.slice(last + 1)].join('\n')
}

// The desktop table follows the main one, under its own markers. First run: insert it after.
{
  const b = next.indexOf(DESKTOP_BEGIN)
  const e = next.indexOf(DESKTOP_END)
  if (b >= 0 && e > b) next = next.slice(0, b) + desktopBlock + next.slice(e + DESKTOP_END.length)
  else {
    const at = next.indexOf(END) + END.length
    next = `${next.slice(0, at)}

## Desktop dependencies

The Rust crates of \`Cargo.lock\` and the NuGet packages of \`apps/desktop-windows\`, read from
those manifests and joined to the licence expression in
[\`packages/licences/desktop-deps.json\`](packages/licences/desktop-deps.json). PDFium and
libarchive are in the table above. Each crate carries its own licence and copyright files in its
published package; a crate that offers \`MIT OR Apache-2.0\` is used under either.

${desktopBlock}${next.slice(at)}`
  }
}

if (process.argv.includes('--check')) {
  for (const problem of desktop.problems) console.error(problem)
  if (desktop.problems.length > 0) process.exitCode = 1
  if (next !== current) {
    console.error('THIRD_PARTY_NOTICES.md is out of date. Run: pnpm notices')
    process.exit(1)
  }
  console.log(`THIRD_PARTY_NOTICES.md is in sync (${notices.length} components, ${desktop.count} desktop packages).`)
} else {
  for (const problem of desktop.problems) console.error(problem)
  if (desktop.problems.length > 0) process.exit(1)
  writeFileSync(TARGET, next)
  console.log(`Wrote ${notices.length} components to THIRD_PARTY_NOTICES.md.`)
}

// A missing copyright line is a compliance gap, not a formatting one, so it is loud
// either way. BSD and Apache both require the real notice, and the SPDX template in
// texts/ says `Copyright (c) <year> <owner>`.
if (missing.length > 0) {
  console.error(`Missing a copyright line: ${missing.join(', ')}`)
  process.exitCode = 1
}
