#!/usr/bin/env node
/**
 * Copies a small, named set of real publications into a local showcase library.
 *
 * The store listing needs a shelf a stranger believes. `corpus.mjs` cannot supply one:
 * its nineteen publications are gradient PNGs with names like *Foreign Codec*, which is
 * exactly right for proving a decoder and exactly wrong for a screenshot somebody decides
 * to install from. So the shelf in the store frames is real files off the owner's own
 * drive.
 *
 * **Nothing here is committed.** These are third-party comics and books; the manifest
 * below names them, and the copies live outside the repository (`LIBRARY`). A machine without the source
 * volume gets a clear refusal rather than a silent half-library — which is the whole
 * reason the set is a manifest rather than "whatever is in that folder", because
 * "whatever is in that folder" produces a different shelf on every machine and a store
 * frame nobody can reproduce.
 *
 * The names are rewritten on the way in. A file called
 * `The Boys 001 (2006) (Digital) (Kingpin-Empire).cbr` puts the scene group's name on the
 * shelf, and the shelf is the picture.
 *
 * Usage:
 *   node scripts/store-showcase.mjs              import into the default library
 *   node scripts/store-showcase.mjs --out <dir>  import somewhere else
 *   node scripts/store-showcase.mjs --list       what the manifest names, and its state
 */
import { execFileSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))

/** Where the owner's library lives. Overridable, because one drive is not a contract. */
export const SOURCE = process.env.STORYARC_SHOWCASE_SOURCE ?? '/Volumes/smb/ebooks'

/**
 * Where the imported copies land: outside the repository, so no git command can stage them
 * and every worktree reads the same copy. Overridable for a machine that keeps it elsewhere.
 */
export const LIBRARY = process.env.STORYARC_SHOWCASE ?? join(homedir(), '.cache/storyarc/store-showcase')

const BOYS = 'comics-alternates/The Boys'
const BOOKS = 'books'

/**
 * The showcase set, and why each one is in it.
 *
 * Twelve publications, in four formats, across four series and three standalones. The
 * shape matters more than the titles: `library-browsing` sections a shelf by series, so a
 * set of eleven unrelated files would photograph a feature the app does not have, and a
 * set of eleven issues of one comic would photograph a shelf that looks like a bug.
 *
 * `from` is relative to SOURCE. `as` is the filename the app will read a title out of.
 * `inZip` names an entry inside a bundle, for the two Punisher issues that arrive that way.
 */
