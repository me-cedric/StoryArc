// The matching under the "search-results" message, without a browser: the function is pure.
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { findMatches } from '../src/search.js'

describe('findMatches', () => {
  it('ignores case and accents and reports the original text', () => {
    const [match] = findMatches('Une tarte à la crème, un ÉCLAIR au café.', 'eclair')
    assert.equal(match.highlight, 'ÉCLAIR')
    assert.equal(match.before, 'Une tarte à la crème, un ')
    assert.equal(match.after, ' au café.')
  })

  it('finds a phrase across a line break', () => {
    const [match] = findMatches('the quick\n   brown fox', 'quick brown')
    assert.equal(match.highlight, 'quick brown')
  })

  it('finds every occurrence, in order, with its progression', () => {
    const matches = findMatches('ab ab ab', 'ab')
    assert.deepEqual(matches.map((m) => m.start), [0, 3, 6])
    assert.equal(matches[1].progression, 3 / 8)
  })

  it('does not overlap matches', () => {
    assert.equal(findMatches('aaaa', 'aa').length, 2)
  })

  it('stops at the limit', () => {
    assert.equal(findMatches('a a a a a', 'a', { limit: 3 }).length, 3)
  })

  it('answers nothing for a blank query or no match', () => {
    assert.deepEqual(findMatches('some text', '  '), [])
    assert.deepEqual(findMatches('some text', 'absent'), [])
  })

  it('keeps context to a short window', () => {
    const text = `${'x'.repeat(200)}needle${'y'.repeat(200)}`
    const [match] = findMatches(text, 'needle')
    assert.equal(match.before.length, 40)
    assert.equal(match.after.length, 40)
  })
})
