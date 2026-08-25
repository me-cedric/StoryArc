# Changelog

All notable changes to StoryArc are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The two apps version and release independently — `ios-vX.Y.Z` and
`android-vX.Y.Z` — so entries name the platform they affect.

## [Unreleased]

### Added

- **Format layer, both platforms.** CBZ, CBT, CBR, PDF and plain image folders
  open from real files, asserted against one shared corpus of 22 archives and 2
  PDFs. Format is detected from content, never from the extension.
  - **CBZ** through our own ranged-read ZIP reader (ADR-0008).
  - **CBT** through our own TAR reader: 512-byte headers need no library, so
    libarchive turned out not to be required for it after all. GNU long names and
    pax `path=` records handled.
  - **CBR** through our own RAR header reader plus vendored libarchive for
    decompression only. A remote CBR is catalogued — pages, sizes, cover, solid
    flag — without being downloaded, because RAR headers carry no compression.
    RAR4 and RAR5, stored and compressed.
  - **PDF** through PDFKit and `PdfRenderer`. Page count, geometry in points, and
    on-demand rendering bounded by display size on both; text selection, search
    and outline on iOS only, which `ebook-reader` specifies rather than concedes.
  - **Plain folders** with the same page rules as an archive, not following
    symlinks.
  - **EPUB structure** — metadata, reading order, table of contents, cover and
    the fixed-layout flag — with no dependency, because an EPUB is a ZIP holding
    XML. EPUB 2 and EPUB 3 are both handled explicitly: they keep their contents
    and name their covers differently, and assuming the modern shape loses both
    for every older book. Readium is still needed to *render* reflowable text.
  - **CB7** refused by name, as are solid RAR4, password-protected archives and
    damaged files — four distinct refusals, because "could not open file" tells
    the user nothing.
- **Vendored libarchive**, 26 of 132 sources, compiled by SwiftPM for Apple and
  CMake for all four Android ABIs from one shared copy. Adds ~180 kB on Apple and
  137–149 kB per Android ABI. See `third_party/libarchive/VENDORING.md`.
- **Test corpus** grown to 22 archives and 2 PDFs, including RAR4, RAR5, TAR,
  PDF and a 7-Zip refusal stub. The RAR containers are written by the generator
  itself — store mode needs no compressor — and three compressed or solid
  archives are vendored from libarchive's own suite with provenance recorded.

- **EPUBs read as books**, on both platforms, through Readium (ADR-0005). Real
  pagination, the chapter named, position restored from a stored locator rather
  than a page number — `ebook-reader` requires the position to survive a
  type-size change, and a page number cannot. Progress is a percentage, never a
  reflowable page number, which the spec forbids presenting as an identity.
  Typography controls are absent rather than disabled; they belong to the
  in-flight `reader-theming-and-page-transitions` change.
  - Readium lives behind a boundary on both platforms, and for two different
    platform reasons. On iOS it is a second SwiftPM package, `StoryArcEpub`,
    because Readium declares iOS support only and `StoryArcKit` also builds for
    macOS so its parsers can be tested on the host. On Android it is
    `:feature:epubreader`, because Readium's EPUB navigator is a `Fragment` and
    nothing else in the app is.
  - Our own `EpubReader` still does the indexing — metadata, reading order,
    cover, fixed-layout flag — with no dependency and on the host. Readium is
    only for the part that genuinely needs a rendering engine.
- **The apps actually read comics now, on both platforms.** Pick a folder, watch
  the scan fill a cover grid, open a publication, turn pages, come back and the
  cover carries a progress bar. Right-to-left reading direction throughout.
- **A folder names its series.** `local-library` presents a subfolder of a
  library "as a series whose name is the folder name", and the usual real layout
  — `Bone/001.cbz` — says which issue a file is and never which series. The
  folder now supplies that, and only where nothing better exists: embedded
  metadata and the filename both beat it, because both describe *this*
  publication and a folder name describes its neighbours. A bare number that is
  the whole filename reads as an issue number rather than as a title.
- **Search, sorting and filtering**, on both platforms and behaving identically
  because the rules are one pure function per platform asserted against the same
  table. Search covers titles, series, authors and publishers and ranks a title
  that starts with the query above an author who merely contains it. Sorting is
  by title, series, last read, progress or year, using the device's collation and
  ignoring leading articles in the interface language — "The Sandman" files under
  S, and "La Brea" only loses its article in Spanish. Filters combine with AND,
  carry a visible count, and clear in one action.
