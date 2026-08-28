#!/usr/bin/env node
// A mock Kavita server, enough of one to drive StoryArc's Kavita client against.
//
// It exists because nobody here has a Kavita server, and a client built against
// documentation alone is a client nobody has ever seen answer. This is not a reimplementation
// of Kavita: it is the shape of the handful of endpoints StoryArc calls, so the walkthrough
// -- enter a key, list libraries, open a series, read a chapter -- can be watched.
//
// When someone points StoryArc at a real Kavita and finds a difference, the fix belongs
// here as well as in the client, so the next person inherits the correction.
//
// Usage: node scripts/kavita-server.mjs [corpus-directory] [--port 5000]

import { createServer } from 'node:http'
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, extname, basename } from 'node:path'

const args = process.argv.slice(2)
const portFlag = args.indexOf('--port')
const port = portFlag >= 0 ? Number(args[portFlag + 1]) : 5000
const root = args.find((a) => !a.startsWith('--') && a !== String(port)) ??
  join(process.env.HOME, 'StoryArcCorpus')

if (!existsSync(root)) {
  console.error(`no corpus at ${root} — run: node scripts/corpus.mjs ${root}`)
  process.exit(2)
}

/** The one key this mock accepts, and the token it mints for it. */
const API_KEY = 'storyarc-test-key'
const TOKEN = 'mock-session-token'
const VERSION = '0.8.3'

const TYPES = {
  '.cbz': 'application/vnd.comicbook+zip',
  '.cbt': 'application/vnd.comicbook+tar',
  '.epub': 'application/epub+zip',
  '.pdf': 'application/pdf',
}

/** The corpus, arranged the way Kavita arranges things: libraries, series, chapters. */
const files = readdirSync(root)
  .filter((name) => statSync(join(root, name)).isFile() && TYPES[extname(name).toLowerCase()])
  .sort()

/** A series per stem-without-number, so "Tidal Reach 01..03" is one series of three. */
const series = []
for (const [index, file] of files.entries()) {
  const stem = basename(file, extname(file))
  const numbered = /^(.*?)\s+(\d+)$/.exec(stem)
  const name = numbered?.[1] ?? stem
  let found = series.find((each) => each.name === name)
  if (!found) {
    found = {
      id: series.length + 1,
      name,
      // Comics in one library, books in the other, which is how a reader's Kavita is
      // usually set up and exercises the library list having more than one row.
      libraryId: extname(file) === '.epub' || extname(file) === '.pdf' ? 2 : 1,
      chapters: [],
    }
    series.push(found)
  }
  found.chapters.push({
    id: index + 1,
    number: numbered?.[2] ?? '1',
    title: stem,
    file,
    pagesRead: 0,
    pages: 8,
  })
}

const libraries = [
  { id: 1, name: 'Comics', type: 0 },
  { id: 2, name: 'Books', type: 2 },
]

const send = (response, status, body, type = 'application/json') => {
  const payload = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body)
  response.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' })
  response.end(payload)
}

/** Whether the request carries the token this mock minted. */
const authorised = (request) =>
  request.headers.authorization === `Bearer ${TOKEN}`

const server = createServer((request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`)
  response.on('finish', () => {
    console.log(`${response.statusCode} ${request.method} ${request.url}`)
  })

  // Authentication is the one route that does not need a token.
  if (url.pathname === '/api/Plugin/authenticate') {
    if (url.searchParams.get('apiKey') !== API_KEY) {
      return send(response, 401, { message: 'unauthorised' })
    }
    return send(response, 200, { username: 'ada', token: TOKEN, apiKey: API_KEY })
  }

  if (url.pathname === '/api/Server/server-info') {
    return send(response, 200, { kavitaVersion: VERSION, installId: 'mock' })
  }

  if (!authorised(request)) {
    return send(response, 401, { message: 'token expired' })
  }

  if (url.pathname === '/api/Library/libraries') {
    return send(response, 200, libraries)
  }

  if (url.pathname === '/api/Series/all-v2' || url.pathname === '/api/Series') {
    const libraryId = Number(url.searchParams.get('libraryId') ?? 0)
    const shown = libraryId ? series.filter((each) => each.libraryId === libraryId) : series
    return send(response, 200, shown.map((each) => ({
      id: each.id,
      name: each.name,
      libraryId: each.libraryId,
      pages: each.chapters.reduce((total, chapter) => total + chapter.pages, 0),
      pagesRead: each.chapters.reduce((total, chapter) => total + chapter.pagesRead, 0),
    })))
  }

  if (url.pathname === '/api/Series/volumes') {
    const found = series.find((each) => each.id === Number(url.searchParams.get('seriesId')))
    if (!found) return send(response, 404, { message: 'no such series' })
    // One volume holding every chapter, plus the chapters again as "loose" so the client's
    // handling of both shapes is exercised.
    return send(response, 200, [{
      id: found.id * 100,
      number: 1,
      name: 'Volume 1',
      chapters: found.chapters.map((chapter) => ({
        id: chapter.id,
        number: chapter.number,
        title: chapter.title,
        pages: chapter.pages,
        pagesRead: chapter.pagesRead,
      })),
    }])
  }

  if (url.pathname === '/api/Download/chapter') {
    const id = Number(url.searchParams.get('chapterId'))
    const chapter = series.flatMap((each) => each.chapters).find((each) => each.id === id)
    if (!chapter) return send(response, 404, { message: 'no such chapter' })
    return send(
      response,
      200,
      readFileSync(join(root, chapter.file)),
      TYPES[extname(chapter.file).toLowerCase()],
    )
  }

  if (url.pathname === '/api/Reader/progress' && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const chapter = series.flatMap((each) => each.chapters)
        .find((each) => each.id === posted.chapterId)
      if (chapter) chapter.pagesRead = posted.pageNum ?? 0
      send(response, 200, {})
    })
    return undefined
  }

  if (url.pathname === '/api/Search/search') {
    const query = (url.searchParams.get('queryString') ?? '').toLowerCase()
    return send(response, 200, {
      series: series
        .filter((each) => each.name.toLowerCase().includes(query))
        .map((each) => ({ id: each.id, name: each.name, libraryId: each.libraryId })),
      chapters: [],
      persons: [],
      genres: [],
      tags: [],
    })
  }

  send(response, 404, { message: 'no such route' })
})

server.listen(port, () => {
  console.log(`kavita mock: http://localhost:${port}`)
  console.log(`  api key: ${API_KEY}   version: ${VERSION}`)
  console.log(`  ${libraries.length} libraries, ${series.length} series from ${root}`)
})
