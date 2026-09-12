#!/usr/bin/env node
// Registers mock sources on an emulator, by writing the registry the app reads at launch.
//
// `source-lifecycle` owes eight frames of states that only a **registered** source can be
// in: the detail screen with its five fields, the removal confirmation with a real title
// count, the "cannot be reached" notice, and the precedence rule with two sources holding
// one title. None of them is reachable on a device whose *Your libraries* is empty, and the
// corpus alone leaves it empty — its publications carry `origin: EMBEDDED` and belong to no
// source.
//
// Driving the add form through `adb shell input text` was the alternative, and it is worse:
// three sources is three form walks, each one a sequence of taps that breaks whenever a
// field moves. The registry is one JSON blob in one preference file (see `SourceStore`), so
// this writes that file instead.
//
// **Only OPDS sources, and deliberately.** A Kavita source needs an API key, and a secret
// lives in the Android Keystore encrypted under a key the app cannot export (see
// `CredentialStore`) — so a seeded Kavita entry would hold a reference to a secret that is
// not there. An OPDS catalogue with no sign-in needs no secret, which is why the mock
// catalogue rather than the mock Kavita is what these frames are taken against.
//
// Usage:
//   node scripts/seed-android-sources.mjs                       (three sources, two live)
//   node scripts/seed-android-sources.mjs --device emulator-5554 --ports 4444,4446
//   node scripts/seed-android-sources.mjs --clear               (forget every source)
//   node scripts/seed-android-sources.mjs --refused-kavita      (one server needing sign-in)
//
// It needs `adb root`, which an emulator gives and a phone does not. The file it writes
// belongs to the app's own uid, so the mode and the owner are restored after the copy — a
// preference file the app cannot read is indistinguishable from no sources at all.

import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const args = process.argv.slice(2)
const flag = (name, fallback) => {
  const at = args.indexOf(name)
  return at === -1 ? fallback : args[at + 1]
}

const PACKAGE = flag('--package', 'com.mecedric.storyarc.debug')
const PREFS = `/data/data/${PACKAGE}/shared_prefs/app.storyarc.sources.xml`

/** The host, as an emulator sees it. `localhost` on the device is the device. */
const HOST = flag('--host', '10.0.2.2')

/**
 * The feed the source saves, and it has to be the **acquisition** feed.
 *
 * `OpdsContributor` reads "one feed, not a walk" — the one the reader saved. `/opds` is the
 * navigation feed, whose entries are ways further in and not publications, so a source
 * saved there contributes nothing and the detail screen reads `0 titles`. Measured on
 * 2026-09-11: three seeded sources, every one of them `Available` and every one `0 titles`,
 * until this pointed at `/opds/all`.
 */
const FEED = flag('--feed', '/opds/all')

/** Where the two live catalogues answer, and where the third deliberately does not. */
const [live, second] = flag('--ports', '4444,4446').split(',')
const DEAD = flag('--dead-port', '4999')

const adb = (...rest) => {
  const device = flag('--device', null)
  const head = device ? ['-s', device] : []
  return execFileSync('adb', [...head, ...rest], { encoding: 'utf8' }).trim()
}

/**
 * The registry, in the shape `StoredRegistry` decodes.
 *
 * Fixed identifiers rather than generated ones, so a re-seed replaces the same three
 * sources and a screenshot taken today names the source a screenshot taken tomorrow names.
 * `lastSuccessfulSyncEpochMillis` is null on every one of them: connection state is not
 * stored (`SourceStore` says why), and a *Last synchronised* the app never earned would be
 * a claim about a past that did not happen.
 *
 * The order is the registry order, which is the precedence order `SourcePrecedence` ranks
 * by — so *Attic Catalogue* wins a title both catalogues hold, and that is the frame task
 * 4.5 asks for.
 */
