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

### Fixed

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
