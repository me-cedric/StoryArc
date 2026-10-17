// Task 4.2: themes, search and highlights carried to the host as messages. One group per
// message the renderer posts, so a message nobody tests cannot be renamed by accident.
import assert from 'node:assert/strict'
import { after, before, describe, it } from 'node:test'
import { openReader, startHarness } from './harness.mjs'

let harness
before(async () => {
  harness = await startHarness()
})
after(async () => {
  await harness.close()
})

const CH1 = 'OEBPS/ch1.xhtml'
const CH2 = 'OEBPS/ch2.xhtml'

const NIGHT = {
  name: 'night',
  axes: { backgroundColor: '#101418', textColor: '#e6e1d6', fontFamily: 'Georgia, serif', fontSize: 1.25, lineHeight: 1.7 },
}
const PAPER = { name: 'paper', axes: { backgroundColor: '#ffffff', textColor: '#1a1a1a', lineHeight: 1.4 } }

describe('the "theme" message', () => {
  it('applies a preset and reports its colours and the CSS it produced', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'theme', theme: NIGHT })

    const theme = await reader.waitFor('theme')
    assert.equal(theme.name, 'night')
    assert.equal(theme.background, '#101418')
    assert.equal(theme.text, '#e6e1d6')
    assert.equal(theme.properties['--USER__lineHeight'], '1.7')
    const colour = await reader
      .frame()
      .evaluate(() => document.documentElement.style.getPropertyValue('--USER__backgroundColor').trim())
    assert.equal(colour, '#101418')
    await reader.page.close()
  })

  it('a second preset replaces the first instead of stacking on it', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'theme', theme: NIGHT })
    await reader.waitFor('theme')
    await reader.send({ type: 'theme', theme: PAPER })

    const theme = await reader.waitFor('theme', (m) => m.name === 'paper')
    assert.equal(theme.properties['--USER__backgroundColor'], '#ffffff')
    assert.equal(theme.properties['--USER__lineHeight'], '1.4')
    assert.equal(theme.properties['--USER__fontFamily'], undefined, 'the typeface of the first preset is gone')
    assert.equal(theme.properties['--USER__fontSize'], undefined, 'so is its size')
    await reader.page.close()
  })

  it('an axis moved after the preset stays moved', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'theme', theme: PAPER })
    await reader.send({ type: 'preferences', preferences: { fontSize: 1.5 } })
    const applied = await reader.waitFor('preferences', (m) => m.properties['--USER__fontSize'] === '150%')
    assert.equal(applied.properties['--USER__backgroundColor'], '#ffffff')
    await reader.page.close()
  })
})

describe('the "search-results" message', () => {
  it('lists each match with its context and a locator that goes there', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'search', id: 'q1', query: 'PARAGRAPH 12' })

    const done = await reader.waitFor('search-results', (m) => m.id === 'q1' && m.done)
    const results = (await reader.messages('search-results')).filter((m) => m.id === 'q1').flatMap((m) => m.results)
    assert.equal(done.total, 2)
    assert.deepEqual(results.map((r) => r.locator.href), [CH1, CH2])

    const first = results[0]
    assert.equal(first.locator.text.highlight, 'paragraph 12')
    assert.match(first.locator.text.before, /Chapter 1, $/)
    assert.match(first.locator.text.after, /^\. Text long enough/)
    assert.equal(first.locator.title, 'Chapter One')
    assert.ok(first.locator.locations.progression > 0 && first.locator.locations.progression < 1)

    await reader.send({ type: 'go', locator: results[1].locator })
    await reader.waitFor('locator', (m) => m.locator.href === CH2)
    await reader.page.close()
  })

  it('finds text in any case', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'search', id: 'q2', query: 'chapter ONE' })
    const done = await reader.waitFor('search-results', (m) => m.id === 'q2' && m.done)
    assert.equal(done.total, 1)
    await reader.page.close()
  })

  it('an empty result still says it is done', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'search', id: 'none', query: 'zzyzx' })
    const done = await reader.waitFor('search-results', (m) => m.id === 'none' && m.done)
    assert.equal(done.total, 0)
    assert.deepEqual(done.results, [])
    await reader.page.close()
  })

  it('a blank query is answered with an empty, finished result', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'search', id: 'blank', query: '   ' })
    const done = await reader.waitFor('search-results', (m) => m.id === 'blank' && m.done)
    assert.equal(done.total, 0)
    await reader.page.close()
  })

  it('a newer search silences the one before it', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    // Both in one turn of the page, so the second starts while the first is reading chapters.
    await reader.page.evaluate(() => {
      window.__reader.receive({ type: 'search', id: 'old', query: 'paragraph' })
      window.__reader.receive({ type: 'search', id: 'new', query: 'paragraph 3' })
    })
    await reader.waitFor('search-results', (m) => m.id === 'new' && m.done)
    await reader.page.waitForTimeout(300)
    assert.deepEqual(
      (await reader.messages('search-results')).filter((m) => m.id === 'old' && m.done),
      [],
      'the old search never reports done',
    )
    await reader.page.close()
  })
})

