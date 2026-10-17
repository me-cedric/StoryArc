// Task 4.1: the bundle's API, in a real browser. A fixture manifest from fixture.mjs, resources
// served by a local static server, headless WebKit by default.
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

describe('the bundle opens a publication', () => {
  it('says it is ready and reports the first position', async () => {
    const reader = await openReader(harness)
    const ready = await reader.waitFor('ready')
    assert.equal(ready.title, 'Fixture Publication')
    assert.equal(ready.positions, harness.server.positions.length)

    const first = await reader.waitFor('locator')
    assert.equal(first.locator.href, CH1)
    assert.equal(first.locator.locations.position, 1)
    assert.deepEqual(reader.errors, [])
    await reader.page.close()
  })
})

describe('a locator round trip', () => {
  it('a locator the reader posted takes the reader back to the same place', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')

    await reader.send({
      type: 'go',
      locator: { href: CH2, type: 'application/xhtml+xml', locations: { progression: 0.5 } },
    })
    const there = await reader.waitFor('locator', (m) => m.locator.href === CH2 && m.locator.locations.progression > 0)
    assert.ok(there.locator.locations.totalProgression >= 0.5, 'chapter two is the second half of the book')

    // The host stores the JSON, restarts, and hands it back.
    const stored = JSON.stringify(there.locator)
    await reader.send({ type: 'go', locator: { href: CH1, type: 'application/xhtml+xml', locations: { progression: 0 } } })
    await reader.waitFor('locator', (m) => m.locator.href === CH1 && m.seq > there.seq)

    await reader.send({ type: 'go', locator: JSON.parse(stored) })
    const back = await reader.waitFor('locator', (m) => m.locator.href === CH2 && m.seq > there.seq)
    assert.equal(back.locator.href, there.locator.href)
    assert.equal(back.locator.locations.progression, there.locator.locations.progression)
    assert.equal(back.locator.locations.position, there.locator.locations.position)
    await reader.page.close()
  })

  it('opens at the locator it is given', async () => {
    const start = { href: CH2, type: 'application/xhtml+xml', locations: { progression: 0 } }
    const reader = await openReader(harness, { options: { locator: start } })
    const first = await reader.waitFor('locator')
    assert.equal(first.locator.href, CH2)
    await reader.page.close()
  })

  it('numbers its messages so the host can drop a stale one', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'next' })
    await reader.page.waitForTimeout(300)
    const seqs = (await reader.messages()).map((m) => m.seq)
    assert.deepEqual(seqs, [...seqs].sort((a, b) => a - b))
    assert.equal(new Set(seqs).size, seqs.length)
    await reader.page.close()
  })
})

describe('the preference axes arrive as CSS properties', () => {
  it('sets each axis on the content document', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({
      type: 'preferences',
      preferences: {
        fontSize: 1.5,
        fontFamily: 'Georgia, serif',
        fontWeight: 700,
        lineHeight: 1.8,
        letterSpacing: 0.05,
        wordSpacing: 0.2,
        paragraphSpacing: 1.25,
        pageGutter: 48,
        textAlign: 'justify',
        backgroundColor: '#fdf6e3',
        textColor: '#073642',
      },
    })
    const applied = await reader.waitFor('preferences')
    assert.equal(applied.properties['--USER__textColor'], '#073642')

    const read = (name) =>
      reader.frame().evaluate((name) => document.documentElement.style.getPropertyValue(name).trim(), name)
    const properties = {
      '--USER__fontSize': '150%',
      '--USER__fontFamily': 'Georgia, serif',
      '--USER__fontWeight': '700',
      '--USER__lineHeight': '1.8',
      '--USER__letterSpacing': '0.05rem',
      '--USER__wordSpacing': '0.2rem',
      '--USER__paraSpacing': '1.25rem',
      '--RS__pageGutter': '48px',
      '--USER__textAlign': 'justify',
      '--USER__backgroundColor': '#fdf6e3',
      '--USER__textColor': '#073642',
    }
    for (const [name, value] of Object.entries(properties)) assert.equal(await read(name), value, name)
    await reader.page.close()
  })

  it('a later preference keeps the axes it does not name', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.send({ type: 'preferences', preferences: { lineHeight: 1.6 } })
    await reader.send({ type: 'preferences', preferences: { fontSize: 1.2 } })
    const applied = await reader.waitFor('preferences', (m) => m.properties['--USER__fontSize'] !== undefined)
    assert.equal(applied.properties['--USER__lineHeight'], '1.6')
    await reader.page.close()
  })
})

describe('links and footnotes', () => {
  it('a footnote reference posts the note and does not move the reader', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    const before = (await reader.messages('locator')).length

    await reader.frame().locator('#noteref').click()
    const note = await reader.waitFor('footnote')
    assert.equal(note.text, 'The footnote says so.')
    assert.equal(note.href, `${CH1}#fn1`)
    assert.equal((await reader.messages('locator')).length, before, 'the reader stayed where it was')
    await reader.page.close()
  })

  it('a link out of the book posts the link and the page does not leave', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    const hostUrl = reader.page.url()
    const outside = `${harness.server.origin}/outside`

    await reader.frame().locator('#out').click()
    const link = await reader.waitFor('link')
    assert.equal(link.href, outside)
    await reader.page.waitForTimeout(300)
    assert.equal(reader.page.url(), hostUrl)
    assert.ok(!harness.server.hits.includes('/outside'), 'nothing was fetched from the link')
    await reader.page.close()
  })

  it('a link naming a scheme other than http or https is dropped', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    const hostUrl = reader.page.url()

    await reader.frame().locator('#mail').click()
    await reader.page.waitForTimeout(300)
    assert.deepEqual(await reader.messages('link'), [])
    assert.deepEqual(await reader.messages('footnote'), [])
    assert.equal(reader.page.url(), hostUrl)
    await reader.page.close()
  })

  it('an internal link moves the reader and is not reported as leaving', async () => {
    const reader = await openReader(harness)
    await reader.waitFor('locator')
    await reader.frame().locator('#next').click()
    await reader.waitFor('locator', (m) => m.locator.href === CH2)
    assert.deepEqual(await reader.messages('link'), [])
    await reader.page.close()
  })
})
