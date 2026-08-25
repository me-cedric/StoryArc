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
- **The theme sheet is a popover on a tablet and a sheet on a phone**, with the page
  still readable beside it. One declaration rather than two layouts: iOS adapts a
  popover back into a sheet on a phone, and Material 3's bottom sheet already caps
  and centres itself at tablet width.
- **One opt-in that ties the reading theme to the app's appearance**, off by default —
  because a dark app with a paper-white page is a legitimate preference, and the spec says
  so. Light maps to Paper, every dark appearance to Quiet.
  - OLED Dark maps to Quiet too, not to something darker: the difference between Dark and
    OLED Dark is the *chrome*'s black point, and a reading surface is never pure black
    anyway.
  - Your per-series theme is not overwritten, so turning the setting off brings it back.
- **A colour behind a comic page**, chosen in Settings and applied to the area *around*
  the page only — the artwork is never tinted, because tinting someone else's drawing is
  not a reading preference.
  - A preset deliberately does not reach it. A comic has no typography for a preset to
    change, so all a preset could offer is its paper colour, and that is not what a preset
    means.
  - Swatches here rather than the reader's full picker: the picker's sliders and its
    contrast refusal need the page visible behind them to be worth anything.
- **Settings search**, matching the *setting* rather than the group: "volume" finds
  "Volume buttons turn pages" and tells you it lives under Reading, and "night" finds
  Appearance. You search for the thing you want, not for what the screen calls it.
- **Reset settings**, and the confirmation names what survives rather than only asking
  whether you are sure. Sources, downloads, reading progress — and the themes you chose
  while reading, which the spec does not list but which are equally not settings. Verified
  by reading both stores across a reset.
- **Reading defaults for series you have not opened**, with books and comics kept
  separate — wanting cream paper for novels does not mean wanting it behind a comic.
  Changing a default cannot touch a series you have already chosen for; the two live in
  different places, so one cannot reach the other.
- **The volume buttons turn pages on Android**, off by default and explained where it
  sits — volume keys that silently stop changing the volume are a defect, not a feature.
  - It cannot be done on iOS within the rules: the system owns those buttons, and the only
    way round it is a trick App Review has rejected and that breaks whenever anything else
    plays audio. The setting says so instead of offering a switch that does nothing.
- **Settings exists.** Seven groups in the order the spec names them, each row stating
  its current value so a setting can be checked without opening it. Reachable from the
  library even when the library is empty — a reader with no books still needs About.
  - Appearance applies **immediately**, while you are still looking at the picker. The
    first attempt handed the choice back on the way out, which satisfies "without a
    restart" and misses the point.
  - Three groups cannot be entered yet and say what they will hold rather than opening
    onto a blank screen. Hiding them would leave you hunting for where sources live.
  - The system back gesture goes up one level inside Settings rather than out of it.
- **Acknowledgements, with every licence in full** — which is what the five bundled fonts
  legally require and what nothing did until now.
  - It needed a source of truth first: `third_party/libarchive/VENDORING.md` pointed at a
    `THIRD_PARTY_NOTICES.md` that did not exist. It does now, generated from
    `packages/licences/notices.json`, which also records *why* each dependency is in the
    app — a dependency whose reason nobody can state is one to remove.
  - One copy on disk read by both apps, the same arrangement as the fonts and the vendored
    libarchive. It ships inside the app rather than only in the repository, because BSD
    and Apache require the notice to travel with the binary.
  - The list is filtered by platform. Telling an Android reader the app depends on the
    Readium *Swift* toolkit would be worse than telling them nothing.
- **About**: version read from the bundle, the author, the repository, the licence, the
  statement that it is free with no paid tier and no advertising, one optional Ko-fi link
  that appears nowhere else, and a problem report that pre-fills the version and device
  *class* and nothing personal.
- **A privacy screen with nothing to switch off**, which is the point: no account, no
  backend, no analytics, no crash reporting. A screen of disabled toggles would imply
  otherwise.
- **OLED Dark**, as a fourth appearance beside System, Light and Dark. Chrome goes
  true black; the *page* deliberately does not, because pure black smears on OLED
  during a page turn — which is the exact motion this app is built around. The setting
  says so rather than quietly doing something other than its name.
  - Natural is not one of these. It is a theme with its own light and dark variants, so
    making it an appearance would force a choice between Natural and dark mode.
  - Dynamic colour and true black turned out to be incompatible asks: Material You
    derives its surfaces from the wallpaper, and a wallpaper-tinted "true black" is
    neither. The explicit choice wins.
- **Fixed: the typeface specimens shrank the face at large text sizes.** A specimen is a
  picture of a typeface in a fixed-size card, so scaling it with the system text size
  showed *less* of the face the larger a reader needs it. It no longer scales.
- **Fixed: the preset grid clipped its labels at twice the system text size.** It was a
  lazy grid inside a scrolling column, which needs a fixed height. Six known items never
  needed one — rows take the height their content asks for.