- **A compact list beside the cover grid**, with the layout and the active filters
  remembered across launches — a search term deliberately is not, because a
  library narrowed by yesterday's half-typed word reads as a bug.
- **A "Continue reading" row**, most recently read first, absent rather than
  empty when nothing is in progress, and hidden while a search is running.
- **iOS scans its own Documents folder** when no folder has been picked, so a
  comic dropped in through the Files app appears without any setup — the same
  thing Android does with `getExternalFilesDir`.
- **The comic reader zooms.** Pinch about the pinch centre, pan within bounds,
  double-tap to magnify the panel you tapped and again to fit. A `UIScrollView`
  on iOS and Compose's `transformable` on Android, both chosen because they
  decline the drag at fit scale so the pager still turns the page.
- **The end of a volume offers the next one.** Turning past the last page reaches
  an end screen naming what was finished and, when the series has one, the issue
  after it — matched on series and issue number, and only offered when it can
  actually be opened. Deleting the download is part of the same scenario and is
  absent: there are no downloads yet, and a button that deletes nothing is worse
  than none.
- **The reader keeps the screen awake, turns on arrow, page and space keys, and
  prefetches three pages ahead and one behind** — the depth `comic-reader` asks
  for, where it used to keep one either side. A page still loading shows nothing
  for the first 400 ms rather than flashing a spinner on its way past.
- **Reading themes reach the page.** The six presets now render: pick one and the
  EPUB behind the sheet changes immediately, which is what `reading-themes` asks
  for. A stepped text size with a visible position on a nine-rung ladder, and — the
  part that is easy to skip — selecting Original says so, gives the reason in one
  line, offers a single action to switch to StoryArc's typography, and names the
  five axes it makes unavailable rather than hiding them or leaving dead controls.
  - Which axes the publisher's stylesheet overrides is answered by the domain, not
    by Readium's preferences editor: it is a fact about the axis, so it is
    unit-tested on a host rather than observed through a navigator.
  - The token pipeline now emits reading-theme colours as hex as well as platform
    colours, from the same resolved value, because Readium parses its own — so a
    preset's swatch and its rendered page cannot drift apart.
  - Not built yet, and named rather than missing: the fine axes (line, character,
    word and paragraph spacing, margins, alignment), custom backgrounds, and
    reader-local brightness.
- **The reading-theme model**, both platforms, from the in-flight
  `reader-theming-and-page-transitions` change. Six presets — Original, Quiet,
  Paper, Bold, Calm, Focus — whose colours already live in the design tokens and
  therefore already pass the AAA contrast gate at 7:1. `ThemePreset` knows which
  one keeps the publisher's stylesheet (Original alone); `ThemeAxis` knows which
  of the nine axes Readium cannot apply while it is on; `ReadingTheme` is a preset
  plus the axes deviated from, which is the only part Readium will not tell us.
  Deliberately holds no typographic values — a preset is a named Readium
  preferences value and Readium owns those. Ten tests each side, same table.
  `PageTransition.fade` is now `fastFade`, named for what it is.
- **A thumbnail browser.** Every page in a scrollable strip with the current one
  marked, and tapping one jumps to it. Lazy, because it has to be: a 300-page
  comic would otherwise read 300 archive entries to open a strip. Thumbnails are
  decoded per cell as it scrolls into view and the reader keeps a bounded number
  of them, evicting whatever is furthest from where you are looking. The strip
  and the fit menu both hold the chrome open while they are up — reading either
  takes longer than four seconds.
- **Four fit modes**, and the choice persists: fit-to-screen, fit-to-width,
  fit-to-height and original size. Each is expressed as a scale against
  fit-to-screen rather than as its own layout, which is what lets pinch,
  double-tap and the fit control share one number — pinching out of fit-to-width
  is just a larger scale, and pinching back lands on the mode again.
  Fit-to-width opens at the top of the page, which is where reading starts.
  `comic-reader` asks for the choice to persist *per series*; a series is not yet
  something the app can key anything on, so it persists per reader and says so.
- **Tap zones and chrome that gets out of the way.** The left and right quarters
  turn pages without revealing the controls; the centre toggles them; and they
  fade out again after four seconds. A page slider sits under the counter —
  bound to the publication's page number, so its left end is page one in
  right-to-left too. Thumbnails on the slider are not built yet.
- **PDFs read like comics**, on both platforms. Pages are rasterised one at a
  time at the size they are drawn, so a several-hundred-megabyte document opens
  as fast as a small one. iOS renders on an actor because `PDFDocument` is not
  `Sendable`; Android serialises with a lock because `PdfRenderer` permits one
  open page at a time.
