#!/usr/bin/env node
// Downloads the pinned PDFium binary for one platform into `.build/pdfium/<platform>/` and
// checks it against apps/desktop-core/pdfium/pin.json before it is unpacked (ADR-0018,
// design.md Decision 7). The Rust core binds to the library at run time, so the tests of
// `src/pdf/` and the desktop apps need the file on disk; nothing in the package graph
// carries it. A tarball whose digest is not the pinned one is deleted and the run fails.
//
//   node scripts/pdfium-fetch.mjs                   the host's platform
//   node scripts/pdfium-fetch.mjs --platform linux-x64
//   node scripts/pdfium-fetch.mjs --check           say whether the host's library is there
//
// Platforms are the asset names of pin.json without `pdfium-` and `.tgz`: mac-arm64,
// mac-x64, linux-x64, linux-arm64, win-x64, win-arm64. The library lands in `lib/` (macOS,
// Linux) or `bin/` (Windows) under the platform folder; `STORYARC_PDFIUM_DIR` names that
// folder to the tests and the apps.

import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const PIN = join(ROOT, 'apps/desktop-core/pdfium/pin.json')
const BUILD = join(ROOT, '.build/pdfium')

const hostPlatform = () => {
  const os = { darwin: 'mac', linux: 'linux', win32: 'win' }[process.platform]
  const arch = { arm64: 'arm64', x64: 'x64' }[process.arch]
  if (!os || !arch) throw new Error(`no pinned PDFium for ${process.platform} ${process.arch}`)
  return `${os}-${arch}`
}

/** Where the library for `platform` is, or null. */
export function libraryDir(platform) {
  const folder = platform.startsWith('win') ? 'bin' : 'lib'
  const name = { mac: 'libpdfium.dylib', linux: 'libpdfium.so', win: 'pdfium.dll' }[platform.split('-')[0]]
  const dir = join(BUILD, platform, folder)
  return existsSync(join(dir, name)) ? dir : null
}

export async function fetchPdfium(platform) {
  const pin = JSON.parse(readFileSync(PIN, 'utf8'))
  const asset = `pdfium-${platform}.tgz`
  const expected = pin.assets?.[asset]
  if (!expected) throw new Error(`${asset} is not pinned in pin.json; pinned: ${Object.keys(pin.assets).join(', ')}`)

  const already = libraryDir(platform)
  if (already) return already

  const url = `${pin.repository}/releases/download/${encodeURIComponent(pin.tag)}/${asset}`
  const response = await fetch(url, { signal: AbortSignal.timeout(120_000) })
  if (!response.ok) throw new Error(`${url} answered ${response.status}`)
  const bytes = Buffer.from(await response.arrayBuffer())
  const found = createHash('sha256').update(bytes).digest('hex')
  if (found !== expected) {
    throw new Error(`${asset} does not match the pin: expected ${expected}, found ${found}. Not unpacked.`)
  }

  const dir = join(BUILD, platform)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  const tarball = join(dir, asset)
  writeFileSync(tarball, bytes)
  execFileSync('tar', ['-xzf', tarball, '-C', dir], { stdio: 'inherit' })
  rmSync(tarball)
  const lib = libraryDir(platform)
  if (!lib) throw new Error(`${asset} unpacked, but holds no library under ${dir}`)
  return lib
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2)
  const platform = args.includes('--platform') ? args[args.indexOf('--platform') + 1] : hostPlatform()
  if (args.includes('--check')) {
    const dir = libraryDir(platform)
    console.log(dir ? `pdfium: ${platform} library at ${dir}` : `pdfium: no ${platform} library; run pnpm pdfium:fetch`)
    process.exit(dir ? 0 : 1)
  }
  try {
    const dir = await fetchPdfium(platform)
    console.log(`pdfium: ${platform} library at ${dir}`)
  } catch (error) {
    console.error(`pdfium: ${error.message}`)
    process.exit(1)
  }
}
