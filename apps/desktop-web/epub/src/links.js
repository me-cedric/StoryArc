// Footnotes and links, which the toolkit treats as one thing: a click on an anchor.
//
// ebook-reader spec, "Following an internal link": a footnote opens in place, a longer jump
// navigates. "Following a link out of the publication": handed to the host, never opened over
// the text, and only http and https are followed; any other scheme is dropped.
//
// The toolkit's navigator would send an `http` link to its `handleLocator` listener and
// follow an `epub:type="noteref"` like any other internal link, so this module listens in the
// content frame first, in the capture phase, and decides before the navigator sees the click.
// A click it does not recognise (a plain internal link) is left to the navigator untouched.

const SCHEME = /^[a-z][a-z0-9+.-]*:/i
const FOLLOWED = /^https?:/i

/** An `epub:type` is a space-separated list; a `role` can say the same in ARIA. */
export function isNoteReference(anchor) {
  const types = (anchor.getAttribute('epub:type') ?? '').split(/\s+/)
  return types.includes('noteref') || anchor.getAttribute('role') === 'doc-noteref'
}

/** `ch1.xhtml#fn` read from `OEBPS/ch2.xhtml` is `OEBPS/ch1.xhtml#fn`: a publication href. */
export function resolveHref(raw, fromHref) {
  const url = new URL(raw, `http://publication/${fromHref}`)
  return `${decodeURIComponent(url.pathname.slice(1))}${url.hash}`
}

const squash = (text) => text.replace(/\s+/g, ' ').trim()

function parse(markup) {
  for (const type of ['application/xhtml+xml', 'text/html']) {
    const document = new DOMParser().parseFromString(markup, type)
    if (!document.querySelector('parsererror')) return document
  }
  return undefined
}

/**
 * @param {object} context
 * @param {(message: object) => void} context.post
 * @param {() => string} context.currentHref the publication href of the chapter on screen
 * @param {(href: string) => Promise<string | undefined>} context.readText a chapter's markup
 */
export function createLinkHandler({ post, currentHref, readText }) {
  async function noteText(raw, frameDocument) {
    const fromHref = currentHref()
    const href = raw.startsWith('#') ? `${fromHref}${raw}` : resolveHref(raw, fromHref)
    const [path, fragment] = href.split('#')
    let document = path === fromHref ? frameDocument : undefined
    if (!document) {
      const markup = await readText(path).catch(() => undefined)
      document = markup === undefined ? undefined : parse(markup)
    }
    const target = fragment ? document?.getElementById(decodeURIComponent(fragment)) : undefined
    return { href, text: target ? squash(target.textContent ?? '') : '' }
  }

  /** The click handler for one content frame. */
  function onClick(event) {
    const anchor = event.target?.closest?.('a[href]')
    if (!anchor) return
    const raw = anchor.getAttribute('href')
    const claim = () => {
      event.preventDefault()
      event.stopImmediatePropagation()
    }

    if (isNoteReference(anchor) && !SCHEME.test(raw)) {
      claim()
      noteText(raw, anchor.ownerDocument).then(({ href, text }) => post({ type: 'footnote', href, text }))
    } else if (SCHEME.test(raw)) {
      claim()
      if (FOLLOWED.test(raw)) post({ type: 'link', href: new URL(raw).href })
    }
  }

  /** Listens in a content frame once, however often the toolkit reports that frame again. */
  const attached = new WeakSet()
  function attach(frameWindow) {
    if (attached.has(frameWindow)) return
    attached.add(frameWindow)
    frameWindow.addEventListener('click', onClick, true)
  }

  /** The toolkit's own route for a locator it cannot place: a link out of the book. */
  function handleLocator(locator) {
    if (FOLLOWED.test(locator.href)) post({ type: 'link', href: locator.href })
    return true
  }

  return { attach, handleLocator }
}