const registry = {
  sources: [
    {
      id: '11111111-1111-4111-8111-111111111111',
      displayName: 'Attic Catalogue',
      kind: 'OPDS_CATALOG',
      lastSuccessfulSyncEpochMillis: null,
      credentialReference: null,
      locator: `http://${HOST}:${live}${FEED}`,
    },
    {
      id: '22222222-2222-4222-8222-222222222222',
      displayName: 'Loft Catalogue',
      kind: 'OPDS_CATALOG',
      lastSuccessfulSyncEpochMillis: null,
      credentialReference: null,
      locator: `http://${HOST}:${second}${FEED}`,
    },
    {
      // The unreachable one. A port nothing listens on, rather than a hostname that does
      // not resolve: a refused connection is the state `source-lifecycle` calls *Not
      // answering*, and a DNS failure is a different sentence.
      id: '33333333-3333-4333-8333-333333333333',
      displayName: 'Cellar Catalogue',
      kind: 'OPDS_CATALOG',
      lastSuccessfulSyncEpochMillis: null,
      credentialReference: null,
      locator: `http://${HOST}:${DEAD}${FEED}`,
    },
  ],
  tombstones: [],
}

/**
 * A Kavita server whose key is gone, which is the *refused credential* state.
 *
 * **Deterministic, and that is why it exists.** `source-lifecycle` §4.2 needs a source whose
 * credential a server refused, and the obvious fixture — a mock served with a rotated key — is
 * a race: the probe lands on 401 on one launch and on a connection failure on the next, and
 * only the first offers *Sign in again*.
 *
 * `SourceHealth.probe` has a second route to the same state, and its last line says so:
 * "Neither page could be built, so the secret this source needs has gone" returns
 * `Unauthorized`. A `credentialReference` naming a secret the Android Keystore does not hold
 * reaches it, asks nothing of the network, and therefore cannot flicker. iOS's
 * `MockCatalogues.refusedKavita` is the same fixture against the same sentence.
 */
const refusedKavita = {
  sources: [
    {
      id: '44444444-4444-4444-8444-444444444444',
      displayName: 'Attic Kavita',
      kind: 'KAVITA_SERVER',
      lastSuccessfulSyncEpochMillis: null,
      credentialReference: 'a-secret-this-keystore-does-not-hold',
      locator: `http://${HOST}:5000`,
    },
  ],
  tombstones: [],
}

const escape = (text) =>
  text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

/** Which registry to write: the three catalogues, or the one refused server. */
const chosen = args.includes('--refused-kavita') ? refusedKavita : registry

const xml = args.includes('--clear')
  ? "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map />\n"
  : "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n" +
    `    <string name="registry">${escape(JSON.stringify(chosen))}</string>\n</map>\n`

adb('root')
// The app has to be down. `SharedPreferences` keeps the map in memory and writes it back on
// the next edit, so a file written under a running app is overwritten by what the app
// already held.
adb('shell', 'am', 'force-stop', PACKAGE)

const scratch = join(tmpdir(), 'storyarc-sources.xml')
writeFileSync(scratch, xml)
adb('push', scratch, '/data/local/tmp/storyarc-sources.xml')

// The owner and the mode of a neighbouring preference file, so this one is indistinguishable
// from a file the app wrote itself. A root-owned file in that directory is a file the app
// cannot open, and the shelf then reads "nothing here" for a reason nothing reports.
const neighbour = `/data/data/${PACKAGE}/shared_prefs/app.storyarc.library.xml`
const owner = adb('shell', `stat -c %u:%g ${neighbour}`)
adb('shell', `cp /data/local/tmp/storyarc-sources.xml ${PREFS}`)
adb('shell', `chown ${owner} ${PREFS}`)
adb('shell', `chmod 660 ${PREFS}`)
adb('shell', `restorecon ${PREFS}`)
adb('shell', 'rm /data/local/tmp/storyarc-sources.xml')

const written = adb('shell', `cat ${PREFS}`)
if (args.includes('--clear')) {
  console.log('Sources cleared. *Your libraries* is empty again.')
} else {
  const names = chosen.sources.map((source) => source.displayName).join(', ')
  console.log(`Registered ${chosen.sources.length} sources: ${names}`)
  console.log(`Live on ${HOST}:${live} and ${HOST}:${second}; ${HOST}:${DEAD} answers nothing, by design.`)
  console.log(`Start the mock catalogues first:\n  node scripts/opds-server.mjs <corpus> --port ${live}`)
}
if (!written.includes('registry') && !args.includes('--clear')) {
  console.error(`Wrote nothing readable to ${PREFS}.`)
  process.exit(1)
}
