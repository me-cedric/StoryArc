#!/usr/bin/env node
// Serves the generated corpus as an OPDS catalogue, in both dialects.
//
// It exists because `opds-catalog` cannot be verified against a screenshot. The parser has
// unit tests; what those cannot show is whether a reader can type an address, get past a
// sign-in, and read a book. This is the server that makes that walkthrough possible on a
// simulator or an emulator, with no account anywhere.
//
// Usage: node scripts/opds-server.mjs [corpus-directory] [--port 4444]
//        node scripts/opds-server.mjs --self-test
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
//   /files/<name>    the publication itself, byte-served — see `byteRange` below
//   /redirect/<name> a 302 to the file, so a redirect mid-stream is reachable
//   /covers/<name>   a cover image
//
// `/files/<name>` answers `Range`, which is what ADR-0008 needs a server to do: the first
// page of a 400 MB archive is three ranged reads, not 400 MB. It also answers it *badly*
// on demand, because a reader on someone's NAS meets servers that do — see `LIES`.

import { createServer, get as httpGet } from 'node:http'
import { readFileSync, readdirSync, statSync, existsSync, writeFileSync, mkdtempSync } from 'node:fs'
import { join, extname, basename } from 'node:path'
import { tmpdir } from 'node:os'
import { deflateSync } from 'node:zlib'

const args = process.argv.slice(2)
const selfTest = args.includes('--self-test')
const portFlag = args.indexOf('--port')
// Port zero for the self-test: it must not collide with a mock someone is already watching,
// and it has no reason to be reachable from outside its own process.
const port = selfTest ? 0 : portFlag >= 0 ? Number(args[portFlag + 1]) : 4444

/**
 * A corpus of known sizes and predictable bytes, for the self-test.
 *
 * Byte `n` of every file is `n % 251`, which makes a range verifiable on its own terms:
 * the answer to `bytes=1000-1015` is arithmetic rather than a second read of the same
 * server agreeing with the first. 251 rather than 256 so the pattern does not repeat on a
 * power-of-two boundary — an off-by-a-block bug would land on identical bytes and pass.
 */
const scratchCorpus = () => {
  const at = mkdtempSync(join(tmpdir(), 'storyarc-opds-test-'))
  for (const [name, size] of [
    ['Tidal Reach 01.cbz', 4096],
    ['Tidal Reach 02.cbz', 100],
    ['Winter Field.epub', 7],
  ]) {
    writeFileSync(at + '/' + name, Buffer.from(Array.from({ length: size }, (_, n) => n % 251)))
  }
  return at
}

const root = selfTest
  ? scratchCorpus()
  : args.find((a) => !a.startsWith('--') && a !== String(port)) ??
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
    const facts = statSync(join(root, name))
    return {
      id: `urn:storyarc:${index + 1}`,
      file: name,
      title: stem,
      series: numbered?.[1],
      index: numbered ? Number(numbered[2]) : undefined,
      type: TYPES[extname(name).toLowerCase()] ?? 'application/octet-stream',
      // What the acquisition link declares. `offline-downloads` requires a queued download
      // to show "its size", and a size nobody sends is a size the app can only learn by
      // starting the transfer it was meant to describe.
      size: facts.size,
      updated: facts.mtime.toISOString().replace(/\.\d+Z$/, 'Z'),
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
          href="/files/${encodeURIComponent(entry.file)}" type="${entry.type}"
          length="${entry.size}"/>
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
        // The Readium Link Object's own field — "original size of the resource in bytes".
        // OPDS 1.2 spells the same fact `length` on the Atom link; there is no third
        // spelling, and a mock that invented one would teach the parser a fiction.
        size: entry.size,
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

/**
 * One `Range` header, as a byte window into a body of `length` bytes.
 *
 * Null when there is nothing to honour — no header, or a header this mock does not speak.
 * RFC 9110 lets a server ignore a range it does not understand and answer 200 with the
 * whole resource, so a multi-range request lands here as null on purpose: that is the
 * behaviour a client meets in the wild, and it has to survive it rather than assume a 206.
 *
 * `unsatisfiable` is the third answer and a distinct one: bytes that are not there are a
 * 416, not a 404 and not a short 206.
 */
export function byteRange(header, length) {
  if (!header) return null
  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim())
  if (!match) return null
  const [, from, to] = match
  if (from === '' && to === '') return null
  if (from === '') {
    // `bytes=-500` is the last 500 bytes, and a suffix longer than the file is the file.
    const count = Number(to)
    if (count === 0) return { unsatisfiable: true }
    return { start: Math.max(0, length - count), end: length - 1 }
  }
  const start = Number(from)
  // A start at or past the end has no bytes to give. A zero-length body does not either,
  // which is why this is `>=` and why an empty file answers 416 to every range.
  if (start >= length) return { unsatisfiable: true }
  const end = to === '' ? length - 1 : Math.min(Number(to), length - 1)
  if (end < start) return { unsatisfiable: true }
  return { start, end }
}