- **Reading progress**, per ADR-0006: SwiftData on iOS, Room on Android, written
  every page turn rather than on a clean exit — the normal way a phone closes an
  app is to kill it. Furthest-wins on merge, and finished is sticky.
- **Picked folders survive a restart.** Security-scoped bookmarks on iOS;
  on Android the Storage Access Framework's own persistable URI permission, which
  needs no storage of ours. A folder that can no longer be read is named, with one
  action to pick it again.
- **Android reads folders the user owns.** A tree `Uri` has no path, so the format
  layer gained `UriSource` — ranged reads over a `ParcelFileDescriptor` — plus a
  `DocumentsContract` walk and a document-backed folder archive. Compressed CBRs
  decode straight from a storage provider by handing libarchive
  `/proc/self/fd/N`, with no copy.

### Fixed

- **Covers drifted in the iOS grid.** `LazyVGrid` centres cells vertically and a
  caption runs to one, two or three lines depending on the title and whether
  there is a series — so the row took its height from its wordiest cell and every
  cover in it floated to a different height. The columns align to the top now:
  one line of artwork, captions ending where they end. Android was already
  right — Compose lazy grids top-align by default.

- **SwiftLint had never actually run.** `pnpm lint:ios` changed into `apps/ios`
  first, where there is no `.swiftlint.yml`; SwiftLint then used its defaults and
  linted the vendored dependencies in `.build`, reporting 12,372 violations
  against other people's code. Run from the repository root, where the config
  lives, it found 25 real ones — all now fixed rather than silenced. The script
  no longer changes directory.
  - `LibraryView`, `ZipReader` and `EpubReader` were over the file-length limit
    and are split along seams that were already there: the browsing controls and
    the pre-content states out of the view, DEFLATE and the central directory out
    of the ZIP reader, XML attribute lookup out of the EPUB reader.
  - The four binary parsers keep their branches and carry a `swiftlint:disable`
    naming the reason. A TAR header is a switch over type flags; splitting it
    would hide which early exit means what.

- **`commitlint` never ran.** `commitlint.config.js` used `export default` with
  no `"type": "module"`, so Node loaded it as CommonJS, commitlint saw an empty
  config, and the commit-msg hook rejected every message including valid ones.
  The scope and body-length rules had never once been applied.

- **Contract.** 15 OpenSpec capability specs covering sources, local libraries,
  SMB shares, OPDS catalogues, Kavita servers, publication formats, library
  browsing, collections and reading lists, both readers, reading progress,
  offline downloads, settings, localisation, and the native-experience floor.
- **Design system.** OKLCH token source generating Swift and Kotlin, with a
  WCAG contrast gate that fails the build — 4.5:1 for text, 3:1 for tertiary and
  accents, and AAA for reflowable reader themes. Documented in
  `docs/design/DESIGN.md`.
- **iOS app shell.** SwiftUI on iOS 26, XcodeGen project, one SPM package with
  `DesignSystem`, `StoryArcCore` and `LibraryFeature` targets. Swift 6 language
  mode, strict concurrency, `ExistentialAny` and `InternalImportsByDefault`.
  Localised in English, French, German and Spanish.
- **Android app shell.** Compose on Android 12+, AGP 9 with built-in Kotlin,
  Material 3 Expressive, four Gradle modules. `allWarningsAsErrors` throughout
  and Lint with `warningsAsErrors` on `:app`. Localised in the same four
  languages.
- **Domain layer on both platforms.** Source registry and connection states with
  exponential backoff, content-addressed publication identity, reading positions
  and the progress-merge rules from ADR-0006 — asserted row by row against the
  same table in both test suites.
- **Seven ADRs** covering independent native cores, the monorepo layout,
  platform floors, the desktop strategy, format and rendering libraries,
  progress storage and sync, and the design-token pipeline.
- **Desktop planning.** macOS, Windows and Linux documented with their trade-offs
  and open questions. No code, by design.
- **CI.** Three path-filtered workflows: contract (specs, token contrast, token
  sync), iOS (package tests, SwiftLint, app build), Android (lint, tests,
  assemble).

### Notes

- Nothing is installable yet. There are no releases and no signed builds.
- `material3` is pinned to a 1.5.0 alpha because `MaterialExpressiveTheme` is
  `internal` in 1.4.0. Recorded in `apps/android/README.md`; move to stable when
  it ships.
- ADR-0005 is **proposed**, not accepted. Every library choice in it is labelled
  *Known* or *Assumed*, and the Assumed ones need a spike before anything is
  built on them.
