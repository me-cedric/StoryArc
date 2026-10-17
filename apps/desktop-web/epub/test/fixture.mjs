// A Readium Web Publication Manifest and a positions list for one EPUB of
// packages/test-fixtures/ebooks, and a static server that plays the host's part: it answers
// the manifest and the archive's entries. The core builds both for real (design.md,
// Decision 6); this script is the smallest stand-in that lets the bundle be tested alone.
import { createServer } from 'node:http'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import { dirname, join, posix } from 'node:path'
import { readZip } from './zip.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
export const DIST = join(HERE, '..', 'dist', 'storyarc-epub.js')
export const EPUB = join(HERE, '..', '..', '..', '..', 'packages', 'test-fixtures', 'ebooks', 'fixture.epub')

const XHTML = 'application/xhtml+xml'
const TYPES = { '.xhtml': XHTML, '.png': 'image/png', '.css': 'text/css', '.json': 'application/json' }

const attribute = (tag, name) => tag.match(new RegExp(`${name}="([^"]*)"`))?.[1]

/**
 * The fixture's footnote and links. ch1.xhtml of the fixture has none, and the fixtures
 * directory is not this lane's to edit, so the server adds them to the bytes it answers:
 * a noteref with its note, an http link, a mailto link the reader must drop, and an
 * internal link.
 */
export function patchChapterOne(xhtml) {
  return xhtml
    .replace(
      '<html xmlns="http://www.w3.org/1999/xhtml">',
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">',
    )
    .replace(
      '<h1>Chapter One</h1>',
      '<h1>Chapter One</h1>\n' +
        '    <p id="links">Note<a id="noteref" epub:type="noteref" href="#fn1">1</a> ' +
        '<a id="out" href="OUTSIDE">out</a> <a id="mail" href="mailto:someone@example.com">mail</a> ' +
        '<a id="next" href="ch2.xhtml">next</a></p>\n' +
        '    <aside id="fn1" epub:type="footnote"><p>The footnote says so.</p></aside>',
    )
}

/**
 * @param {string} baseUrl where the server answers, no trailing slash
 * @param {string} [epub]
 */
export function buildPublication(baseUrl, epub = EPUB) {
  const zip = readZip(epub)
  const text = (name) => zip.get(name).bytes().toString('utf8')
  const rootfile = attribute(text('META-INF/container.xml').match(/<rootfile [^>]*>/)[0], 'full-path')
  const opf = text(rootfile)
  const root = posix.dirname(rootfile)
  const at = (href) => posix.join(root, href)

  const items = new Map(
    [...opf.matchAll(/<item [^>]*>/g)].map(([tag]) => [
      attribute(tag, 'id'),
      { href: at(attribute(tag, 'href')), type: attribute(tag, 'media-type'), properties: attribute(tag, 'properties') ?? '' },
    ]),
  )
  const navItem = [...items.values()].find((item) => item.properties.includes('nav'))
  const toc = [...text(navItem.href).matchAll(/<a href="([^"]+)">([^<]+)<\/a>/g)].map(([, href, title]) => ({
    href: at(href),
    title,
  }))
  const titleOf = new Map(toc.map((entry) => [entry.href, entry.title]))

  const spine = [...opf.matchAll(/<itemref [^>]*>/g)].map(([tag]) => items.get(attribute(tag, 'idref')))
  const counts = spine.map((item) => Math.max(1, Math.ceil(zip.get(item.href).compressedSize / 1024)))
  const total = counts.reduce((sum, count) => sum + count, 0)

  let position = 0
  const positions = spine.flatMap((item, index) =>
    Array.from({ length: counts[index] }, (_, page) => {
      position += 1
      return {
        href: item.href,
        type: item.type,
        title: titleOf.get(item.href),
        locations: { position, progression: page / counts[index], totalProgression: (position - 1) / total },
      }
    }),
  )

  const meta = (name) => opf.match(new RegExp(`<dc:${name}[^>]*>([^<]*)</dc:${name}>`))?.[1]
  const cover = [...items.values()].find((item) => item.properties.includes('cover-image'))
  const manifest = {
    '@context': 'https://readium.org/webpub-manifest/context.jsonld',
    metadata: {
      '@type': 'http://schema.org/Book',
      identifier: meta('identifier'),
      title: meta('title'),
      author: meta('creator'),
      language: [meta('language')],
    },
    links: [{ rel: 'self', href: `${baseUrl}/pub/manifest.json`, type: 'application/webpub+json' }],
    readingOrder: spine.map((item) => ({ href: item.href, type: item.type, title: titleOf.get(item.href) })),
    resources: [{ rel: 'cover', href: cover.href, type: cover.type }],
    toc,
  }
  return { manifest, positions, zip }
}

const HOST_PAGE = `<!doctype html>
<meta charset="utf-8">
<title>Bundle API test host</title>
<style>html,body{margin:0}#reader{width:800px;height:600px}</style>
<div id="reader"></div>
<script src="/storyarc-epub.js"></script>`

/** Starts the static server. `hits` lists every path asked for, so a test can see what was reached. */
export async function startServer() {
  const hits = []
  let publication
  let origin = ''
  const server = createServer((request, response) => {
    const path = new URL(request.url, 'http://x').pathname
    hits.push(path)
    const send = (status, type, body) => {
      response.writeHead(status, { 'content-type': type, 'cache-control': 'no-store' })
      response.end(body)
    }
    if (path === '/') return send(200, 'text/html', HOST_PAGE)
    if (path === '/storyarc-epub.js') return send(200, 'text/javascript', readFileSync(DIST))
    if (path === '/outside') return send(200, 'text/plain', 'the page left')
    if (path === '/pub/manifest.json') return send(200, 'application/webpub+json', JSON.stringify(publication.manifest))
    if (path.startsWith('/pub/')) {
      const entry = publication.zip.get(decodeURIComponent(path.slice(5)))
      if (!entry) return send(404, 'text/plain', 'no such entry')
      let bytes = entry.bytes()
      if (path.endsWith('/ch1.xhtml')) {
        bytes = Buffer.from(patchChapterOne(bytes.toString('utf8')).replace('OUTSIDE', `${origin}/outside`))
      }
      const extension = path.slice(path.lastIndexOf('.'))
      return send(200, TYPES[extension] ?? 'application/octet-stream', bytes)
    }
    return send(404, 'text/plain', 'not found')
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  origin = `http://127.0.0.1:${server.address().port}`
  publication = buildPublication(origin)
  return {
    origin,
    hits,
    manifest: publication.manifest,
    positions: publication.positions,
    close: () => new Promise((resolve) => server.close(resolve)),
  }
}
