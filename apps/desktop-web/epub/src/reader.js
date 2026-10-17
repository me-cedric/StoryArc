// The reader: one publication open in one container, and the two-way message surface the
// host talks to (tasks 4.1 and 4.2 of desktop-clients).
//
// The host owes the renderer a Readium Web Publication Manifest and a positions list
// (design.md, Decision 6); this module wraps the toolkit's navigator around them and turns its
// callbacks into messages.
//
//   out (renderer to host)         in (host to renderer, through `receive`)
//   ready, locator                 go, next, previous
//   footnote, link                 (clicks inside the content, see links.js)
//   preferences                    preferences
//
//   theme                          theme   (a preset: every axis it names, the rest cleared)
//   search-results                 search  (`{id, query}`; a newer search silences an older one)
//   highlights, highlight-activated  highlights  (the whole set for the book)
//   selection                      (a reader selecting text in the content)
//
// Every outgoing message is plain JSON with a `type` and a `seq`.
import { EpubNavigator, EpubPreferences } from '@readium/navigator'
import { HttpFetcher, Link, Locator, Manifest, Publication } from '@readium/shared'
import { createHighlights } from './highlights.js'
import { createLinkHandler } from './links.js'
import { createSearch } from './search.js'
import { hostPost, sequenced } from './transport.js'

const OPAQUE = Object.freeze({})

/** The CSS properties the navigator has compiled from the preferences, as the content sees them. */
function compiledProperties(navigator) {
  const css = navigator._css
  return { ...css.rsProperties.toCSSProperties(), ...css.userProperties.toCSSProperties() }
}

const FRAME_RULE = '.readium-navigator-iframe { border: 0; width: 100%; height: 100%; }'

/**
 * The toolkit sizes its container's width and leaves the rest to the page: a content frame is
 * an `<iframe>`, and an iframe left alone is 300 by 150. The reader owns that, so no host has
 * to know it. The rule goes in a constructed stylesheet, which a Content-Security-Policy
 * without `style-src 'unsafe-inline'` does not block, with a `<style>` element as the fallback.
 */
function fillContainer(container) {
  const document = container.ownerDocument
  const stage = document.createElement('div')
  stage.style.height = '100%'
  container.append(stage)
  if ('adoptedStyleSheets' in document && 'replaceSync' in CSSStyleSheet.prototype) {
    const sheet = new CSSStyleSheet()
    sheet.replaceSync(FRAME_RULE)
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]
  } else {
    const style = document.createElement('style')
    style.textContent = FRAME_RULE
    document.head.append(style)
  }
  return stage
}

const settle = (go) => new Promise((resolve) => go(resolve))

/**
 * @param {object} options
 * @param {HTMLElement} options.container the host's own element, sized by the host; the reader fills it
 * @param {object} options.manifest the Readium Web Publication Manifest, as JSON
 * @param {object[]} [options.positions] the positions list, as locator JSON
 * @param {object} [options.locator] where to open, as locator JSON; the first position when absent
 * @param {object} [options.preferences] axes to apply before the first page
 * @param {(message: object) => void} [options.post] the way to the host; the web view's own by default
 */
export async function open({ container, manifest, positions = [], locator, preferences = {}, post: transport }) {
  const post = sequenced(transport ?? hostPost())
  const parsed = Manifest.deserialize(manifest)
  if (!parsed) throw new Error('the manifest is not a Readium Web Publication Manifest')

  const baseUrl = new Publication({ manifest: parsed }).baseURL
  const publication = new Publication({ manifest: parsed, fetcher: new HttpFetcher(undefined, baseUrl) })
  const located = positions.map((json) => Locator.deserialize(json)).filter(Boolean)
  const initial = locator ? Locator.deserialize(locator) : undefined

  let navigator
  const links = createLinkHandler({
    post,
    currentHref: () => navigator.currentLocator.href,
    readText: (href) => publication.get(new Link({ href })).readAsString(),
  })

  let axes = { ...preferences }
  let highlights
  navigator = new EpubNavigator(
    fillContainer(container),
    publication,
    {
      frameLoaded: (frameWindow) => links.attach(frameWindow),
      positionChanged: (current) => post({ type: 'locator', locator: current.serialize() }),
      handleLocator: links.handleLocator,
      textSelected: (selection) => highlights.selected(selection),
    },
    located,
    initial,
    { preferences: new EpubPreferences(axes), defaults: OPAQUE },
  )
  highlights = createHighlights({ navigator, post })
  await navigator.load()
  post({ type: 'ready', title: manifest.metadata?.title, positions: located.length })

  async function applyPreferences(next) {
    axes = { ...axes, ...next }
    await navigator.submitPreferences(new EpubPreferences(axes))
    post({ type: 'preferences', properties: compiledProperties(navigator) })
  }

  /** A preset replaces the axes: those it names are set, those it does not are cleared. */
  async function applyTheme({ theme }) {
    const cleared = Object.fromEntries(Object.keys(axes).map((axis) => [axis, null]))
    const next = { ...cleared, ...theme.axes }
    axes = Object.fromEntries(Object.entries(next).filter(([, value]) => value !== null))
    await navigator.submitPreferences(new EpubPreferences(next))
    post({
      type: 'theme',
      name: theme.name,
      background: theme.axes.backgroundColor,
      text: theme.axes.textColor,
      properties: compiledProperties(navigator),
    })
  }

  function locateIn(href, progression) {
    const link = publication.readingOrder.findWithHref(href)
    const here = located.filter((position) => position.href === href)
    const position = [...here].reverse().find((candidate) => (candidate.locations.progression ?? 0) <= progression) ?? here[0]
    return {
      href,
      type: link?.type ?? 'application/xhtml+xml',
      title: link?.title,
      locations: {
        progression,
        position: position?.locations.position,
        totalProgression: position?.locations.totalProgression,
      },
    }
  }

  const search = createSearch({
    chapters: publication.readingOrder.items,
    readText: (href) => publication.get(new Link({ href })).readAsString(),
    locate: locateIn,
    post,
  })

  const commands = {
    theme: applyTheme,
    search: ({ id, query }) => search.start(id, String(query ?? '')),
    highlights: ({ items }) => highlights.apply(items ?? []),
    async go({ locator: target }) {
      const to = Locator.deserialize(target)
      if (!to) return post({ type: 'navigation-failed', reason: 'not a locator' })
      if (!(await settle((done) => navigator.go(to, false, done)))) post({ type: 'navigation-failed', reason: 'not reachable' })
    },
    async next() {
      await settle((done) => navigator.goForward(false, done))
    },
    async previous() {
      await settle((done) => navigator.goBackward(false, done))
    },
    preferences: ({ preferences: next }) => applyPreferences(next ?? {}),
  }

  return {
    navigator,
    publication,
    /** The host's door in: one message, one command. Unknown messages are ignored, not thrown. */
    receive: (message) => commands[message?.type]?.(message),
    destroy: async () => {
      await navigator.destroy()
      container.replaceChildren()
    },
  }
}