/**
 * The ways this mock will answer a range wrongly, on request.
 *
 * Every one of these is something a real server, a proxy, or a captive portal has been
 * seen to do, and each is a case rather than a crash: the reader degrades to what the app
 * already does — download first, or say the source is unreachable — and never shows a page
 * built out of the wrong bytes. A client that only ever meets a correct server is a client
 * nobody has tested against the servers that exist.
 */
const LIES = {
  /** A 200 with the whole body where a 206 was asked for. Legal, and a client must cope. */
  ignore: 'answers 200 with the whole resource, ignoring the range',
  /** A 200 whose body is only the requested slice. The status and the bytes disagree. */
  status: 'answers 200 but sends only the requested slice',
  /** A 206 whose `Content-Range` names a total that is not the real length. */
  total: 'answers 206 with the wrong total in Content-Range',
  /** A 206 with correct headers and the bytes from somewhere else. */
  offset: 'answers 206 with the bytes of a different range',
  /** A 206 whose body is shorter than its own `Content-Range` claims. */
  short: 'answers 206 with fewer bytes than it promised',
  /** A 206 that stops writing halfway and destroys the socket. */
  cut: 'answers 206 and drops the connection mid-body',
}

/**
 * Sends `body`, honouring `Range`, and lying about it when asked to.
 *
 * The `Accept-Ranges: bytes` here is the advertisement ADR-0008 needs: without it a client
 * has no way to know a ranged read is worth attempting, and `offline-downloads` has to
 * state whether an interrupted download resumed or restarted.
 */
