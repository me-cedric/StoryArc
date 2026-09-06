// Says whether the live servers are reachable, without ever saying what they are.
//
// Usage: pnpm live:check            reads `.env`, reports, exits non-zero on a failure
//        pnpm live:check --names    lists the variables and whether each is set, no network
//        node scripts/live-check.mjs --self-test
//
// **Why this exists.** `scripts/kavita-server.mjs` and `scripts/opds-server.mjs` answer
// everything a mock can answer, and `STATUS.md` records what they cannot: the permission
// model, a real conflict, and whether an SMB share that demands encryption is refused as
// such. Those need the owner's own servers, and a server needs a secret.
//
// **Nothing here may print a secret.** Every value is redacted to its shape — a length and
// a last character or two — because a check that leaks a key into a terminal, a CI log or an
// agent transcript is worse than no check. `redact` is the only way a value reaches output,
// and its test is the first one below. A URL is redacted too: Kavita puts the OPDS key in
// the path, so an address is a credential.
//
// The app reads none of this. A reader types a server into the app and the secret goes to
// the platform's secure store, which is what `sources` requires.

import { existsSync } from 'node:fs'

const args = process.argv.slice(2)
const selfTest = args.includes('--self-test')
const namesOnly = args.includes('--names')

/**
 * A value reduced to its shape.
 *
 * Enough to tell "I pasted the wrong thing" from "I pasted nothing", and not enough to use.
 * The tail is two characters because one is noise and four is a meaningful prefix of a
 * short key.
 */
export const redact = (value) => {
  if (value === undefined || value === null || value === '') return 'unset'
  const text = String(value)
  if (text.length <= 4) return `set, ${text.length} characters`
  return `set, ${text.length} characters, ends ${text.slice(-2)}`
}

const KAVITA = [
  'STORYARC_KAVITA_URL',
  'STORYARC_KAVITA_API_KEY',
  'STORYARC_KAVITA_OPDS_URL',
  'STORYARC_KAVITA_IMAGE_KEY',
]
const SMB = [
  'STORYARC_SMB_HOST',
  'STORYARC_SMB_SHARE',
  'STORYARC_SMB_USER',
  'STORYARC_SMB_PASSWORD',
]

/** Whether a fetch answered at all, and with what status. Never the body, never the URL. */
const reach = async (url, headers = {}) => {
  try {
    const answer = await fetch(url, { headers, redirect: 'manual' })
    return { ok: answer.status < 400, status: answer.status }
  } catch (error) {
    return { ok: false, status: error?.cause?.code ?? 'unreachable' }
  }
}

if (selfTest) {
  let failures = 0
  const check = (what, passed) => {
    console.log(`${passed ? '  ok  ' : ' FAIL '} ${what}`)
    if (!passed) failures += 1
  }
  check('an unset value says so', redact(undefined) === 'unset' && redact('') === 'unset')
  check('a short value gives no characters away', redact('abcd') === 'set, 4 characters')
  const long = redact('sk-abcdefghijklmnop')
  check('a long value gives away only its last two', long === 'set, 19 characters, ends op')
  check('no redaction contains the middle of its value', !long.includes('defghi'))
  // The guard that matters: a URL is a credential here, so it must redact like one.
  const url = redact('https://kavita.example.com/api/opds/9f2b7c1d')
  check('a url is redacted like any other secret', !url.includes('kavita') && !url.includes('9f2b'))
  console.log(failures ? `live-check self-test failed: ${failures}` : 'live-check self-test: 5 checks passed')
  process.exit(failures ? 1 : 0)
}

if (existsSync('.env')) process.loadEnvFile('.env')

const present = (names) => names.filter((n) => process.env[n])
console.log('Values, by shape only:')
for (const name of [...KAVITA, ...SMB, 'STORYARC_SMB_REQUIRES_ENCRYPTION']) {
  console.log(`  ${name.padEnd(34)} ${redact(process.env[name])}`)
}

if (namesOnly) process.exit(0)

let failed = 0
if (present(KAVITA).length === 0) {
  console.log('\nKavita: nothing set, nothing tried.')
} else {
  console.log('\nKavita:')
  const base = process.env.STORYARC_KAVITA_URL
  const key = process.env.STORYARC_KAVITA_API_KEY
  if (base && key) {
    // The call the client itself makes first, and the only one that says whether the key is
    // good: `KavitaClient.authenticate` POSTs the key as a query item to Plugin/authenticate
    // and exchanges it for a token, then every later request carries `Bearer <token>`.
    // Probing anything else answers a question the app never asks — an earlier version of
    // this script used `Server/server-info`, which the mock serves and a real Kavita does
    // not, and reported a 404 that looked like a bad key.
    const url = new URL(`${base.replace(/\/$/, '')}/api/Plugin/authenticate`)
    url.searchParams.set('apiKey', key)
    url.searchParams.set('pluginName', 'StoryArc')
    let answer
    try {
      const got = await fetch(url, { method: 'POST', redirect: 'manual' })
      const body = got.ok ? await got.json().catch(() => null) : null
      answer = { ok: got.ok && Boolean(body?.token), status: got.status }
      if (got.ok && !body?.token) answer.status = `${got.status}, no token in the answer`
    } catch (error) {
      answer = { ok: false, status: error?.cause?.code ?? 'unreachable' }
    }
    console.log(`  key exchanges for a token  ${answer.ok ? 'yes' : 'no'} (${answer.status})`)
    if (!answer.ok) failed += 1
  }
  const opds = process.env.STORYARC_KAVITA_OPDS_URL
  if (opds) {
    const answer = await reach(opds)
    console.log(`  opds feed answers         ${answer.ok ? 'yes' : 'no'} (${answer.status})`)
    if (!answer.ok) failed += 1
  }
}

if (present(SMB).length === 0) {
  console.log('\nSMB: nothing set, nothing tried.')
} else {
  // No connection is attempted from here. An SMB handshake belongs in the app, where the
  // client under test is, and a second implementation in a script would prove nothing about
  // it. This reports only that the values are there for a device walk to use.
  console.log('\nSMB:')
  console.log(`  values for a walk     ${present(SMB).length} of ${SMB.length} set`)
  const encrypted = process.env.STORYARC_SMB_REQUIRES_ENCRYPTION === '1'
  console.log(`  demands encryption    ${encrypted ? 'yes — the refusal is reachable' : 'not declared'}`)
  if (!encrypted) {
    console.log('  note: SmbError.encryptionRequired cannot be observed until a share requires it.')
  }
}

process.exit(failed ? 1 : 0)
