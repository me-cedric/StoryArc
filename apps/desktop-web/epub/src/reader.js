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
// Every outgoing message is plain JSON with a `type` and a `seq`.
import { EpubNavigator, EpubPreferences } from '@readium/navigator'
import { HttpFetcher, Link, Locator, Manifest, Publication } from '@readium/shared'
import { createLinkHandler } from './links.js'
import { hostPost, sequenced } from './transport.js'

const OPAQUE = Object.freeze({})

/** The CSS properties the navigator has compiled from the preferences, as the content sees them. */
function compiledProperties(navigator) {
  const css = navigator._css
  return { ...css.rsProperties.toCSSProperties(), ...css.userProperties.toCSSProperties() }
}

const settle = (go) => new Promise((resolve) => go(resolve))

/**
 * @param {object} options
 * @param {HTMLElement} options.container where the content frames go
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
  navigator = new EpubNavigator(
    container,
    publication,
    {
      frameLoaded: (frameWindow) => links.attach(frameWindow),
      positionChanged: (current) => post({ type: 'locator', locator: current.serialize() }),
      handleLocator: links.handleLocator,
    },
    located,
    initial,
    { preferences: new EpubPreferences(axes), defaults: OPAQUE },
  )
  await navigator.load()
  post({ type: 'ready', title: manifest.metadata?.title, positions: located.length })

  async function applyPreferences(next) {
    axes = { ...axes, ...next }
    await navigator.submitPreferences(new EpubPreferences(axes))
    post({ type: 'preferences', properties: compiledProperties(navigator) })
  }

  const commands = {
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
    destroy: () => navigator.destroy(),
  }
}
