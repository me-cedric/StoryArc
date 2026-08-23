# Changelog

All notable changes to StoryArc are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The two apps version and release independently — `ios-vX.Y.Z` and
`android-vX.Y.Z` — so entries name the platform they affect.

## [Unreleased]

### Added

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
