#!/usr/bin/env node
// Registers mock sources on a simulator, by writing the registry the app reads at launch.
//
// The iOS twin of `scripts/seed-android-sources.mjs`, and it exists for the same reason:
// `source-lifecycle` owes frames of states only a **registered** source reaches — the detail
// screen with its five fields, the removal confirmation with a real title count, an
// unreachable server beside a reachable one, and one title held by two sources. The corpus
// alone cannot reach any of them, because its publications belong to no source.
//
// Where Android keeps the registry in a preference file, iOS keeps it as one JSON blob in
// `UserDefaults` under `app.storyarc.sources` — see `Persistence/SourceStore.swift`, which
// says why it is one blob rather than a key per field. `simctl spawn defaults write` writes
// it, and `-data <hex>` is how a `Data` value is written from a shell.
//
// **Only OPDS sources, and deliberately.** A Kavita source needs an API key, and a secret
// lives in the Keychain rather than in defaults, so a seeded Kavita entry would name a secret
// that is not there. An OPDS catalogue with no sign-in needs none.
//
// Usage:
//   node scripts/seed-simulator-sources.mjs                        (three sources, two live)
//   node scripts/seed-simulator-sources.mjs --device "iPhone 17 Pro" --ports 4444,4447
//   node scripts/seed-simulator-sources.mjs --clear                 (forget every source)

import { execFileSync } from 'node:child_process'

const args = process.argv.slice(2)
const flag = (name, fallback) => {
  const at = args.indexOf(name)
  return at === -1 ? fallback : args[at + 1]
}

const DEVICE = flag('--device', 'iPhone 17 Pro')
const BUNDLE = flag('--bundle', 'com.mecedric.storyarc')
const KEY = 'app.storyarc.sources'

/**
 * The host, as a simulator sees it.
 *
 * A simulator shares the Mac's own network stack, so `127.0.0.1` is the Mac. This is the one
 * line that differs from the Android script, where `10.0.2.2` is the emulator's alias for it.
 */
const HOST = flag('--host', '127.0.0.1')

/** The acquisition feed, for the reason the Android script's own note gives. */
const FEED = flag('--feed', '/opds/all')

const [live, second] = flag('--ports', '4444,4447').split(',')
const DEAD = flag('--dead-port', '4999')

const simctl = (...rest) => execFileSync('xcrun', ['simctl', ...rest], { encoding: 'utf8' }).trim()

/**
 * The registry, in the shape `StoredRegistry` decodes.
 *
 * The same three sources the Android script writes, with the same names and the same fixed
 * identifiers, so a frame taken on one platform names what a frame taken on the other names.
 *
 * `lastSuccessfulSync` is null on every one: connection state is never persisted, and a
 * *Last synchronised* the app never earned would be a claim about a past that did not happen.
 */
const registry = {
  sources: [
    {
      id: '11111111-1111-4111-8111-111111111111',
      displayName: 'Attic Catalogue',
      kind: 'opdsCatalog',
      lastSuccessfulSync: null,
      credentialReference: null,
      locator: `http://${HOST}:${live}${FEED}`,
    },
    {
      id: '22222222-2222-4222-8222-222222222222',
      displayName: 'Loft Catalogue',
      kind: 'opdsCatalog',
      lastSuccessfulSync: null,
      credentialReference: null,
      locator: `http://${HOST}:${second}${FEED}`,
    },
    {
      // A port nothing listens on, rather than a name that does not resolve: a refused
      // connection is the state `source-lifecycle` calls *Not answering*, and a DNS failure
      // is a different sentence.
      id: '33333333-3333-4333-8333-333333333333',
      displayName: 'Cellar Catalogue',
      kind: 'opdsCatalog',
      lastSuccessfulSync: null,
      credentialReference: null,
      locator: `http://${HOST}:${DEAD}${FEED}`,
    },
  ],
  tombstones: [],
}

// The app has to be down. It reads the registry once at launch and writes its own back when a
// reader edits one, so a blob written under a running app is overwritten by what it holds.
//
// An app that is not running is the state this wants, and `simctl terminate` answers non-zero
// for it — so the failure is swallowed here rather than treated as one.
try {
  execFileSync('xcrun', ['simctl', 'terminate', DEVICE, BUNDLE], { stdio: 'ignore' })
} catch {
  // Already down.
}

if (args.includes('--clear')) {
  simctl('spawn', DEVICE, 'defaults', 'delete', BUNDLE, KEY)
  console.log('Sources cleared. *Your libraries* is empty again.')
} else {
  const hex = Buffer.from(JSON.stringify(registry), 'utf8').toString('hex')
  simctl('spawn', DEVICE, 'defaults', 'write', BUNDLE, KEY, '-data', hex)
  const written = simctl('spawn', DEVICE, 'defaults', 'read', BUNDLE, KEY)
  // Proof rather than hope: `defaults` reports success for a write it did not make when the
  // domain does not exist yet, and a silent no-op looks exactly like a seed that worked.
  if (!written.replace(/\s/g, '').includes(hex.slice(0, 32))) {
    console.error(`Wrote nothing readable to ${BUNDLE} ${KEY}.`)
    process.exit(1)
  }
  const names = registry.sources.map((source) => source.displayName).join(', ')
  console.log(`Registered ${registry.sources.length} sources on ${DEVICE}: ${names}`)
  console.log(`Live on ${HOST}:${live} and ${HOST}:${second}; ${HOST}:${DEAD} answers nothing, by design.`)
  console.log(`Start the mock catalogues first:\n  node scripts/opds-server.mjs <corpus> --port ${live}`)
}
