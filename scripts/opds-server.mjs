#!/usr/bin/env node
// Serves the generated corpus as an OPDS catalogue, in both dialects.
//
// It exists because `opds-catalog` cannot be verified against a screenshot. The parser has
// unit tests; what those cannot show is whether a reader can type an address, get past a
// sign-in, and read a book. This is the server that makes that walkthrough possible on a
// simulator or an emulator, with no account anywhere.
//
// Usage: node scripts/opds-server.mjs [corpus-directory] [--port 4444]
//
// Routes, each one a case the spec names:
//   /opds            navigation feed, Atom (OPDS 1.2)
//   /opds/all        acquisition feed, paginated, with a language facet
//   /opds/series     navigation feed of series
//   /opds2           the same catalogue as OPDS 2.0 JSON, in two named groups
//   /private         401 until Basic ada:lovelace, then the acquisition feed
//   /bearer          401 until Bearer storyarc-token
//   /page            an HTML page, so the "that is not a feed" path is reachable
//   /empty           a 200 with no body
//   /files/<name>    the publication itself
//   /covers/<name>   a cover image

import { createServer } from 'node:http'
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, extname, basename } from 'node:path'
import { deflateSync } from 'node:zlib'

const args = process.argv.slice(2)
const portFlag = args.indexOf('--port')
const port = portFlag >= 0 ? Number(args[portFlag + 1]) : 4444
const root = args.find((a) => !a.startsWith('--') && a !== String(port)) ??
  join(process.env.HOME, 'StoryArcCorpus')

if (!existsSync(root)) {
  console.error(`no corpus at ${root} — run: node scripts/corpus.mjs ${root}`)
  process.exit(2)
}

const TYPES = {
  '.cbz': 'application/vnd.comicbook+zip',
  '.cbt': 'application/vnd.comicbook+tar',
  '.cb7': 'application/vnd.comicbook+7z',
  '.epub': 'application/epub+zip',
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
}

/** Everything in the corpus that is a file, with what little the filename says. */
const entries = readdirSync(root)
  .filter((name) => statSync(join(root, name)).isFile())
  .sort()
  .map((name, index) => {
    const stem = basename(name, extname(name))
    const numbered = /^(.*?)\s+(\d+)$/.exec(stem)
    return {
      id: `urn:storyarc:${index + 1}`,
      file: name,
      title: stem,
      series: numbered?.[1],
      index: numbered ? Number(numbered[2]) : undefined,
      type: TYPES[extname(name).toLowerCase()] ?? 'application/octet-stream',
      updated: statSync(join(root, name)).mtime.toISOString().replace(/\.\d+Z$/, 'Z'),
    }
  })

const PER_PAGE = 6

const escape = (value) => String(value)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')

