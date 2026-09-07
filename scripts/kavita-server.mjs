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
  // Four series, and the order matters twice: `Tidal Reach` sorts first so `series[0]` is the
  // one with two chapters the continue-point checks need, and the fourth exists so the corpus
  // holds a series that states no publication status at all.
  const names = [
    'Tidal Reach 01.cbz', 'Tidal Reach 02.cbz', 'Undertow 01.cbz', 'Vale.pdf',
    'Winter Field.epub',
  ]
  for (const name of names) {
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
 * Age ratings, by Kavita's own numbering, cycled across the corpus.
 *
 * `Kavita.Models/Entities/Enums/AgeRating.cs`: 0 is `Unknown`, 3 `Everyone`, 8 `Teen`,
 * 10 `Mature 17+`, 13 `Adults Only 18+`. Zero stays first and deliberately: it is Kavita's
 * default for a series nobody has rated, and a client that drew "Unknown" as if it were a
 * rating would be telling a parent the book had been assessed. Every value here used to be
 * zero, so the whole stated-rating path was served by nothing.
 */
const AGE_RATINGS = [0, 3, 8, 10, 13]

/**
 * Metadata the server holds, which the spec says wins over the file's own.
 *
 * Deliberately disagrees with what `ComicInfo.xml` in the corpus says, so a client that
 * quietly prefers the file is visible rather than merely unproven.
 */
const metadata = new Map(series.map((each, index) => {
  const held = {
    seriesId: each.id,
    summary: `${each.name} is a fixture series held by the StoryArc Kavita mock. ` +
      'The server is the curated source, so this text wins over anything in the file.',
    genres: [{ id: 1, title: 'Fixture' }, { id: 2, title: index % 2 ? 'Drama' : 'Adventure' }],
    tags: [{ id: 3, title: 'test-corpus' }],
    writers: [{ id: 4, name: 'Ada Lovelace' }],
    publishers: [{ id: 5, name: 'StoryArc Press' }],
    ageRating: AGE_RATINGS[index % AGE_RATINGS.length],
    releaseYear: 2020 + (index % 5),
  }
  // One series in four states no status at all, which is what a real Kavita does: it omits
  // what a series does not have. The corpus needs that case because zero in this enum is
  // `OnGoing` -- a client that read an absent field as zero would state that a series is
  // running on the server's behalf, and against a corpus where every series states one it
  // would look exactly like a client that read the field correctly.
  //
  // 0 `OnGoing`, 1 `Hiatus`, 2 `Completed`, from Kavita's `PublicationStatus`.
  if (index % 4 !== 3) held.publicationStatus = index % 3
  return [each.id, held]
}))

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

/**
 * The verb each route answers to, and one address that reaches it.
 *
 * This mock used to route on the path alone, so a GET, a POST, a PUT and a DELETE were all
 * answered the same way and a client that picked the wrong verb passed every test in the
 * suite. Two of them were wrong. Measured against a live Kavita on 2026-09-06:
 * `GET /api/Series/all-v2` and `GET /api/ReadingList/lists` both answer 404, and a POST
 * carrying an empty filter answers with the whole list. A reader who added their own server
 * was shown no series and no reading lists.
 *
 * A route whose verb nobody has measured is left out of this table and still answers any
 * verb, because a wrong entry here makes a working client look broken -- which is worse
 * than the blindness it replaces. One route is left out today: `/api/Series`. This mock
 * serves it from the `all-v2` handler and no client calls it, so neither a measurement nor
 * an agreement between the clients states its verb. Kavita's own `openapi.json` states
 * POST for it up to 0.8.9.1 and drops the route at 0.9.0, so this mock's GET is wrong
 * against every one of those five releases. Nothing calls it, so nothing is broken by it.
 *
 * This table is now written from Kavita's published `openapi.json` rather than from the
 * clients. Two routes were removed on 2026-09-07 because no shipped Kavita has ever had
 * them: `/api/Server/server-info` and `/api/Collection/series`. Both were absent from
 * v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4, and a live 0.9.1.4 answers 404 to each.
 * They survived because this mock was written from the client, so the client asked for a
 * route it had invented and this mock answered it.
 *
 * **Two entries below are kept against the published spec, and this is the only place that
 * says so beside `STATUS.md`.** `/api/Reader/mark-chapter-unread` is absent from all five,
 * so unmarking a chapter is dead against every Kavita; the nearest route is
 * `/api/Reader/mark-multiple-unread`, whose body is a different shape from the
 * `{seriesId, chapterId}` both clients send. `/api/Reader/mark-chapter-read` is absent from
 * v0.8.6, v0.8.8 and v0.8.9.1 and present from v0.9.0, so it 404s on the three older
 * releases. Both are left answering here because no replacement has been measured against a
 * live server, and guessing a write shape is the mistake this file already records twice.
 * A change to either caller -- `KavitaMetadata.swift:196` and `KavitaClient.kt:163` -- will
 * pass every suite and still 404 on a real server.
 */
const ROUTES = [
  { at: '/api/Plugin/authenticate', verb: 'POST', example: `/api/Plugin/authenticate?apiKey=${API_KEY}` },
  { at: /^\/api\/Image\//, verb: 'GET', example: `/api/Image/series-cover?seriesId=1&apiKey=${API_KEY}` },
  { at: '/api/Library/libraries', verb: 'GET', example: '/api/Library/libraries' },
  { at: '/api/Series/all-v2', verb: 'POST', example: '/api/Series/all-v2' },
  { at: /^\/api\/Series\/\d+$/, verb: 'GET', example: '/api/Series/1' },
  { at: '/api/Series/metadata', verb: 'GET', example: '/api/Series/metadata?seriesId=1' },
  { at: '/api/Series/volumes', verb: 'GET', example: '/api/Series/volumes?seriesId=1' },
  { at: '/api/Download/chapter', verb: 'GET', example: '/api/Download/chapter?chapterId=1' },
  { at: '/api/Reader/continue-point', verb: 'GET', example: '/api/Reader/continue-point?seriesId=1' },
  { at: '/api/Reader/progress', verb: 'POST', example: '/api/Reader/progress' },
  { at: '/api/Reader/mark-chapter-read', verb: 'POST', example: '/api/Reader/mark-chapter-read' },
  { at: '/api/Reader/mark-chapter-unread', verb: 'POST', example: '/api/Reader/mark-chapter-unread' },
  { at: '/api/Collection', verb: 'GET', example: '/api/Collection' },
  { at: '/api/Collection/update-for-series', verb: 'POST', example: '/api/Collection/update-for-series' },
  {
    at: '/api/Series/series-by-collection',
    verb: 'GET',
    example: '/api/Series/series-by-collection?collectionId=1',
  },
  { at: '/api/ReadingList/lists', verb: 'POST', example: '/api/ReadingList/lists' },
  { at: '/api/ReadingList/items', verb: 'GET', example: '/api/ReadingList/items?readingListId=1' },
  { at: '/api/ReadingList/create', verb: 'POST', example: '/api/ReadingList/create' },
  { at: '/api/ReadingList/update-by-multiple', verb: 'POST', example: '/api/ReadingList/update-by-multiple' },
  { at: '/api/ReadingList/update-position', verb: 'POST', example: '/api/ReadingList/update-position' },
  { at: '/api/ReadingList', verb: 'DELETE', example: '/api/ReadingList?readingListId=1' },
  { at: '/api/Search/search', verb: 'GET', example: '/api/Search/search?queryString=a' },
]

/**
 * `Libraries` in Kavita's `SeriesFilterField`, and the one comparison measured to narrow.
 *
 * `Kavita.Models/DTOs/Filtering/v2/FilterFields/SeriesFilterField.cs` line 29 numbers
 * `Libraries` 19. `comparison` 0 narrowed a live server on 2026-09-06; so did 5, and every
 * other value from 1 to 10 answered the whole unfiltered list. This mock therefore claims a
 * meaning for 0 alone -- a comparison nobody measured is not one it can speak for.
 */
const LIBRARY_FIELD = 19
const MEASURED_COMPARISON = 0

/**
 * Which library a posted filter names, or 0 for "every library".
 *
 * The body is a `SeriesFilterV2Dto`. An empty `{}` means everything, which is what a live
 * Kavita answered and what this mock answers. A statement this mock cannot read widens
 * rather than refuses, because that is what the live server did with the comparisons it
 * ignored -- a mock that refused would be stricter than the thing it stands in for.
 */
const libraryFiltered = (posted) => {
  const statements = Array.isArray(posted?.statements) ? posted.statements : []
  const named = statements.find(
    (each) => each?.field === LIBRARY_FIELD && each?.comparison === MEASURED_COMPARISON,
  )
  return Number(named?.value ?? 0) || 0
}

/** The verb a route requires, or nothing when this mock asserts none for it. */
const verbFor = (pathname) =>
  ROUTES.find(({ at }) => (typeof at === 'string' ? at === pathname : at.test(pathname)))?.verb

const server = createServer((request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`)
  if (!selfTest) {
    response.on('finish', () => {
      console.log(`${response.statusCode} ${request.method} ${request.url}`)
    })
  }

  // The verb, before anything else -- before the token, because a route that answered the
  // wrong verb is the defect this gate exists for and hiding it behind a 401 would only
  // move it. Kavita answers 404 here rather than 405; the mock says 405 because it knows
  // the route exists and the caller needs to be told which of the two is wrong.
  const required = verbFor(url.pathname)
  if (required && request.method !== required) {
    response.writeHead(405, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      Allow: required,
    })
    return response.end(JSON.stringify({ message: `${url.pathname} answers ${required}` }))
  }

  // Authentication is the one route that does not need a token.
  if (url.pathname === '/api/Plugin/authenticate') {
    if (url.searchParams.get('apiKey') !== API_KEY) {
      return send(response, 401, { message: 'unauthorised' })
    }
    return send(response, 200, { username: 'ada', token: TOKEN, apiKey: API_KEY })
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

  // The series list, narrowed by the filter in the **body** and by nothing in the query.
  // A `libraryId` query parameter is read by no live Kavita and is ignored here too.
  if (url.pathname === '/api/Series/all-v2' || url.pathname === '/api/Series') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      let posted
      try {
        posted = JSON.parse(body || '{}')
      } catch {
        return send(response, 400, { message: 'a filter must be json' })
      }
      const wanted = libraryFiltered(posted)
      const shown = wanted ? series.filter((each) => each.libraryId === wanted) : series
      send(response, 200, shown.map((each) => ({
        id: each.id,
        name: each.name,
        libraryId: each.libraryId,
        pages: each.chapters.reduce((total, chapter) => total + chapter.pages, 0),
        pagesRead: each.chapters.reduce((total, chapter) => total + chapter.pagesRead, 0),
      })))
    })
    return undefined
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

  // `collections-and-reading-lists` lets a reader keep a new collection on a server. Kavita
  // has no create route for one: it brings a collection into being by tagging series, and a
  // zero id means "make it". The mock takes a bulk-add with no series at all, which is what
  // the shelves screen sends; **a real Kavita may refuse that**, because a collection holding
  // nothing is not something its own interface can make. Nothing here has run against a live
  // server, so that stays an open question rather than a proven behaviour.
  if (url.pathname === '/api/Collection/update-for-series' && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const title = posted.collectionTagTitle ?? ''
      const wanted = posted.seriesIds ?? []
      if (!posted.collectionTagId) {
        if (!title) return send(response, 400, { message: 'a collection needs a name' })
        collections.push({
          id: Math.max(0, ...collections.map((each) => each.id)) + 1,
          title,
          summary: null,
          seriesIds: wanted,
        })
        return send(response, 200, {})
      }
      const found = collections.find((each) => each.id === posted.collectionTagId)
      if (!found) return send(response, 404, { message: 'no such collection' })
      found.seriesIds = [...new Set([...found.seriesIds, ...wanted])]
      send(response, 200, {})
    })
    return undefined
  }

  if (url.pathname === '/api/Series/series-by-collection') {
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

  // `collections-and-reading-lists` makes a reading list's order its meaning, and asks for a
  // new order to be sent to the server. Kavita moves one entry at a time, by position, so the
  // mock takes the same four fields Kavita's own `update-position` takes and renumbers what
  // is left -- a mock that took the move and kept the old `order` values could not tell a
  // client that reorders from one that only thinks it does.
  if (url.pathname === '/api/ReadingList/update-position' && request.method === 'POST') {
    let body = ''
    request.on('data', (chunk) => { body += chunk })
    request.on('end', () => {
      const posted = JSON.parse(body || '{}')
      const list = readingLists.find((each) => each.id === posted.readingListId)
      if (!list) return send(response, 404, { message: 'no such list' })
      const from = posted.fromPosition
      const to = posted.toPosition
      const inRange = (at) => Number.isInteger(at) && at >= 0 && at < list.items.length
      if (!inRange(from) || !inRange(to)) {
        return send(response, 400, { message: 'position out of range' })
      }
      if (list.items[from].id !== posted.readingListItemId) {
        // Kavita addresses the move by the entry as well as by where it is. A client that
        // sent one without the other would be moving whatever happens to sit there now.
        return send(response, 400, { message: 'that entry is not at that position' })
      }
      const [moved] = list.items.splice(from, 1)
      list.items.splice(to, 0, moved)
      list.items.forEach((item, at) => { item.order = at })
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

  // The two routes a live Kavita answers to a POST alone. Both clients sent a GET, both got
  // a 404 from the owner's own server on 2026-09-06, and no test here could see it because
  // this mock routed on the path and never on the verb. A reader who added a real server was
  // shown no series and no reading lists at all.
  const shelf = await post('/api/Series/all-v2', {}, token)
  check('the series list answers a post', shelf.status === 200, shelf.status)
  check('the series list a post answers holds the whole corpus',
    (await shelf.json()).length === series.length)
  check('a get on the series list is refused',
    (await get('/api/Series/all-v2', token)).status === 405,
    (await get('/api/Series/all-v2', token)).status)

  // The library filter, which Kavita reads from the body and nowhere else. Measured against
  // a live server on 2026-09-06: `POST /api/Series/all-v2?libraryId=3` with an empty body
  // answered all 215 series across four libraries, and the same route carrying the statement
  // below answered 91 series from library 3 alone. This mock used to read the query
  // parameter, so it agreed with a client that sent one there -- and a reader who picked one
  // library was shown every library, confidently and with no error anywhere.
  const one = libraries[0].id
  const narrowed = await post('/api/Series/all-v2', {
    statements: [{ comparison: 0, field: 19, value: String(one) }],
    combination: 0,
  }, token)
  check('a filter statement naming one library is accepted', narrowed.status === 200,
    narrowed.status)
  const narrowedSeries = narrowed.status === 200 ? await narrowed.json() : []
  check('a filter statement naming one library answers with that library alone',
    narrowedSeries.length > 0 && narrowedSeries.every((each) => each.libraryId === one),
    narrowedSeries.map((each) => each.libraryId))
  check('a filter statement naming one library leaves the other libraries out',
    narrowedSeries.length < series.length, narrowedSeries.length)

  // And the parameter the clients used to send does nothing at all, which is what a live
  // Kavita does with it. A mock that narrowed here would keep the trap armed.
  const queried = await post(`/api/Series/all-v2?libraryId=${one}`, {}, token)
  check('a library named in the query alone is ignored',
    (await queried.json()).length === series.length)

  const lists = await post('/api/ReadingList/lists', {}, token)
  check('the reading lists answer a post', lists.status === 200, lists.status)
  check('the reading lists a post answers are the ones the server holds',
    (await lists.json()).length === readingLists.length)
  check('a get on the reading lists is refused',
    (await get('/api/ReadingList/lists', token)).status === 405,
    (await get('/api/ReadingList/lists', token)).status)

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

  // `kavita-server`'s *Metadata* requirement lists seven fields and two of them cross the
  // wire as bare integers. They were served as a constant zero and a three-cycle, which is
  // a corpus in which the stated-rating path never happens — so a client that dropped the
  // rating entirely, which is what both clients did, looked exactly like one that kept it.
  const held = await Promise.all(
    series.map(async (each) =>
      (await get(`/api/Series/metadata?seriesId=${each.id}`, token)).json())
  )
  check('the metadata route states an age rating on every series',
    held.every((each) => typeof each.ageRating === 'number'))

  // Kavita's own tables, from `Kavita.Models/Entities/Enums`. A number outside them would be
  // one no client could name, and the corpus would be asking for a guess.
  check('every age rating is one Kavita defines',
    held.every((each) => each.ageRating >= -1 && each.ageRating <= 14),
    held.map((each) => each.ageRating))
  const statuses = held
    .filter((each) => each.publicationStatus !== undefined)
    .map((each) => each.publicationStatus)
  check('every publication status the server states is one Kavita defines',
    statuses.every((each) => typeof each === 'number' && each >= 0 && each <= 4),
    statuses)

  // The two halves of the status rule. Zero in Kavita's `PublicationStatus` is `OnGoing`, so
  // "stated nothing" cannot be a number -- and a corpus in which every series states one is
  // a corpus where reading an absent field as zero is invisible.
  check('at least one series states no publication status at all',
    held.some((each) => each.publicationStatus === undefined),
    held.length - statuses.length)
  check('at least one series states a publication status', statuses.length > 0)

  // The two halves of the rating rule, both of which have to be reachable: a series nobody
  // rated, which must not be drawn as a rating, and a series with a real one, which must.
  check('at least one series carries no rating at all',
    held.some((each) => each.ageRating === 0))
  check('at least one series carries a rating a reader would be shown',
    held.some((each) => each.ageRating > 0), held.map((each) => each.ageRating))

  // More than one of each, so a client that hardcoded a label is visible rather than lucky.
  check('the corpus holds more than one age rating',
    new Set(held.map((each) => each.ageRating)).size > 1)
  check('the corpus holds more than one publication status',
    new Set(statuses).size > 1, statuses)

  // A collection a reader made against the server, per `collections-and-reading-lists`. The
  // server mints the id, and the client reads it back by name because Kavita's bulk-add
  // answers with nothing.
  const heldBefore = (await (await get('/api/Collection', token)).json()).length
  const created = await post('/api/Collection/update-for-series', {
    collectionTagId: 0,
    collectionTagTitle: 'Made by a reader',
    seriesIds: [],
  }, token)
  check('a collection a reader made is accepted', created.status === 200, created.status)
  const grouped = await (await get('/api/Collection', token)).json()
  check('a collection a reader made is one the server then lists',
    grouped.length === heldBefore + 1 &&
      grouped.some((each) => each.title === 'Made by a reader'),
    grouped.map((each) => each.title))
  check('a collection a reader made carries an id nothing else has',
    new Set(grouped.map((each) => each.id)).size === grouped.length,
    grouped.map((each) => each.id))
  const unnamed = await post('/api/Collection/update-for-series', {
    collectionTagId: 0,
    collectionTagTitle: '',
    seriesIds: [],
  }, token)
  check('a collection with no name is refused rather than made', unnamed.status === 400,
    unnamed.status)

  // `collections-and-reading-lists` makes a reading list's order the thing it exists to
  // hold, so the mock has to be a contract about the order and not only about the entries.
  // A move by position is the one place a reordering client can be silently wrong: a server
  // that took the move and left `order` alone would answer every later read in the old
  // sequence, and no client-side test could see the difference.
  const listItems = async (id) =>
    (await get(`/api/ReadingList/items?readingListId=${id}`, token)).json()

  const start = await listItems(1)
  check('a reading list answers in its own order',
    start.every((item, at) => item.order === at), start.map((each) => each.order))

  if (start.length > 1) {
    const last = start[start.length - 1]
    const moved = await post('/api/ReadingList/update-position', {
      readingListId: 1,
      readingListItemId: last.id,
      fromPosition: start.length - 1,
      toPosition: 0,
    }, token)
    check('a move the server accepts answers 200', moved.status === 200, moved.status)

    const after = await listItems(1)
    check('the entry moved to the top is the one that is now first',
      after[0].id === last.id, after[0].id)
    check('the whole list is renumbered from zero after a move',
      after.every((item, at) => item.order === at), after.map((each) => each.order))
    check('a move keeps every entry it started with',
      after.length === start.length &&
        start.every((each) => after.some((item) => item.id === each.id)),
      after.map((each) => each.id))

    // Kavita addresses a move by the entry as well as by where it is. A client that sent one
    // without the other would move whatever happens to sit there now, which is how a reorder
    // scrambles a list instead of ordering it.
    const mismatched = await post('/api/ReadingList/update-position', {
      readingListId: 1,
      readingListItemId: last.id,
      fromPosition: 1,
      toPosition: 0,
    }, token)
    check('a move naming an entry that is not at that position is refused',
      mismatched.status === 400, mismatched.status)

    const outOfRange = await post('/api/ReadingList/update-position', {
      readingListId: 1,
      readingListItemId: after[0].id,
      fromPosition: 0,
      toPosition: after.length,
    }, token)
    check('a move to a position the list does not have is refused',
      outOfRange.status === 400, outOfRange.status)
  }

  const noSuchList = await post('/api/ReadingList/update-position', {
    readingListId: 9999,
    readingListItemId: 1,
    fromPosition: 0,
    toPosition: 0,
  }, token)
  check('a move on a list the server does not hold is refused',
    noSuchList.status === 404, noSuchList.status)

  // The routes the drive above does not otherwise reach, each asked the way the clients ask
  // it. Every route in `ROUTES` is now used somewhere in this drive with the verb it states,
  // which is what makes the table a claim about Kavita rather than about itself: state the
  // wrong verb for a route and the call that uses it stops answering.
  // The collection listing, at the route Kavita publishes. `Series/series-by-collection`
  // is in v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4, and a live 0.9.1.4 answered 200.
  const collected = await get(`/api/Series/series-by-collection?collectionId=${collections[0].id}`, token)
  check('a collection lists its series', collected.status === 200, collected.status)
  check('the listed series are the ones the collection holds',
    (await collected.json()).map((each) => each.id).join() === collections[0].seriesIds.join())

  // The two routes no shipped Kavita has ever had. Absent from all five published specs,
  // and 404 on a live 0.9.1.4. This mock answered both until 2026-09-07, which is the only
  // reason two clients could ship a call to each with every test passing.
  check('nothing stands at the invented collection route',
    (await get('/api/Collection/series?collectionId=1', token)).status === 404)
  check('nothing states the server version, because no route does',
    (await get('/api/Server/server-info', token)).status === 404)
  check('a cover answers a get',
    (await get(`/api/Image/series-cover?seriesId=${first.id}&apiKey=${API_KEY}`, token)).status === 200)
  check('a chapter download answers a get',
    (await get(`/api/Download/chapter?chapterId=${chapter.id}`, token)).status === 200)

  // Search is the third route a live Kavita has answered for. `GET /api/Search/search`
  // answered 200 on the owner's own server on 2026-09-06 and both clients GET it, so the
  // table pins it and this drive uses it.
  const found = await get(
    `/api/Search/search?queryString=${encodeURIComponent(first.name)}`, token)
  check('the search route answers a get', found.status === 200, found.status)
  const hits = found.status === 200 ? await found.json() : { series: [] }
  check('a search for a series the corpus holds finds that series',
    hits.series.some((each) => each.id === first.id))

  const kept = await post('/api/ReadingList/create', { title: 'Kept by a reader' }, token)
  check('a list a reader made is accepted', kept.status === 200, kept.status)
  const keptId = (await kept.json()).id

  // Appending chapters to a list is a route both clients POST and nothing above reaches, so
  // its row in the table used to be asserted only by the sweep -- which derives the wrong
  // verb from the same row it tests, and therefore agrees with a wrong row.
  const appended = await post('/api/ReadingList/update-by-multiple', {
    readingListId: keptId,
    seriesId: first.id,
    chapterIds: [chapter.id],
  }, token)
  check('chapters a reader appends to a list are accepted', appended.status === 200,
    appended.status)
  check('a chapter appended to a list is one the list then holds',
    (await listItems(keptId)).some((item) => item.chapterId === chapter.id))
  const dropped = await fetch(`${base}/api/ReadingList?readingListId=${keptId}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  })
  check('a list a reader made can be dropped again', dropped.status === 200, dropped.status)
  check('a dropped list is no longer one the server lists',
    (await (await post('/api/ReadingList/lists', {}, token)).json())
      .every((each) => each.id !== keptId))

  // And every one of them asked with a verb it does not answer. This is the check the mock
  // never had: it routed on the path alone, so a client using the wrong verb passed the
  // whole suite and only a live server could say otherwise.
  const otherwise = { GET: 'POST', POST: 'GET', DELETE: 'GET' }
  for (const route of ROUTES) {
    const wrong = otherwise[route.verb]
    const answered = await fetch(`${base}${route.example}`, {
      method: wrong,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(wrong === 'POST' ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(wrong === 'POST' ? { body: '{}' } : {}),
    })
    const label = typeof route.at === 'string' ? route.at : String(route.at)
    check(`${label} answers ${route.verb} and refuses a ${wrong}`,
      answered.status === 405 && answered.headers.get('allow') === route.verb,
      answered.status)
  }

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
    console.log(`  api key: ${API_KEY}`)
    console.log(`  ${libraries.length} libraries, ${series.length} series from ${root}`)
  })
}
