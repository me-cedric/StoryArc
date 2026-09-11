// Installs the built app on a booted simulator, then seeds it, so the UI tests audit a
// populated screen.
//
// **This is the step the iOS CI job did not have.** `scripts/seed-simulator.mjs` existed and
// nothing called it, so every audit ran against a clean device. An empty shelf makes
// `LibraryToolbar` hide Select, View and Filter — they sit behind
// `if !model.publications.isEmpty` — and the walks then reported "The library toolbar offers
// no View menu" about a menu that is implemented, beside "This library has nothing to read"
// and "No audiobook on this device's library or downloads", which said the true thing
// plainly.
//
// Install before seed, not after: `seed-simulator.mjs` writes into the app's own container,
// and `simctl get_app_container` has nothing to answer with until the app is installed. That
// is why the flow is three steps — `build:ios:ui`, `seed:ios:ui`, `test:ios:ui` — rather than
// one `xcodebuild test`, which installs at the moment it starts running and leaves no seam to
// seed in.

import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

/** Where `build:ios:ui` leaves the app. The two must agree, so both name the same path. */
const PRODUCTS = join(ROOT, '.build/ios-ui/Build/Products')

const DEVICE = 'iPhone 17 Pro'

const run = (file, args) => execFileSync(file, args, { encoding: 'utf8', stdio: 'inherit' })
const read = (file, args) => execFileSync(file, args, { encoding: 'utf8' }).trim()

/**
 * The built app bundle.
 *
 * The configuration folder is named by the scheme's build configuration, which this script
 * does not choose, so it is found rather than assumed. Named rather than swallowed: a missing
 * bundle means `build:ios:ui` did not run, and saying so beats a `simctl install` usage error.
 */
const appBundle = () => {
  if (!existsSync(PRODUCTS)) {
    console.error(`No build products at ${PRODUCTS}. Run \`pnpm build:ios:ui\` first.`)
    process.exit(1)
  }
  for (const configuration of readdirSync(PRODUCTS)) {
    const folder = join(PRODUCTS, configuration)
    const app = readdirSync(folder).find((entry) => entry.endsWith('.app'))
    if (app) return join(folder, app)
  }
  console.error(`No .app under ${PRODUCTS}. Run \`pnpm build:ios:ui\` first.`)
  process.exit(1)
}

// Wait for the boot to finish rather than for the device to answer. The epub job learned
// this on 2026-09-09: `xcodebuild` begins as soon as the device replies, which is before its
// services are up.
run('xcrun', ['simctl', 'bootstatus', DEVICE, '-b'])

const app = appBundle()
console.log(`Installing ${app.slice(ROOT.length + 1)} on ${DEVICE}`)
run('xcrun', ['simctl', 'install', DEVICE, app])

// The device is named, and it has to be. `seed-simulator.mjs` falls back to the **first**
// booted device, and more than one is booted whenever an iPad walk has run — so the seed
// landed on an iPad while `test:ios:ui` ran on the iPhone, and the iPhone kept whatever an
// earlier run had left it. Measured on 2026-09-11: the install said `iPhone 17 Pro` and the
// seed said `Seeded 2 publications on C88E620F`, which is an iPad Air. The check below passed
// on stale content, so nothing reported it.
run('node', [join(ROOT, 'scripts/seed-simulator.mjs'), '--device', DEVICE])

// Proof, not hope: the container now holds the scanned copies a sweep depends on, and a sweep
// clears the download record. A silent seed that wrote nothing looks exactly like a seed that
// was never called, which is the failure this script exists to end.
const container = read('xcrun', ['simctl', 'get_app_container', DEVICE, 'com.mecedric.storyarc', 'data'])
const documents = join(container, 'Documents')
const seeded = existsSync(documents) ? readdirSync(documents) : []
if (seeded.length === 0) {
  console.error(`Nothing in ${documents}. The sweeps would find an empty shelf.`)
  process.exit(1)
}
console.log(`Documents holds ${seeded.length} entr${seeded.length === 1 ? 'y' : 'ies'}: ${seeded.join(', ')}`)
