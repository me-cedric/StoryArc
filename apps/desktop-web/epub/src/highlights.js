// Highlights and selections (ebook-reader spec, "Highlights and notes").
//
// The host owns the records: it sends the whole set of highlights for the book and the
// renderer draws them with the toolkit's decorations. A highlight is `{id, locator, color}`;
// the locator is the one a selection or a search result carried, found again by its text.
// Sending the set again replaces the set, so a deleted highlight is one the host stops sending.
import { DecorationStyleType } from '@readium/navigator'
import { Locator } from '@readium/shared'

const GROUP = 'storyarc-highlights'

const rectOf = (box) => (box ? { x: box.left, y: box.top, width: box.width, height: box.height } : undefined)

export function createHighlights({ navigator, post }) {
  navigator.registerDecorationObserver(GROUP, {
    onDecorationActivated: ({ decoration, rect }) => {
      post({ type: 'highlight-activated', id: decoration.id, rect: rectOf(rect) })
      return true
    },
  })

  /** @param {{id: string, locator: object, color: string}[]} items */
  function apply(items) {
    const decorations = items.flatMap(({ id, locator, color }) => {
      const parsed = Locator.deserialize(locator)
      return parsed ? [{ id, locator: parsed, style: { type: DecorationStyleType.Highlight, tint: color } }] : []
    })
    navigator.applyDecorations(decorations, GROUP)
    post({ type: 'highlights', ids: decorations.map((decoration) => decoration.id) })
  }

  /** The toolkit's selection event, as the host's `selection` message. */
  function selected(selection) {
    post({
      type: 'selection',
      text: selection.text,
      locator: selection.locator?.serialize(),
      rect: { x: selection.x, y: selection.y, width: selection.width, height: selection.height },
    })
  }

  return { apply, selected }
}