export const SHOWCASE = [
  // A run of three, so the shelf has a series heading with something under it.
  { from: `${BOYS}/01. The Boys 001-072+ (2006-2012)/The Boys 001 (2006) (Digital) (Kingpin-Empire).cbr`, as: 'The Boys 001.cbr' },
  { from: `${BOYS}/01. The Boys 001-072+ (2006-2012)/The Boys 002 (2006) (Digital) (Kingpin-Empire).cbr`, as: 'The Boys 002.cbr' },
  { from: `${BOYS}/01. The Boys 001-072+ (2006-2012)/The Boys 003 (2008) (digital) (Kingpin-Empire).cbr`, as: 'The Boys 003.cbr' },
  // A second run, in the other comic container, so CBZ and CBR are both on screen.
  { from: `${BOYS}/02. The Boys - Highland Laddie 001-006+ (2010)/The Boys - Highland Laddie 01 (of 06) (2010) (digital-Empire).cbz`, as: 'The Boys - Highland Laddie 01.cbz' },
  { from: `${BOYS}/02. The Boys - Highland Laddie 001-006+ (2010)/The Boys - Highland Laddie 02 (of 06) (2010) (digital-Empire).cbz`, as: 'The Boys - Highland Laddie 02.cbz' },
  { from: `${BOYS}/03. The Boys - Butcher, Baker, Candlestickmaker 001-006+ (2011)/The Boys - Butcher, Baker, Candlestickmaker 01 (of 06) (2011) (digital-Empire).cbz`, as: 'The Boys - Butcher, Baker, Candlestickmaker 01.cbz' },
  // From a bundle, because that is how they are stored.
  {
    from: 'comics-alternates/source-bundles/Punisher War Zone 001-006 (2009) (Digital) (AnHeroGold-Empire).zip',
    inZip: 'Punisher War Zone 001-006 (2009) (Digital) (AnHeroGold-Empire)/Punisher War Zone 001 (2009) (Digital) (AnHeroGold-Empire).cbz',
    as: 'Punisher War Zone 001.cbz',
  },
  {
    from: 'comics-alternates/source-bundles/Punisher War Zone 001-006 (2009) (Digital) (AnHeroGold-Empire).zip',
    inZip: 'Punisher War Zone 001-006 (2009) (Digital) (AnHeroGold-Empire)/Punisher War Zone 002 (2009) (Digital) (AnHeroGold-Empire).cbz',
    as: 'Punisher War Zone 002.cbz',
  },
  // Three EPUBs, because the app is not a comic reader and a shelf of only comics says it
  // is. Two of them declare a series, which is the reflowable half of the same heading.
  { from: `${BOOKS}/Jennifer Lynch/The Secret Diary of Laura Palmer (Jennifer Lynch).epub`, as: 'The Secret Diary of Laura Palmer.epub' },
  { from: `${BOOKS}/Mark Frost/The Secret History of Twin Peaks by Mark Frost.epub`, as: 'The Secret History of Twin Peaks.epub' },
  { from: `${BOOKS}/Mark Frost/Twin Peaks_ The Final Dossier by Mark Frost.epub`, as: 'Twin Peaks - The Final Dossier.epub' },
  // The audiobook for the player frame. The owner named this file: AAC, an embedded cover
  // and fifty chapters, so the player shows artwork and a chapter title.
  {
    from: 'audiobooks/Dungeon Crawler Carl (Dungeon Crawler Carl 01) by Matt Dinniman (Audiobook)(Fiction).m4b',
    as: 'Dungeon Crawler Carl.m4b',
  },
]

const flag = (name, fallback = null) => {
  const at = process.argv.indexOf(`--${name}`)
  return at === -1 ? fallback : process.argv[at + 1]
}

/** Pulls one entry out of a bundle. `unzip -j` drops the archive's own folders. */
function extract(archive, entry, into, as) {
  execFileSync('/usr/bin/unzip', ['-o', '-j', archive, entry, '-d', into], { stdio: 'pipe' })
  const landed = join(into, entry.split('/').pop())
  if (landed !== join(into, as)) {
    copyFileSync(landed, join(into, as))
    rmSync(landed)
  }
}

/**
 * Fills the library, and says what it could not fill it with.
 *
 * A missing source is reported and skipped rather than fatal: eleven publications where
 * ten arrived is a usable shelf, and refusing to run because one volume moved would make
 * the capture depend on a drive being mounted a particular way. An **empty** library is a
 * different thing and the caller is told so.
 */
export function importShowcase(library = LIBRARY, source = SOURCE) {
  mkdirSync(library, { recursive: true })
  const imported = []
  const missing = []
  for (const item of SHOWCASE) {
    const from = join(source, item.from)
    const target = join(library, item.as)
    if (existsSync(target)) {
      imported.push(item.as)
      continue
    }
    if (!existsSync(from)) {
      missing.push(item.from)
      continue
    }
    if (item.inZip) extract(from, item.inZip, library, item.as)
    else copyFileSync(from, target)
    imported.push(item.as)
  }
  return { imported, missing }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--list')) {
    for (const item of SHOWCASE) {
      const at = join(SOURCE, item.from)
      console.log(`${existsSync(at) ? 'have' : 'MISSING'}  ${item.as}`)
    }
    process.exit(0)
  }

  const library = flag('out', LIBRARY)
  const { imported, missing } = importShowcase(library)
  for (const gone of missing) console.error(`missing at the source: ${gone}`)
  if (imported.length === 0) {
    console.error(`Nothing could be imported. Is ${SOURCE} mounted?`)
    process.exit(1)
  }
  const bytes = readdirSync(library).reduce((sum, f) => sum + statSync(join(library, f)).size, 0)
  console.log(`showcase: ${imported.length} publication(s), ${(bytes / 1e6).toFixed(0)} MB -> ${library}`)
}
