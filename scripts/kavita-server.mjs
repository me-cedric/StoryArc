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
//        node scripts/kavita-server.mjs --self-test

import { png } from './png.mjs'
import { createServer } from 'node:http'
import { readFileSync, readdirSync, statSync, existsSync, writeFileSync, mkdtempSync } from 'node:fs'
import { join, extname, basename } from 'node:path'
import { tmpdir } from 'node:os'

const args = process.argv.slice(2)
const selfTest = args.includes('--self-test')
const portFlag = args.indexOf('--port')
// Port zero for the self-test: it must not collide with a mock someone is already watching,
// and it has no reason to be reachable from outside its own process.
const port = selfTest ? 0 : portFlag >= 0 ? Number(args[portFlag + 1]) : 5000

/**
 * A corpus of the right shape and none of the right bytes, for the self-test.
 *
 * The routes under test never open a file — only `Download/chapter` does, and it hands back
 * whatever is there. So what matters is the names: two numbered files are one series of two,
 * which is what the continue point needs to have somewhere to move on to, and they sort
 * first so that series is the one the drive below picks up. The book makes a second library.
 */
const scratchCorpus = () => {
  const at = mkdtempSync(join(tmpdir(), 'storyarc-kavita-test-'))
  for (const name of ['Tidal Reach 01.cbz', 'Tidal Reach 02.cbz', 'Winter Field.epub']) {
    writeFileSync(join(at, name), Buffer.from('not a real publication'))
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

/** The colours covers are drawn in, one per series, so a wrong cover is visible. */
const COVERS = [
  [214, 90, 44], [58, 96, 158], [72, 138, 96],
  [148, 78, 148], [176, 148, 52], [96, 108, 128], [188, 64, 96],
]

/**
 * Metadata the server holds, which the spec says wins over the file's own.
 *
 * Deliberately disagrees with what `ComicInfo.xml` in the corpus says, so a client that
 * quietly prefers the file is visible rather than merely unproven.
 */
const metadata = new Map(series.map((each, index) => [each.id, {
  seriesId: each.id,
  summary: `${each.name} is a fixture series held by the StoryArc Kavita mock. ` +
    'The server is the curated source, so this text wins over anything in the file.',
  genres: [{ id: 1, title: 'Fixture' }, { id: 2, title: index % 2 ? 'Drama' : 'Adventure' }],
  tags: [{ id: 3, title: 'test-corpus' }],
  writers: [{ id: 4, name: 'Ada Lovelace' }],
  publishers: [{ id: 5, name: 'StoryArc Press' }],
  ageRating: 0,
  releaseYear: 2020 + (index % 5),
  publicationStatus: index % 3,
}]))

/**
 * Collections and reading lists the server holds.
 *
 * Kavita calls a collection a tag and a reading list a list, and they differ in kind: a
 * collection groups series and has no order, a list is an ordered run of chapters. The mock
 * keeps that difference rather than flattening it, because a client that treats them alike
 * is a client that will lose someone's order.
 */
const collections = [
  { id: 1, title: 'Staff picks', summary: 'What the mock recommends.', seriesIds: [] },
  { id: 2, title: 'Long reads', summary: 'Series with more than one chapter.', seriesIds: [] },
]

const readingLists = [
  { id: 1, title: 'Start here', summary: 'One chapter from each library.', items: [] },
]

const libraries = [
  { id: 1, name: 'Comics', type: 0 },
  { id: 2, name: 'Books', type: 2 },
]

// Filled once the corpus is known: the first two series, and every series with more than
// one chapter. Computed rather than hard-coded so the mock follows whatever corpus it is
// pointed at.
collections[0].seriesIds = series.slice(0, 2).map((each) => each.id)
collections[1].seriesIds = series.filter((each) => each.chapters.length > 1).map((e) => e.id)
readingLists[0].items = series.slice(0, 3).map((each, order) => ({
  id: order + 1,
  order,
  seriesId: each.id,
  chapterId: each.chapters[0].id,
  title: each.chapters[0].title,
  seriesName: each.name,
}))

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
  if (!selfTest) {
    response.on('finish', () => {
      console.log(`${response.statusCode} ${request.method} ${request.url}`)
    })
  }

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

  // Kavita's image endpoints take the key in the query rather than a bearer token, so an
  // <img> can point straight at them. Checked before the token gate for that reason.
  if (url.pathname.startsWith('/api/Image/')) {
    if (url.searchParams.get('apiKey') !== API_KEY) {
      return send(response, 401, { message: 'unauthorised' })
    }
    const id = Number(
      url.searchParams.get('seriesId') ?? url.searchParams.get('chapterId') ?? 0,
    )
    if (!id) return send(response, 400, { message: 'no id' })
    return send(response, 200, png(300, 450, COVERS[id % COVERS.length]), 'image/png')
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

  // One series by identity. A search result names a series without always naming the library
  // it sits in, and Kavita keys progress by both -- so opening a found series asks here first.
  if (/^\/api\/Series\/\d+$/.test(url.pathname)) {
    const found = series.find((each) => each.id === Number(url.pathname.split('/').pop()))
    if (!found) return send(response, 404, { message: 'no such series' })
    return send(response, 200, {
      id: found.id,
      name: found.name,
      libraryId: found.libraryId,
      pages: found.chapters.reduce((total, chapter) => total + chapter.pages, 0),
      pagesRead: found.chapters.reduce((total, chapter) => total + chapter.pagesRead, 0),
    })
  }

  if (url.pathname === '/api/Series/metadata') {
    const found = metadata.get(Number(url.searchParams.get('seriesId')))
    if (!found) return send(response, 404, { message: 'no such series' })
    return send(response, 200, found)
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

  // The chapter a reader should open next: the first unfinished one, or the first of all
  // when nothing has been read. Kavita answers this itself so a client does not have to
  // guess from progress it may not have pulled yet.
  if (url.pathname === '/api/Reader/continue-point') {
    const found = series.find((each) => each.id === Number(url.searchParams.get('seriesId')))
    if (!found) return send(response, 404, { message: 'no such series' })
    const next = found.chapters.find((each) => each.pagesRead < each.pages) ?? found.chapters[0]
    return send(response, 200, {
      id: next.id,
      number: next.number,
      title: next.title,
      pages: next.pages,
      pagesRead: next.pagesRead,
    })
  }

  // Kavita's own way of saying "I have read this" without having turned the pages.
  const marking = url.pathname === '/api/Reader/mark-chapter-read' ||
    url.pathname === '/api/Reader/mark-chapter-unread'
  if (marking && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const chapter = series.flatMap((each) => each.chapters)
        .find((each) => each.id === posted.chapterId)
      if (!chapter) return send(response, 404, { message: 'no such chapter' })
      chapter.pagesRead = url.pathname.endsWith('unread') ? 0 : chapter.pages
      send(response, 200, {})
    })
    return undefined
  }

  if (url.pathname === '/api/Reader/progress' && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const chapter = series.flatMap((each) => each.chapters)
        .find((each) => each.id === posted.chapterId)
      // Kavita's `pageNum` is the page the reader is on, counted from zero, so the number
      // of pages read is one more than that.
      if (chapter) chapter.pagesRead = Math.min((posted.pageNum ?? 0) + 1, chapter.pages)
      send(response, 200, {})
    })
    return undefined
  }

  if (url.pathname === '/api/Collection') {
    return send(response, 200, collections.map(({ id, title, summary }) => ({
      id,
      title,
      summary,
    })))
  }

  if (url.pathname === '/api/Collection/series') {
    const found = collections.find((each) => each.id === Number(url.searchParams.get('collectionId')))
    if (!found) return send(response, 404, { message: 'no such collection' })
    return send(response, 200, series
      .filter((each) => found.seriesIds.includes(each.id))
      .map((each) => ({
        id: each.id,
        name: each.name,
        libraryId: each.libraryId,
        pages: each.chapters.reduce((total, chapter) => total + chapter.pages, 0),
        pagesRead: each.chapters.reduce((total, chapter) => total + chapter.pagesRead, 0),
      })))
  }

  if (url.pathname === '/api/ReadingList/lists') {
    return send(response, 200, readingLists.map(({ id, title, summary }) => ({
      id,
      title,
      summary,
    })))
  }

  // A local list copied onto the server, per `collections-and-reading-lists`. The server
  // mints the id, which is what the client then addresses the entries and the undo by.
  if (url.pathname === '/api/ReadingList/create' && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const made = {
        id: Math.max(0, ...readingLists.map((each) => each.id)) + 1,
        title: posted.title ?? '',
        summary: null,
        items: [],
      }
      readingLists.push(made)
      send(response, 200, { id: made.id, title: made.title, summary: made.summary })
    })
    return undefined
  }

  // The other half of that copy: an undo inside its ten seconds asks the server to drop the
  // list again, so a mistake leaves nothing behind for other Kavita clients to see.
  if (url.pathname === '/api/ReadingList' && request.method === 'DELETE') {
    const at = readingLists.findIndex((each) => each.id === Number(url.searchParams.get('readingListId')))
    if (at < 0) return send(response, 404, { message: 'no such list' })
    readingLists.splice(at, 1)
    return send(response, 200, true)
  }

  if (url.pathname === '/api/ReadingList/items') {
    const found = readingLists.find((each) => each.id === Number(url.searchParams.get('readingListId')))
    if (!found) return send(response, 404, { message: 'no such list' })
    return send(response, 200, found.items)
  }

  if (url.pathname === '/api/ReadingList/update-by-multiple' && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const list = readingLists.find((each) => each.id === posted.readingListId)
      if (!list) return send(response, 404, { message: 'no such list' })
      for (const chapterId of posted.chapterIds ?? []) {
        if (list.items.some((item) => item.chapterId === chapterId)) continue
        const owner = series.find((each) => each.chapters.some((c) => c.id === chapterId))
        const chapter = owner?.chapters.find((c) => c.id === chapterId)
        if (!owner || !chapter) continue
        list.items.push({
          id: list.items.length + 1,
          order: list.items.length,
          seriesId: owner.id,
          chapterId,
          title: chapter.title,
          seriesName: owner.name,
        })
      }
      send(response, 200, {})
    })
    return undefined
  }

  // `kavita-server` asks a server-side search for matches "across series, chapters, people,
  // genres, and tags". The client reads all five now, so the mock answers with all five --
  // a mock that only ever returned series could not tell a working reader from a broken one.
  if (url.pathname === '/api/Search/search') {
    const query = (url.searchParams.get('queryString') ?? '').toLowerCase()
    const matches = (text) => (text ?? '').toLowerCase().includes(query)
    const chapters = []
    for (const each of series) {
      for (const chapter of each.chapters) {
        if (!matches(chapter.title)) continue
        chapters.push({
          id: chapter.id,
          // A search result names a chapter's title `titleName`, where a volume calls it
          // `title`. The difference is Kavita's own, and both clients read both spellings.
          titleName: chapter.title,
          number: chapter.number,
          seriesId: each.id,
        })
      }
    }
    return send(response, 200, {
      series: series
        .filter((each) => matches(each.name))
        .map((each) => ({ id: each.id, name: each.name, libraryId: each.libraryId })),
      chapters,
      // Kavita spells a person's name `name` and a genre's `title`; both clients take either.
      persons: [{ id: 1, name: 'Ada Okonkwo' }].filter((each) => matches(each.name)),
      genres: [{ id: 1, title: 'Adventure' }].filter((each) => matches(each.title)),
      tags: [{ id: 2, title: 'Ongoing' }].filter((each) => matches(each.title)),
    })
  }

  send(response, 404, { message: 'no such route' })
})