- **Continuous scrolling for ebooks.** Readium had the preference and nothing was
  wired to it. The theme sheet now offers Pages or Continuous scroll, and lists Curl and
  Fast fade with the reason they cannot run over text that reflows — they animate a
  picture of a page, and a reflowable page is live web content.
  - Scroll here is Readium's own preference, not a scroll view of ours. Two containers
    over one web view would fight for the same gesture.
- **Fixed: "0% read" for a whole chapter in scroll mode.** Readium reports a total
  progression of `0.0` rather than nothing while scrolling, so the fallback that keys on
  *absence* never fired — and that zero was what got stored. A reported zero the position
  contradicts is no longer treated as a report.
- **The page curl, on iOS too** — the same fold, expressed as a stitchable Metal
  fragment shader rather than the vertex shader and mesh the plan called for. SwiftUI's
  shaders sample textures as arguments, so the whole fold is one function over the two
  pages, and a fold contributes no geometry that a per-pixel projection cannot express.
  Built and compiling; not yet verified visually, because the simulator accepts no
  injected input.
  - Building the iOS app now needs the Metal toolchain, which is not part of a default
    Xcode install: `xcodebuild -downloadComponent MetalToolchain`, about 690 MB. It is a
    separate download rather than something the package can declare, so it is in
    [the iOS README](apps/ios/README.md).
- **The page curl, on Android.** One AGSL shader over the two decoded pages: the
  crease follows your finger, the turned sheet shows the page's back, its leading edge
  catches light and it casts a shadow on the page beneath. Past halfway the turn
  completes, before it the page springs back, and a new drag during the settle takes
  over from where the page is instead of snapping.
  - A right-to-left publication curls from the opposite edge, mirrored — one
    coordinate flip inside the shader rather than a second shader.
  - Not a cylinder, despite the plan saying so. Seen straight down a folded page hides
    its crease entirely, so the crease is *shaded* rather than projected. A cylinder
    here would be geometry that draws nothing.
  - Gated at API 33, where `RuntimeShader` arrives. Below it Curl is simply absent and
    Slide is the default, which is the path the picker already had.
- **Choose how a page turns, and the choice sticks per series.** Slide, Fast fade,
  and continuous Scroll in either axis. Curl is not here yet, and says so.
  - **Scroll is the one that changes what you can read.** Pages are stitched with no
    gap, so a webtoon reads as the single strip it is instead of twelve screens.
    The axis follows the publication — vertical for anything materially taller than
    it is wide, horizontal otherwise — and the second scroll row is the override.
  - Curl is absent rather than dead where it cannot be drawn smoothly, with the
    reason in plain language and no API level named. Reduce Motion is the other case
    and gets the other treatment: Curl and Slide stay listed, marked, with the reason
    — a control that vanishes teaches you nothing. Either way your stored choice is
    never overwritten, so it comes back when the condition does.
  - Fast fade is 140 ms, about the shortest a dissolve can be without reading as a
    cut. It doubles as the Reduce Motion substitute, so it must not become the thing
    it replaces.
- **Fixed: the page a publication opens on only reached one of the containers.** A
  ComicInfo cover, or the position you left off at, arrives after the book opens
  rather than when the screen is first built. The pager restored itself from its own
  saved state and hid this; a fade and a scroll had nothing to restore from and
  opened at page one.
- **Every preset card and every typeface row is drawn in its own typeface.** The
  cards previewed each theme's colours with three grey rules, and a rule has no
  letterforms — so the grid showed six colours and no faces.
  - That needed the bundled faces in front of each platform's own text stack, not
    only Readium's. Without it a specimen falls back to the system font in silence,
    which is the one failure a typeface picker must not have.
  - On iOS the typeface menu became a list of rows, because SwiftUI strips a custom
    font inside a menu and a picker whose options all look alike is a list of words
    rather than a choice.
- **Fixed: Bitter shipped as Thin.** The font build narrowed the weight axis and the
  instancer kept the bottom of the range as the default, so Bitter's default instance
  was Light and its family name still read "Bitter Thin". The page was unaffected —
  CSS resolves `normal` to 400 within the declared range — but any native specimen
  would have drawn a hairline and called it Bitter.
  - The narrowing turned out not to pay for itself either: about 1% on the families
    with a wide range, and **+52 kB on Bitter**. It is gone; pinning the optical-size
    axis is the whole win. Family names are now written from the same constant the app
    asks for rather than inherited, because inheriting went wrong twice.
  - The corrected total is 4.0 MB per app, and `--check` reprints it so the table
    cannot go stale. The first version of that table was internally inconsistent.
