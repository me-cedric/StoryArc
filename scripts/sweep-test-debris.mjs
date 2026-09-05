// Removes what the host test suites leave on the developer's machine.
//
// **This exists because a test suite went red for twenty minutes on an unchanged commit.**
// `LibraryRestoreTests` failed two cases, then passed again with no source change, and the
// cause was state that outlived the test process: a `library.json` snapshot written into the
// machine's real caches directory by a model built with the default `LibraryCache()`. That
// half is fixed in the source — the suites that scan now take a cache of their own, and
// planting a snapshot no longer reddens them. What is *not* fixable in the source without
// restructuring twenty-one call sites is the debris, and the debris is what made the machine
// unlike a clean one in the first place.
//
// Two kinds, both measured before this script existed:
//
//   - **2 024 `.plist` files** in `~/Library/Preferences`. Twenty-one test files ask for a
//     `UserDefaults(suiteName:)` with a fresh UUID so one test's remembered folders are not
//     another's — real isolation, and correct. Five of them then call
//     `removePersistentDomain(forName:)`, which empties the domain and **leaves the file**;
//     the other sixteen call nothing at all. So every run of the host suite added several
//     files that nothing would ever remove.
//   - **683 scratch directories** under the system temp folder. `AudiobookScanningTests` now
//     removes its own, and `LibraryRestoreTests` already did; these are what accumulated
//     before either of them did, plus whatever a crashed run leaves behind.
//
// **Why a sweep rather than per-test cleanup.** The obvious fix — a non-copyable helper whose
// `deinit` removes the domain and the file — does not fit the call sites: most of them build
// the suite inside a helper that returns only the *store*, so the wrapper would go out of
// scope and wipe the domain in the middle of the test that is using it. Fixing that properly
// means restructuring twenty-one helpers to thread a lifetime through, which is a large and
// risky change to make for housekeeping. A sweep after the run costs nothing and cannot break
// a test, because by then there is no test.
//
// It is deliberately **conservative**: it removes only names it can attribute to this
// repository's suites, and it never touches a file it did not recognise. A script that deletes
// things out of `~/Library/Preferences` gets one chance to be too clever.

import { readdirSync, rmSync, statSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'

/** Suite-name prefixes the host tests use. Every one is followed by a UUID. */
const SUITE_PREFIXES = [
    'app.storyarc.tests.',
    'restore-',
    'cards-',
    'test-',
    'downloads-',
    'storyarc-',
]

/** Scratch-directory prefixes the host tests create under the temp folder. */
const FOLDER_PREFIXES = ['scan-', 'handed-', 'restore-', 'documents-', 'downloads-', 'storyarc-']

/** A UUID with or without its hyphens, which is what every one of these names ends in. */
const UUID_TAIL = /[0-9A-Fa-f]{8}-?(?:[0-9A-Fa-f]{4}-?){3}[0-9A-Fa-f]{12}$/

/**
 * Whether a name is one of ours.
 *
 * The UUID tail is required, not optional. `test-` alone would match anything a developer had
 * named `test-something`, and a prefix list is not an argument for deleting a file whose shape
 * says nobody generated it.
 */
function isOurs(name, prefixes) {
    const bare = name.endsWith('.plist') ? name.slice(0, -'.plist'.length) : name
    return prefixes.some((p) => bare.startsWith(p)) && UUID_TAIL.test(bare)
}

function sweep(directory, prefixes, { plists }) {
    let removed = 0
    let entries
    try {
        entries = readdirSync(directory)
    } catch {
        return 0
    }
    for (const name of entries) {
        if (plists && !name.endsWith('.plist')) continue
        if (!isOurs(name, prefixes)) continue
        const path = join(directory, name)
        try {
            // A plist is a file and a scratch folder is a directory; asking rather than
            // assuming keeps a stray file of the right name from being passed to a recursive
            // remove, and the reverse.
            const stat = statSync(path)
            if (plists !== stat.isFile()) continue
            rmSync(path, { recursive: !plists, force: true })
            removed += 1
        } catch {
            // A file that vanished under us, or one we may not remove. Neither is worth
            // failing a test run over — this is housekeeping, and it runs after the gate.
        }
    }
    return removed
}

const preferences = join(homedir(), 'Library', 'Preferences')
const plists = sweep(preferences, SUITE_PREFIXES, { plists: true })
const folders = sweep(tmpdir(), FOLDER_PREFIXES, { plists: false })

if (plists || folders) {
    console.log(
        `test debris: removed ${plists} defaults suite(s) and ${folders} scratch folder(s).`
    )
}