function sendBytes(request, response, type, body, { lie, ranges } = {}) {
  const headers = {
    'Content-Type': type,
    'Cache-Control': 'no-store',
    'Accept-Ranges': ranges === 'off' ? 'none' : 'bytes',
  }
  const whole = () => {
    response.writeHead(200, { ...headers, 'Content-Length': String(body.length) })
    response.end(body)
  }

  const window = ranges === 'off' ? null : byteRange(request.headers.range, body.length)
  if (!window || lie === 'ignore') return whole()
  if (window.unsatisfiable) {
    response.writeHead(416, { ...headers, 'Content-Range': `bytes */${body.length}` })
    return response.end()
  }

  const { start, end } = window
  const count = end - start + 1
  if (lie === 'status') {
    response.writeHead(200, { ...headers, 'Content-Length': String(count) })
    return response.end(body.subarray(start, end + 1))
  }

  // The bytes actually sent, which are the right ones unless asked otherwise. `offset`
  // shifts the window by a block without touching the headers, so the response is
  // well-formed and wrong — the failure a client cannot detect from the status line alone.
  const shifted = lie === 'offset' ? Math.min(start + 64, Math.max(0, body.length - count)) : start
  // `short` sends fewer bytes and *declares* fewer, so the message itself is well-formed
  // and only `Content-Range` is a lie. A body that contradicted its own `Content-Length`
  // would break at the transport instead, which is the case `cut` covers — and a source
  // that cannot tell the two apart cannot say whether the server or the link is at fault.
  const sending = lie === 'short' ? Math.max(0, count - 1) : count
  const slice = body.subarray(shifted, shifted + sending)
  const total = lie === 'total' ? body.length + 1024 : body.length
  response.writeHead(206, {
    ...headers,
    'Content-Range': `bytes ${start}-${end}/${total}`,
    'Content-Length': String(sending),
  })
  if (lie === 'cut') {
    // Destroyed from the write callback, not straight after it: destroying while bytes are
    // still buffered resets the connection before the client sees the status line, which
    // is a different failure — no answer at all, rather than an answer that stops.
    return response.write(slice.subarray(0, Math.ceil(sending / 2)), () => response.destroy())
  }
  response.end(slice)
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

  // A 302 to the file. `offline-downloads` has to survive a source that answers a range
  // request with a redirect — a captive portal, or a server that has moved the file — and
  // "survive" means degrading, not rendering whatever came back from the new address.
  if (url.pathname.startsWith('/redirect/')) {
    const name = url.pathname.slice('/redirect/'.length)
    response.writeHead(302, { Location: `/files/${name}${url.search}`, 'Cache-Control': 'no-store' })
    return response.end()
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
    if (!slow) {
      return sendBytes(request, response, entry.type, body, {
        lie: url.searchParams.get('lie'),
        ranges: url.searchParams.get('ranges'),
      })
    }
    // The slow path sends the whole body, whatever was asked for: it exists to be
    // interrupted, and a range would make it finish sooner, which is the opposite.
    response.writeHead(200, {
      'Content-Type': entry.type,
      'Content-Length': String(body.length),
      'Cache-Control': 'no-store',
      'Accept-Ranges': 'bytes',
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

/**
 * Drives the byte-serving against this mock, over HTTP, and says what broke.
 *
 * ADR-0008 turns "read one page of a 400 MB archive" into three ranged reads, and every one
 * of them is a promise this server has to keep: the bytes at the offset asked for, a total
 * that is the real total, a 416 rather than a short 206 for bytes that are not there. None
 * of that is visible from a parser unit test, because a parser is handed bytes rather than
 * fetching them — so this leaves the client entirely and is the mock talking to itself,
 * which is what makes it a contract rather than a shared assumption.
 *
 * The lies are checked as carefully as the truths. A mock that cannot misbehave on demand
 * cannot show that the reader degrades instead of rendering the wrong page.
 */
const drive = async () => {
  const base = `http://127.0.0.1:${server.address().port}`
  const failures = []
  let run = 0
  const check = (name, ok, saw) => {
    run += 1
    if (!ok) failures.push(saw === undefined ? name : `${name} (saw ${JSON.stringify(saw)})`)
  }

  const subject = entries.find((entry) => entry.size === 4096)
  const path = `/files/${encodeURIComponent(subject.file)}`
  const expected = readFileSync(join(root, subject.file))
  const get = (suffix, range) =>
    fetch(`${base}${suffix}`, { headers: range ? { Range: range } : {} })
  const bytes = async (answer) => Buffer.from(await answer.arrayBuffer())

  // Both dialects state the size, because a queue that cannot say how big a download is
  // cannot ask a reader to confirm it on a metered connection.
  const atom = await (await get('/opds/all')).text()
  check('the atom acquisition link declares its length',
    atom.includes(`length="${subject.size}"`))
  const json = await (await get('/opds2')).json()
  const link = json.publications
    .flatMap((each) => each.links)
    .find((each) => each.href.includes(encodeURIComponent(subject.file)))
  check('the opds 2.0 acquisition link declares its size', link?.size === subject.size, link?.size)

  const plain = await get(path)
  check('a file advertises that it takes ranges',
    plain.headers.get('accept-ranges') === 'bytes', plain.headers.get('accept-ranges'))
  check('a file with no range asked is whole',
    (await bytes(plain)).equals(expected))

  const head = await get(path, 'bytes=0-15')
  check('a range is answered 206', head.status === 206, head.status)
  check('a 206 says which bytes it is',
    head.headers.get('content-range') === `bytes 0-15/${subject.size}`,
    head.headers.get('content-range'))
  check('a range is the bytes asked for', (await bytes(head)).equals(expected.subarray(0, 16)))

  // The read ADR-0008 actually makes first: the tail, where a ZIP keeps its central
  // directory. An open-ended range and a suffix range are two spellings of it, and a
  // server that gets either wrong makes every archive unreadable at the first request.
  const openEnded = await get(path, `bytes=${subject.size - 16}-`)
  check('an open-ended range runs to the end',
    (await bytes(openEnded)).equals(expected.subarray(subject.size - 16)))
  const suffix = await get(path, 'bytes=-16')
  check('a suffix range is the last bytes',
    (await bytes(suffix)).equals(expected.subarray(subject.size - 16)))
  const oversized = await get(path, `bytes=-${subject.size + 500}`)
  check('a suffix longer than the file is the file',
    (await bytes(oversized)).equals(expected))

  // Bytes that are not there are a 416 with the real length in it, which is how a client
  // learns the length it guessed at was wrong without downloading anything.
  const past = await get(path, `bytes=${subject.size}-`)
  check('a range past the end is 416', past.status === 416, past.status)
  check('a 416 still states the length',
    past.headers.get('content-range') === `bytes */${subject.size}`,
    past.headers.get('content-range'))
  check('a backwards range is 416', (await get(path, 'bytes=40-20')).status === 416)
  // A file shorter than one read, which is the whole corpus on a bad day.
  const tiny = entries.find((entry) => entry.size === 7)
  const tinyTail = await bytes(await get(`/files/${encodeURIComponent(tiny.file)}`, 'bytes=-64'))
  check('a suffix range on a tiny file is the whole file',
    tinyTail.length === tiny.size, tinyTail.length)

  // And now the lies, each one a case rather than a crash.
  const lie = (name, range = 'bytes=0-15') => get(`${path}?lie=${name}`, range)
  const ignored = await get(`${path}?ranges=off`, 'bytes=0-15')
  check('a server that refuses ranges says so',
    ignored.status === 200 && ignored.headers.get('accept-ranges') === 'none',
    ignored.headers.get('accept-ranges'))
  check('a server that refuses ranges sends everything',
    (await bytes(ignored)).equals(expected))
  const ignoring = await lie('ignore')
  check('a 200 instead of a 206 carries the whole resource',
    ignoring.status === 200 && (await bytes(ignoring)).equals(expected), ignoring.status)
  const mismatched = await lie('status')
  check('a 200 carrying only a slice is reachable',
    mismatched.status === 200 && (await bytes(mismatched)).length === 16, mismatched.status)
  const wrongTotal = await lie('total')
  check('a wrong total in Content-Range is reachable',
    wrongTotal.headers.get('content-range') === `bytes 0-15/${subject.size + 1024}`,
    wrongTotal.headers.get('content-range'))
  const wrongBytes = await lie('offset')
  check('a well-formed 206 with the wrong bytes is reachable',
    !(await bytes(wrongBytes)).equals(expected.subarray(0, 16)))
  const shortBody = await bytes(await lie('short'))
  check('a 206 shorter than it promised is reachable', shortBody.length === 15, shortBody.length)
  // Read with the raw client rather than `fetch`: a body that stops mid-stream is the
  // event under test, and `IncomingMessage.complete` states it plainly where `fetch` only
  // throws. `complete` false with bytes already read is precisely "the source stopped
  // answering half way through", which the reader has to treat as a normal state.
  const cut = await new Promise((resolve) => {
    const asked = httpGet(`${base}${path}?lie=cut`, { headers: { Range: 'bytes=0-15' } }, (answer) => {
      let read = 0
      answer.on('data', (chunk) => { read += chunk.length })
      const done = () => resolve({ status: answer.statusCode, read, complete: answer.complete })
      answer.on('end', done)
      answer.on('error', done)
      answer.on('aborted', done)
    })
    asked.on('error', () => resolve({ status: 0, read: 0, complete: false }))
  })
  check('a connection dropped mid-body is reachable', !cut.complete && cut.read < 16, cut)

  const moved = await fetch(`${base}/redirect/${encodeURIComponent(subject.file)}`, {
    redirect: 'manual',
  })
  check('a redirect mid-stream is reachable', moved.status === 302, moved.status)

  server.close()
  if (failures.length) {
    console.error(`opds mock self-test failed: ${failures.join('; ')}`)
    process.exit(1)
  }
  console.log(`opds mock self-test: ${run} checks passed`)
}

if (selfTest) {
  server.listen(0, '127.0.0.1', () => { drive() })
} else {
  server.listen(port, () => {
    console.log(`opds: http://localhost:${port}/opds  (${entries.length} publications from ${root})`)
    console.log(`      /opds2 for OPDS 2.0, /private for Basic ada:lovelace,`)
    console.log(`      /bearer for Bearer storyarc-token, /page and /empty for the refusals`)
    console.log(`      /files/<name> takes Range; add ?lie=<${Object.keys(LIES).join('|')}>`)
    console.log(`      or ?ranges=off to watch the app meet a server that answers badly`)
  })
}