- **The reading theme survives closing the book**, and it is remembered per series
  rather than globally. Previously every choice was lost on close.
  - A theme is stored per shelf: the series, or the book itself where it has no
    series, because a standalone book is a series of one — keying it to the global
    default would mean reading one novel in sepia changed every other book.
  - Reflowable and fixed-layout keep separate defaults. A line height means nothing
    to a page of artwork, and wanting cream paper for novels does not mean wanting it
    behind a comic.
  - Changing the global default cannot overwrite a choice already made for a series,
    and that needs no logic: the two live in different places, so one cannot reach
    the other.
  - The typography travels with the theme, not just the preset name. Storing only the
    preset would put a moved line height back on the next open.
- **A reading background of your own**, kept legible whether you like it or not.
  Eight swatches, a picker, and a text colour derived from whatever you choose.
  - The derived colour is black or white and nothing else, because contrast depends
    only on relative luminance and those are its extremes — so it is the whole
    answer, not a search that stopped early. Which has a consequence worth saying
    out loud: a mid-tone grey has *no* text colour that reaches 7:1. The sheet says
    so rather than handing back black and looking like a pass.
  - Override the text colour and a pairing below 4.5:1 is refused **with its
    measured ratio**, because "that is not allowed" without a number is an obstacle
    rather than an explanation. The ratio is shown at all times, not only when
    something goes wrong — a number that appears only to scold is one you have no
    reason to trust.
  - The maths is the same relative-luminance definition the token pipeline uses,
    down to the 0.04045 knee, and a golden-value test on both platforms pins them
    together. A drift would let a pairing clear the build gate and be refused in the
    sheet.
  - It is a seventh slot beside the six presets, not a seventh preset: choosing it
    keeps the typography you already set, and tapping one of the six leaves it
    behind. Original refuses it, because the publisher's own colours are the point.
- **The reader chrome wears each platform's own material.** Liquid Glass on iOS,
  Material 3 tonal surfaces on Android.
  - The iOS theme sheet needed no material of its own; it needed the opaque fill it
    was painting *over* the system's glass removed. An iOS 26 sheet is already
    presented on Liquid Glass and already goes opaque under Reduce Transparency.
  - The chrome the app paints itself now goes through one modifier that carries the
    glass *and* the opaque fallback with a strengthened border. Eleven call sites
    across both readers and the library used to declare no fallback at all, and a
    fallback that has to be remembered at eleven places will be missing at one.
  - Both readers' chrome sits in a `GlassEffectContainer`, so overlapping glass
    shapes morph as one instead of stacking their edges.
- **The theme sheet is usable with a screen reader**, and there is a test on a
  device that says so rather than a claim that it should be.
  - Every slider says which axis it is and what its value means — "1.5 times",
    "0.15 em". What a number means is a domain question, so the axis answers it once
    for both platforms, and a test catches an axis that forgets to.
  - The size stepper announces its position out of the total. "Larger" alone never
    says how much room is left on the ladder.
  - Two defects only a semantics dump could show: every slider was unnamed, because
    the heading beside it is a sibling node; and the typeface rows were a radio
    button next to two loose labels, so "Designed for low vision" was a node a
    reader could walk straight past.
  - The fine axes are stepped in ten rather than continuous. A drag used to submit a
    preference change per frame, and each one relays out the page.
- **Five bundled typefaces**: Literata, Source Serif 4, EB Garamond, Bitter and
  Atkinson Hyperlegible, all OFL, subset to Latin, Latin Extended, Greek and
  Cyrillic. Atkinson Hyperlegible is labelled "Designed for low vision" wherever it
  is offered — `reading-themes` is explicit that an accessibility affordance
  presented as a style option gets missed by the people who need it, so the label
  is a property of the face rather than a string a picker remembers.
  - 3.9 MB per app, against the 2–3 MB the design estimated. The estimate was
    optimistic and [the table](packages/fonts/README.md) is the number. Two
    reductions took it from 6.2 MB without changing anything a reader can see:
    subsetting to the four named scripts, and pinning the optical-size axis of the
    two families that have one — a reader never animates optical size, and dropping
    the axis halves both files.
  - One copy on disk, read by both apps, and rebuilt by a script rather than by
    hand — the same arrangement as the fixture corpus and the vendored libarchive.
- **Every typographic axis is adjustable.** Typeface, bold, line, character, word
  and paragraph spacing, margins and text alignment, plus reader-local brightness.
  The sliders are drawn from one loop rather than nine blocks of view code, because
  the domain answers a slider's three questions — its range, its value, and how to
  set it — and the two platforms therefore offer identical spans.
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

- **A typography change lost the reader's place.** Raising the text size two steps
  kept the chapter and the reported progression but moved the reader roughly
  fourteen paragraphs back inside it: Readium re-paginates to the *progression*,
  and a progression is coarser than a paragraph. Both readers now capture the
  locator before submitting preferences and return to it once the reflow settles.
  Re-measured, the top paragraph moves by one — a boundary landing differently
  rather than a place lost. `ebook-reader` asks for the position to be preserved
  "to the paragraph, not the page number", and it was not until it was made to be.

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
  `docs/design.md`.
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
