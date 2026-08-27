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

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const INVENTORY = join(ROOT, 'packages/licences/notices.json')
const TARGET = join(ROOT, 'THIRD_PARTY_NOTICES.md')

const BEGIN = '<!-- generated:notices -->'
const END = '<!-- /generated:notices -->'

const PLATFORM_NAMES = { ios: 'iOS', android: 'Android' }

const { notices } = JSON.parse(readFileSync(INVENTORY, 'utf8'))

const platformsOf = (notice) =>
  notice.platforms?.length
    ? notice.platforms.map((p) => PLATFORM_NAMES[p] ?? p).join(', ')
    : 'iOS, Android'

const titleOf = (notice) =>
  notice.version ? `${notice.name} ${notice.version}` : notice.name

// Escaped because a `why` may hold a pipe, and one pipe silently splits a table cell.
const cell = (text) => String(text).replaceAll('|', '\\|')

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

if (process.argv.includes('--check')) {
  if (next !== current) {
    console.error('THIRD_PARTY_NOTICES.md is out of date. Run: pnpm notices')
    process.exit(1)
  }
  console.log(`THIRD_PARTY_NOTICES.md is in sync (${notices.length} components).`)
} else {
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