describe('the "highlights" and "highlight-activated" messages', () => {
  async function searchOne(reader, query) {
    await reader.send({ type: 'search', id: `find-${query}`, query })
    const done = await reader.waitFor('search-results', (m) => m.id === `find-${query}` && m.done)
    return (await reader.messages('search-results')).filter((m) => m.id === done.id).flatMap((m) => m.results)[0].locator
  }

  it('draws a highlight in the content and acknowledges it by id', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    const locator = await searchOne(reader, 'paragraph 2.')
    await reader.send({ type: 'highlights', items: [{ id: 'h1', locator, color: '#ffd54a' }] })

    const ack = await reader.waitFor('highlights')
    assert.deepEqual(ack.ids, ['h1'])
    // The toolkit draws a highlight with the CSS Custom Highlight API: a registered range
    // and a style rule named for it.
    await reader.frame().waitForFunction(
      () => CSS.highlights.size > 0 && document.querySelector('style[id^="readium-decoration-"]') !== null,
      undefined,
      { timeout: 5000 },
    )
    await reader.page.close()
  })

  it('replaces the whole set, so a removed highlight goes', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    const locator = await searchOne(reader, 'paragraph 2.')
    await reader.send({ type: 'highlights', items: [{ id: 'h1', locator, color: '#ffd54a' }] })
    await reader.waitFor('highlights')
    await reader.send({ type: 'highlights', items: [] })
    const ack = await reader.waitFor('highlights', (m) => m.ids.length === 0)
    assert.deepEqual(ack.ids, [])
    await reader.frame().waitForFunction(() => CSS.highlights.size === 0, undefined, { timeout: 5000 })
    await reader.page.close()
  })

  it('names the highlight a reader clicked', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    const locator = await searchOne(reader, 'paragraph 2.')
    await reader.send({ type: 'highlights', items: [{ id: 'h-click', locator, color: '#ffd54a' }] })
    await reader.waitFor('highlights')
    await reader.page.waitForTimeout(500)

    // The decoration is painted on the text it marks, so a click on that text is a click on it.
    const at = await reader.frame().evaluate(() => {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const start = node.data.indexOf('paragraph 2.')
        if (start < 0) continue
        const range = document.createRange()
        range.setStart(node, start)
        range.setEnd(node, start + 'paragraph 2.'.length)
        const rect = range.getBoundingClientRect()
        return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 }
      }
      return undefined
    })
    const frameBox = await (await reader.frame().frameElement()).boundingBox()
    await reader.page.mouse.click(frameBox.x + at.x, frameBox.y + at.y)
    const activated = await reader.waitFor('highlight-activated')
    assert.equal(activated.id, 'h-click')
    await reader.page.close()
  })
})

describe('the "selection" message', () => {
  it('reports the text a reader selected and where it is', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.frame().locator('p', { hasText: 'paragraph 3.' }).dblclick()
    const selection = await reader.waitFor('selection')
    assert.ok(selection.text.length > 0)
    assert.equal(selection.locator.href, CH1)
    assert.equal(selection.locator.text.highlight, selection.text)
    assert.ok(selection.rect.width > 0 && selection.rect.height > 0)
    await reader.page.close()
  })
})

describe('the transport', () => {
  it('uses the WebKit handler when there is one', async () => {
    const reader = await openReader(harness)
    const posted = await reader.page.evaluate(() => {
      const seen = []
      const scope = { webkit: { messageHandlers: { storyarc: { postMessage: (m) => seen.push(m) } } } }
      StoryArcEpub.hostPost(scope)({ type: 'x' })
      return seen
    })
    assert.deepEqual(posted, [{ type: 'x' }])
    await reader.page.close()
  })

  it('uses the WebView2 door when that is the one there is', async () => {
    const reader = await openReader(harness)
    const posted = await reader.page.evaluate(() => {
      const seen = []
      StoryArcEpub.hostPost({ chrome: { webview: { postMessage: (m) => seen.push(m) } } })({ type: 'y' })
      return seen
    })
    assert.deepEqual(posted, [{ type: 'y' }])
    await reader.page.close()
  })

  it('drops a message quietly when there is no host', async () => {
    const reader = await openReader(harness)
    const result = await reader.page.evaluate(() => StoryArcEpub.hostPost({})({ type: 'z' }))
    assert.equal(result, undefined)
    await reader.page.close()
  })
})