/** A solid PNG, so a cover is a real image rather than a broken one. */
function cover(seed) {
  const width = 60
  const height = 90
  const raw = Buffer.alloc((width * 3 + 1) * height)
  const hue = [(seed * 67) % 200 + 40, (seed * 113) % 200 + 40, (seed * 199) % 200 + 40]
  for (let y = 0; y < height; y += 1) {
    const row = y * (width * 3 + 1)
    for (let x = 0; x < width; x += 1) {
      const shade = 1 - (y / height) * 0.35
      for (let channel = 0; channel < 3; channel += 1) {
        raw.writeUInt8(Math.round(hue[channel] * shade), row + 1 + x * 3 + channel)
      }
    }
  }
  const table = Array.from({ length: 256 }, (_, n) => {
    let c = n
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    return c >>> 0
  })
  const crc = (buffer) => {
    let c = 0xffffffff
    for (const byte of buffer) c = table[(c ^ byte) & 0xff] ^ (c >>> 8)
    return (c ^ 0xffffffff) >>> 0
  }
  const chunk = (type, body) => {
    const head = Buffer.alloc(8)
    head.writeUInt32BE(body.length, 0)
    head.write(type, 4, 'ascii')
    const tail = Buffer.alloc(4)
    tail.writeUInt32BE(crc(Buffer.concat([head.subarray(4), body])), 0)
    return Buffer.concat([head, body, tail])
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr.writeUInt8(8, 8)
  ihdr.writeUInt8(2, 9)
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

const OPDS_ATOM = 'application/atom+xml;profile=opds-catalog'

function navigationFeed(base) {
  const series = [...new Set(entries.map((e) => e.series).filter(Boolean))]
  return `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <id>${base}/opds</id>
  <title>StoryArc Test Catalogue</title>
  <updated>${new Date(0).toISOString().replace(/\.\d+Z$/, 'Z')}</updated>
  <link rel="self" href="/opds" type="${OPDS_ATOM};kind=navigation"/>
  <link rel="start" href="/opds" type="${OPDS_ATOM};kind=navigation"/>
  <link rel="search" href="/opds/all?q={searchTerms}" type="${OPDS_ATOM};kind=acquisition"/>
  <link rel="subsection" href="/opds/all" title="All publications"
        thr:count="${entries.length}" type="${OPDS_ATOM};kind=acquisition"/>
  <link rel="subsection" href="/opds/series" title="Series"
        thr:count="${series.length}" type="${OPDS_ATOM};kind=navigation"/>
  <link rel="subsection" href="/private" title="Members only"
        type="${OPDS_ATOM};kind=acquisition"/>
</feed>
`
}

function seriesFeed() {
  const series = [...new Set(entries.map((e) => e.series).filter(Boolean))].sort()
  return `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <id>urn:storyarc:series</id>
  <title>Series</title>
  <link rel="self" href="/opds/series" type="${OPDS_ATOM};kind=navigation"/>
  <link rel="up" href="/opds" type="${OPDS_ATOM};kind=navigation"/>
${series.map((name) => `  <link rel="subsection" href="/opds/all?series=${encodeURIComponent(name)}"
        title="${escape(name)}"
        thr:count="${entries.filter((e) => e.series === name).length}"
        type="${OPDS_ATOM};kind=acquisition"/>`).join('\n')}
</feed>
`
}

/// The publication the slow endpoint serves: any comic in the corpus will do.
const slowFile = entries.find((entry) => entry.file.endsWith('.cbz'))?.file ?? entries[0]?.file

function acquisitionFeed({ path, title, page, matching, query }) {
  const filtered = matching ? entries.filter(matching) : entries
  const start = page * PER_PAGE
  const shown = filtered.slice(start, start + PER_PAGE)
  const more = start + PER_PAGE < filtered.length
  const separator = path.includes('?') ? '&' : '?'
  const next = more
    ? `  <link rel="next" href="${path}${separator}page=${page + 1}" type="${OPDS_ATOM};kind=acquisition"/>`
    : ''

  return `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <id>urn:storyarc:${escape(title)}</id>
  <title>${escape(title)}${query ? ` — “${escape(query)}”` : ''}</title>
  <link rel="self" href="${path}" type="${OPDS_ATOM};kind=acquisition"/>
  <link rel="up" href="/opds" type="${OPDS_ATOM};kind=navigation"/>
${next}
  <link rel="http://opds-spec.org/facet" href="/opds/all?lang=en" title="English"
        opds:facetGroup="Language" opds:activeFacet="true" thr:count="${entries.length}"/>
  <link rel="http://opds-spec.org/facet" href="/opds/all?lang=fr" title="French"
        opds:facetGroup="Language" thr:count="0"/>
${page === 0 && !query && title === 'All publications' ? `  <entry>
    <id>urn:storyarc:flaky</id>
    <title>Flaky Transfer</title>
    <updated>${new Date(0).toISOString().replace(/\.\d+Z$/, 'Z')}</updated>
    <author><name>Ada Lovelace</name></author>
    <summary>Fails twice with 503, then succeeds. For watching the retry.</summary>
    <link rel="http://opds-spec.org/acquisition" href="/flaky/retry.cbz"
          type="application/vnd.comicbook+zip"/>
  </entry>
  <entry>
    <id>urn:storyarc:slow</id>
    <title>Slow Transfer</title>
    <updated>${new Date(0).toISOString().replace(/\.\d+Z$/, 'Z')}</updated>
    <author><name>Ada Lovelace</name></author>
    <summary>Takes 45 seconds. For watching a download survive the app going away.</summary>
    <link rel="http://opds-spec.org/acquisition"
          href="/files/${encodeURIComponent(slowFile)}?slow=45"
          type="application/vnd.comicbook+zip"/>
  </entry>
` : ''}${shown.map((entry) => `  <entry>
    <id>${entry.id}</id>
    <title>${escape(entry.title)}</title>
    <updated>${entry.updated}</updated>
    <author><name>Ada Lovelace</name></author>
    <summary>A test publication, ${escape(entry.type)}.</summary>
    <link rel="http://opds-spec.org/image" href="/covers/${encodeURIComponent(entry.file)}"
          type="image/png"/>
    <link rel="http://opds-spec.org/image/thumbnail"
          href="/covers/${encodeURIComponent(entry.file)}" type="image/png"/>
    <link rel="http://opds-spec.org/acquisition"
          href="/files/${encodeURIComponent(entry.file)}" type="${entry.type}"/>
  </entry>`).join('\n')}
</feed>
`
}

/** One publication in the OPDS 2.0 shape, shared by the feed and by its groups. */
function jsonPublication(entry) {
  return {
    metadata: {
      identifier: entry.id,
      title: entry.title,
      author: 'Ada Lovelace',
      modified: entry.updated,
      description: `A test publication, ${entry.type}.`,
      ...(entry.series
        ? { belongsTo: { series: { name: entry.series, position: entry.index } } }
        : {}),
    },
    images: [
      { href: `/covers/${encodeURIComponent(entry.file)}`, type: 'image/png', width: 600 },
      { href: `/covers/${encodeURIComponent(entry.file)}`, type: 'image/png', width: 120 },
    ],
    links: [
      {
        rel: 'http://opds-spec.org/acquisition',
        href: `/files/${encodeURIComponent(entry.file)}`,
        type: entry.type,
      },
    ],
  }
}

/** The same catalogue as OPDS 2.0, so the other dialect is reachable from one server. */
function jsonFeed(base) {
  return JSON.stringify({
    metadata: { title: 'StoryArc Test Catalogue (OPDS 2.0)' },
    links: [
      { rel: 'self', href: '/opds2', type: 'application/opds+json' },
      { rel: 'search', href: '/opds2?query={query}', templated: true },
    ],
    // Named groups, which is the thing OPDS 2.0 has and OPDS 1.2 does not. The first
    // carries a `self` link, so the browser has a "see all" to honour; the second does
    // not, so it is a group that is all there is.
    groups: [
      {
        metadata: { title: 'Recently added' },
        links: [{ rel: 'self', href: '/opds2/all', type: 'application/opds+json' }],
        publications: entries.slice(0, 4).map(jsonPublication),
      },
      {
        metadata: { title: 'Comics' },
        publications: entries
          .filter((entry) => entry.type.startsWith('application/vnd.comicbook'))
          .slice(0, 4)
          .map(jsonPublication),
      },
    ],
    navigation: [
      {
        title: 'All publications',
        href: '/opds2/all',
        type: 'application/opds+json',
        properties: { numberOfItems: entries.length },
      },
    ],
    facets: [
      {
        metadata: { title: 'Language' },
        links: [
          { title: 'English', href: '/opds2?lang=en', properties: { numberOfItems: entries.length } },
        ],
      },
    ],
    publications: entries.map(jsonPublication),
  }, null, 2)
}

function authorized(request, expected) {
  const header = request.headers.authorization
  if (!header) return false
  if (expected.scheme === 'Basic') {
    const [, encoded] = header.split(' ')
    return encoded && Buffer.from(encoded, 'base64').toString() === expected.value
  }
  return header === `Bearer ${expected.value}`
}

let flaky = 0

const server = createServer((request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`)
  // Logged, because the reason to run this server is to find out what the app actually
  // asks for. A request that never arrives is the answer to most "why is it blank".
  response.on('finish', () => {
    console.log(`${response.statusCode} ${request.method} ${request.url}`)
  })
  const base = `http://${request.headers.host}`
  const page = Number(url.searchParams.get('page') ?? 0)
  const query = url.searchParams.get('q') ?? url.searchParams.get('query')
  const series = url.searchParams.get('series')

  const send = (status, type, body) => {
    response.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' })
    response.end(body)
  }

  const matching = (entry) => (!series || entry.series === series) &&
    (!query || entry.title.toLowerCase().includes(query.toLowerCase()))

  switch (url.pathname) {
    case '/':
    case '/opds':
      return send(200, `${OPDS_ATOM};kind=navigation`, navigationFeed(base))

    case '/opds/series':
      return send(200, `${OPDS_ATOM};kind=navigation`, seriesFeed())

    case '/opds/all':
      return send(200, `${OPDS_ATOM};kind=acquisition`, acquisitionFeed({
        path: series ? `/opds/all?series=${encodeURIComponent(series)}` : '/opds/all',
        title: series ?? 'All publications',
        page,
        matching,
        query,
      }))

    case '/opds2':
    case '/opds2/all':
      return send(200, 'application/opds+json', jsonFeed(base))

    case '/private':
      if (!authorized(request, { scheme: 'Basic', value: 'ada:lovelace' })) {
        response.writeHead(401, {
          'WWW-Authenticate': 'Basic realm="StoryArc test catalogue"',
          'Content-Type': 'text/plain',
        })
        return response.end('sign in')
      }
      return send(200, `${OPDS_ATOM};kind=acquisition`, acquisitionFeed({
        path: '/private',
        title: 'Members only',
        page,
        matching,
      }))

    case '/bearer':
      if (!authorized(request, { scheme: 'Bearer', value: 'storyarc-token' })) {
        response.writeHead(401, {
          'WWW-Authenticate': 'Bearer realm="StoryArc test catalogue"',
          'Content-Type': 'text/plain',
        })
        return response.end('sign in')
      }
      return send(200, `${OPDS_ATOM};kind=acquisition`, acquisitionFeed({
        path: '/bearer',
        title: 'Token only',
        page,
        matching,
      }))

    // Not a feed, on purpose: a login wall is the usual answer from a wrong path, and the
    // spec requires the app to say which of these it received.
    case '/page':
      return send(200, 'text/html', '<!DOCTYPE html><html><body><h1>Sign in</h1></body></html>')

    case '/empty':
      return send(200, `${OPDS_ATOM};kind=acquisition`, '')

    default:
      break
  }

  if (url.pathname.startsWith('/covers/')) {
    const name = decodeURIComponent(url.pathname.slice('/covers/'.length))
    const index = entries.findIndex((entry) => entry.file === name)
    if (index < 0) return send(404, 'text/plain', 'no such publication')
    return send(200, 'image/png', cover(index + 1))
  }

  // A file that fails twice and then works, so the retry-with-backoff path can be watched
  // rather than reasoned about. `offline-downloads` retries three times; this proves the
  // second attempt happens and the third succeeds.
  if (url.pathname.startsWith('/flaky/')) {
    flaky += 1
    if (flaky % 3 !== 0) return send(503, 'text/plain', 'busy')
    const entry = entries.find((each) => each.file.endsWith('.cbz'))
    return send(200, entry.type, readFileSync(join(root, entry.file)))
  }

  if (url.pathname.startsWith('/files/')) {
    const name = decodeURIComponent(url.pathname.slice('/files/'.length))
    const entry = entries.find((each) => each.file === name)
    if (!entry) return send(404, 'text/plain', 'no such publication')
    const body = readFileSync(join(root, name))
    // `?slow=<seconds>` trickles the body out instead of sending it at once. A fixture
    // corpus is small enough that every download finishes before the app can be
    // backgrounded, which makes background transfer and pause both untestable. This
    // makes a download last long enough to interrupt.
    const slow = Number(url.searchParams.get('slow') ?? 0)
    if (!slow) return send(200, entry.type, body)
    response.writeHead(200, {
      'Content-Type': entry.type,
      'Content-Length': String(body.length),
      'Cache-Control': 'no-store',
    })
    const chunks = 20
    const size = Math.ceil(body.length / chunks)
    let sent = 0
    const tick = () => {
      if (sent >= body.length) return response.end()
      response.write(body.subarray(sent, sent + size))
      sent += size
      setTimeout(tick, (slow * 1000) / chunks)
    }
    return tick()
  }

  send(404, 'text/plain', 'no such route')
})

server.listen(port, () => {
  console.log(`opds: http://localhost:${port}/opds  (${entries.length} publications from ${root})`)
  console.log(`      /opds2 for OPDS 2.0, /private for Basic ada:lovelace,`)
  console.log(`      /bearer for Bearer storyarc-token, /page and /empty for the refusals`)
})