/**
 * Drives the progress round trip against this mock, over HTTP, and says what broke.
 *
 * The push half of `reading-progress` is a number that crosses a wire and comes back
 * meaning the same thing, and the one place it can go wrong silently is the off-by-one:
 * Kavita's `pageNum` is the page the reader is *on*, counted from zero, and its `pagesRead`
 * is how many they have *read*. A client that confuses the two loses a page on every sync
 * and no test that never leaves the client can see it. So this leaves the client entirely —
 * it is the mock talking to itself, which is exactly what makes it a contract rather than a
 * shared assumption.
 */
const drive = async () => {
  const base = `http://127.0.0.1:${server.address().port}`
  const failures = []
  let run = 0
  const check = (name, ok, saw) => {
    run += 1
    if (!ok) failures.push(saw === undefined ? name : `${name} (saw ${JSON.stringify(saw)})`)
  }

  const post = (path, body, token) => fetch(`${base}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body ?? {}),
  })
  const get = (path, token) =>
    fetch(`${base}${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} })

  // A key that is not the key gets nothing, and no route answers without a token.
  check('a wrong api key is refused',
    (await post('/api/Plugin/authenticate?apiKey=wrong&pluginName=StoryArc')).status === 401)
  check('an unauthenticated request is refused',
    (await get('/api/Library/libraries')).status === 401)

  const authenticated = await post(`/api/Plugin/authenticate?apiKey=${API_KEY}&pluginName=StoryArc`)
  const account = await authenticated.json()
  check('the key mints a token', typeof account.token === 'string' && account.token.length > 0)
  const token = account.token

  const volumes = async (seriesId) => (await get(`/api/Series/volumes?seriesId=${seriesId}`, token)).json()
  const first = series[0]
  const chapter = first.chapters[0]

  const before = (await volumes(first.id))[0].chapters[0]
  check('a chapter nobody has read reports nothing read', before.pagesRead === 0, before.pagesRead)
  check('a chapter reports how long it is', before.pages === chapter.pages, before.pages)

  // The page the reader is on, counted from zero. Four pages have then been read.
  await post('/api/Reader/progress', {
    libraryId: first.libraryId,
    seriesId: first.id,
    volumeId: first.id * 100,
    chapterId: chapter.id,
    pageNum: 3,
  }, token)
  const advanced = (await volumes(first.id))[0].chapters[0]
  check('page three read is four pages read', advanced.pagesRead === 4, advanced.pagesRead)

  // Which is where the pull's arithmetic comes back the other way: four read is page three.
  check('four pages read is page three again', advanced.pagesRead - 1 === 3, advanced.pagesRead - 1)

  const resume = await (await get(`/api/Reader/continue-point?seriesId=${first.id}`, token)).json()
  check('a part-read chapter is still where to continue', resume.id === chapter.id, resume.id)

  await post('/api/Reader/progress', {
    libraryId: first.libraryId,
    seriesId: first.id,
    volumeId: first.id * 100,
    chapterId: chapter.id,
    pageNum: chapter.pages - 1,
  }, token)
  const finished = (await volumes(first.id))[0].chapters[0]
  check('the last page read is the whole chapter read', finished.pagesRead === finished.pages,
    finished.pagesRead)
  if (first.chapters.length > 1) {
    const next = await (await get(`/api/Reader/continue-point?seriesId=${first.id}`, token)).json()
    check('a finished chapter hands the continue point on', next.id === first.chapters[1].id, next.id)
  }

  // A deliberate mark is not a position, and must move the same number.
  await post('/api/Reader/mark-chapter-unread', { seriesId: first.id, chapterId: chapter.id }, token)
  check('unmarking a chapter returns it to nothing read',
    (await volumes(first.id))[0].chapters[0].pagesRead === 0)
  await post('/api/Reader/mark-chapter-read', { seriesId: first.id, chapterId: chapter.id }, token)
  const marked = (await volumes(first.id))[0].chapters[0]
  check('marking a chapter read reads all of it', marked.pagesRead === marked.pages, marked.pagesRead)

  // And a series' own row adds its chapters up, which is what a library shelf shows.
  const listed = await (await get(`/api/Series/${first.id}`, token)).json()
  check('a series counts what its chapters have read',
    listed.pagesRead === first.chapters.reduce((sum, each) => sum + each.pagesRead, 0),
    listed.pagesRead)

  server.close()
  if (failures.length) {
    console.error(`kavita mock self-test failed: ${failures.join('; ')}`)
    process.exit(1)
  }
  console.log(`kavita mock self-test: ${run} checks passed`)
}

if (selfTest) {
  server.listen(0, '127.0.0.1', () => { drive() })
} else {
  server.listen(port, () => {
    console.log(`kavita mock: http://localhost:${port}`)
    console.log(`  api key: ${API_KEY}   version: ${VERSION}`)
    console.log(`  ${libraries.length} libraries, ${series.length} series from ${root}`)
  })
}
