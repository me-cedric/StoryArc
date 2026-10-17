// Search in a publication (ebook-reader spec, "Search within a publication": matches are
// listed with surrounding context and a tap jumps to one).
//
// The toolkit has no search service, so the renderer reads each chapter through the
// publication's fetcher and looks in the text. The matching is a pure function over a string
// (`findMatches`) so it is tested without a browser; the scan around it (`createSearch`) is the
// part that touches the publication.

const CONTEXT = 40
const MAX_RESULTS = 500

/** A letter without its accent, lower-cased, so "Eclair" finds "éclair". */
const fold = (character) => character.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()

/**
 * The text folded, and for each folded character the index in the original it came from.
 * Whitespace runs fold to one space, so a line break inside a phrase does not hide it.
 */
function foldWithMap(text) {
  let folded = ''
  const origin = []
  let space = false
  for (let at = 0; at < text.length; at += 1) {
    const character = text[at]
    if (/\s/u.test(character)) {
      if (!space && folded !== '') {
        folded += ' '
        origin.push(at)
      }
      space = true
      continue
    }
    space = false
    for (const piece of fold(character)) {
      folded += piece
      origin.push(at)
    }
  }
  return { folded, origin }
}

const squash = (text) => text.replace(/\s+/g, ' ')

/**
 * Every place `query` occurs in `text`, ignoring case, accents and the shape of whitespace.
 * @returns {{start: number, end: number, before: string, highlight: string, after: string, progression: number}[]}
 */
export function findMatches(text, query, { limit = MAX_RESULTS } = {}) {
  const needle = foldWithMap(query.trim()).folded
  if (needle === '') return []
  const { folded, origin } = foldWithMap(text)
  const found = []
  for (let at = folded.indexOf(needle); at !== -1 && found.length < limit; at = folded.indexOf(needle, at + needle.length)) {
    const start = origin[at]
    const end = origin[at + needle.length - 1] + 1
    found.push({
      start,
      end,
      before: squash(text.slice(Math.max(0, start - CONTEXT), start)).trimStart(),
      highlight: squash(text.slice(start, end)),
      after: squash(text.slice(end, end + CONTEXT)).trimEnd(),
      progression: text.length === 0 ? 0 : start / text.length,
    })
  }
  return found
}

/** The readable text of a chapter's markup: what a reader could select. */
export function textOf(markup) {
  for (const type of ['application/xhtml+xml', 'text/html']) {
    const document = new DOMParser().parseFromString(markup, type)
    if (document.querySelector('parsererror')) continue
    for (const hidden of document.querySelectorAll('script, style, head')) hidden.remove()
    return document.documentElement.textContent ?? ''
  }
  return ''
}

/**
 * @param {object} context
 * @param {{href: string, type?: string, title?: string}[]} context.chapters the reading order
 * @param {(href: string) => Promise<string | undefined>} context.readText a chapter's markup
 * @param {(href: string, progression: number) => object} context.locate a locator for a place
 * @param {(message: object) => void} context.post
 */
export function createSearch({ chapters, readText, locate, post }) {
  let current = 0

  /** Starts a search. A search started later silences this one: it posts nothing more. */
  async function start(id, query) {
    current += 1
    const mine = current
    const live = () => current === mine
    let total = 0

    if (query.trim() !== '') {
      for (const chapter of chapters) {
        if (!live() || total >= MAX_RESULTS) break
        const markup = await readText(chapter.href).catch(() => undefined)
        if (!live()) return
        if (markup === undefined) continue
        const matches = findMatches(textOf(markup), query, { limit: MAX_RESULTS - total })
        if (matches.length === 0) continue
        total += matches.length
        post({
          type: 'search-results',
          id,
          done: false,
          results: matches.map((match) => ({
            locator: {
              ...locate(chapter.href, match.progression),
              text: { before: match.before, highlight: match.highlight, after: match.after },
            },
          })),
        })
      }
    }
    if (live()) post({ type: 'search-results', id, done: true, total, truncated: total >= MAX_RESULTS, results: [] })
  }

  return { start }
}
