# StoryArc for Android

Native Jetpack Compose reader for comics, manga and ebooks. Android 12 (API 31)
and later.

## Layout

```
apps/android/
├── settings.gradle.kts
├── gradle/libs.versions.toml    single source of dependency versions
├── app/                         application module: manifest, activity, launch theme
├── core/
│   ├── designsystem/            theme, palette, typography, the cover-grid rule,
│   │                            the coverless well + generated tokens
│   └── model/                   domain: sources, identity, progress, preferences
└── feature/
    └── library/                 library screen, source presentation, strings
```

## Modules

| Module | Contains | Depends on |
| --- | --- | --- |
| `:core:model` | `Source`, `PublicationIdentity`, `ReadingProgress`, `ProgressMerge`, reader preferences. **No Compose.** | — |
| `:core:designsystem` | `StoryArcTheme`, `StoryArcPalette`, typography, `tokens/StoryArcTokens.kt`, `grid/` — `rememberCoverColumns`, `coverMinimumWidth`, `coverMaximumWidth`, `COVER_MAXIMUM_WIDTH`, `steppedForFontScale`, `BoundedAdaptive`, `cover/` — `CoverlessWell` | Compose, Material 3 |
| `:core:format` | Reading the bytes: `ComicArchive`, `AudiobookFolder`, `ByteReader`, the ZIP/TAR/RAR readers and the indexer. No Compose | `:core:model` |
| `:core:persistence` | Every store on disk — settings, reader preferences, sources, downloads, progress, annotations, bookmarks, certificate pins | `:core:model` |
| `:core:catalogue` | OPDS: `OpdsClient`, `OpdsAtom`, `CatalogueAcquisition` | `:core:model` |
| `:core:kavita` | A Kavita server: `KavitaClient`, `KavitaAddress`, `KavitaExchange` | `:core:catalogue`, `:core:model` |
| `:core:smb` | A network share: `SmbClient`, `SmbAddress`, `SmbDiscovery` | `:core:format` |
| `:core:playback` | The audiobook player — `PlaybackService`, `PlaybackCentre`, `AudiobookSource`, `PlaybackTimeline`, `SleepTimer`, `SkipIntervals` | `:core:model` |
| `:feature:library` | `LibraryScreen`, home, search, shelves, publication page, the selection's contextual bar, empty states | `:core:catalogue`, `:core:designsystem`, `:core:format`, `:core:kavita`, `:core:model`, `:core:persistence`, `:core:smb` |
| `:feature:reader` | The comic and PDF reader: paging, the thumbnail strip, adjustments, reader chrome | `:core:designsystem`, `:core:format`, `:core:model`, `:core:persistence` |
| `:feature:epubreader` | The EPUB reader on Readium: theme sheet, annotations, bookmarks, read-aloud | `:core:designsystem`, `:core:model`, `:core:persistence`, `:core:playback` |
| `:feature:settings` | Settings and its groups — appearance, reading, privacy, about, sources, the app-icon chooser | `:core:designsystem`, `:core:model`, `:core:persistence` |
| `:app` | `MainActivity`, `StoryArcApplication`, the shell and its navigation, the player screen, manifest, launch theme | all of the above |

> **This table listed four modules of twelve until 2026-09-03**, which is a §7 breach that no
> gate catches: `pnpm lint:android` compiles the modules and says nothing about whether a
> document mentions them. Eight were missing, including every one added after the first three —
> `:core:playback` had shipped a whole audiobook player without appearing here. The dependency
> column is read from each module's own `build.gradle.kts` rather than remembered.

`:core:model` has no Compose dependency so the domain is testable as plain JVM
code. Presentation for a domain type — an icon for a source kind, a colour for a
connection state — lives in the feature that shows it.

**`grid/` is in the design system because more than one module draws a shelf.**
The library shelf and the Downloads destination both lay covers out, and while
the rule was `internal` to `:feature:library` the Downloads shelf carried its own
copy of `design.md` §4's ladder. A copy drifts one clause at a time, and this one
had twice: `b2ededa4` fixed the font scale *in the copy* rather than removing the
copy, and the missing upper bound was still open — 175 dp covers on a 1067 dp
emulator against a 168 dp maximum. Those two shelves now call
`rememberCoverColumns` and state nothing themselves, and `:app`'s
`ShelvesAskOneRuleTest` names them by path and reads their call sites to keep it
that way.

**It is those two, and not every cover in the app.** Eight further surfaces still
give a cover a width of their own — three remote grids, a remote row, the
shelf-cover picker, a publication page's series shelf, the shelves lattice and
the library's list-view thumbnail. `design.md` §4 lists all eight in a table with
what each states. Home's own two runs are a third case again: they read the same
accessibility step through `:core:designsystem`, but the Keep reading card keeps
tiers of its own because it is a card, not a grid cell.

**`cover/` is there for the same structural reason, and closed a worse defect.**
`CoverlessWell` is what a cover-shaped cell draws when the publication has no
artwork: the title as stand-in, and the format beneath it on a surface that names
one. Four cells hold a `Publication` — the library shelf, the Downloads shelf,
Home's cards and a publication page's series shelf — and only the first drew
anything. The other three ended at `cover?.let { Image(…) }`, which has no else
branch, so a publication with no cover was a bare `surfaceSunken` rectangle. The
view was written inside `CoverGrid`'s private cell, so no other module could ask
for it however much it should. `:app`'s `ShelvesDrawOneWellTest` names the four by
path, checks each asks, rejects the `?.let` shape that hid the omission, and reads
the `format` argument at each call site — the one thing the four differ about, and
interchangeable to the compiler. Two of the four are also composed and asserted:
`:app`'s `DownloadsCoverlessWellTest` and `:feature:library`'s `CoverlessWellTest`,
which between them cover what the well draws, what it announces, and where its
title sits relative to the format label at `font_scale` 1.0, 1.5 and 2.0.

`:app` declares Robolectric and a Compose test rule for the first time to make the
first of those possible; before that the shelf the defect was reported on had a
source grep behind it and nothing else.

**Again, those four and not every cover.** Four further wells are deliberately
different and `cover/CoverlessWell.kt` names each with its reason: a publication
page's hero draws a book glyph and no title, because the page reads its title out
of the app bar; and `CatalogueEntryCell`, `KavitaSeriesGrid` and
`CatalogueDetailScreen` stand for an OPDS entry or a Kavita series rather than a
`Publication`, so they have no format to name.

Every module compiles with `allWarningsAsErrors`, and `:app` runs Lint with
`warningsAsErrors`.

## Toolchain

| Tool | Version | Why |
| --- | --- | --- |
| AGP | 9.3.1 | **Compiles Kotlin itself.** `org.jetbrains.kotlin.android` must not be applied; Kotlin options live in `android { kotlin { compilerOptions { } } }`. The Compose compiler is still a separate plugin. |
| Gradle | 9.7.1 | via the committed wrapper |
| JDK | 21 | AGP 9 requires 17 or later |
| `compileSdk` / `targetSdk` | 37 | Compose UI 1.12 refuses consumers below 37 |
| `minSdk` | 31 | dynamic colour — see [ADR-0003](../../docs/decisions/0003-platform-floors.md) |

### Known risk: Material 3 Expressive is on an alpha

`MaterialExpressiveTheme` and `MotionScheme` are still `internal` in material3
**1.4.0**, so `libs.versions.toml` pins **1.5.0-alpha26** to reach them. This is
a deliberate trade — the Expressive design language is a product requirement —
and it is the one dependency in the project that is not stable. Move to 1.5.0
stable as soon as it ships.

## Build and run

```bash
cd apps/android
./gradlew assembleDebug
./gradlew installDebug
```

`local.properties` (gitignored) must point at an SDK:

```properties
sdk.dir=/opt/homebrew/share/android-commandlinetools
```

## Validate

```bash
cd apps/android
./gradlew :core:model:testDebugUnitTest    # fast loop — pure JVM
./gradlew lint test                        # the full gate
```

## Visual proof

A change a user can see owes a screenshot from a booted emulator. A `@Preview`
is not proof.

```bash
adb shell am start -n app.storyarc.debug/app.storyarc.MainActivity
adb shell cmd uimode night yes
adb exec-out screencap -p > shot.png
```

Capture light and dark, at default and largest font scale.

## Putting comics in front of the app

The app reads a folder the user picks. There is no path to configure: Android's
Storage Access Framework hands the app a `Uri`, and the grant is persisted so the
folder comes back after a reboot.

To try it on an emulator, put files somewhere the picker can reach and choose
that folder in the app:

```bash
adb push packages/test-fixtures/comics/. /sdcard/Download/Comics/
```

Then **Library → the folder button → Download → Comics → Use this folder**.

`getExternalFilesDir` is still scanned when no folder has been picked. That is
the app's own directory — where a file shared to StoryArc lands — not a library.

## The `:feature:epubreader` module

Reflowable EPUB, on Readium (ADR-0005). Its own module because Readium's EPUB
navigator is a `Fragment` and nothing else in this app is — keeping it here means
`:feature:reader`, which renders comics and PDFs, stays Compose all the way down,
and the heaviest dependency in the build sits behind one screen.

`EpubReaderActivity` is a `FragmentActivity` rather than a Compose destination.
The navigator needs a `FragmentManager` with a factory installed before the
fragment is created; hosting that inside Compose means fighting two lifecycles at
once for no gain. The chrome on top of it is still Compose.

Readium also requires **core library desugaring**, which it states in its AAR
metadata. That is enabled in `:app`.

## Design tokens

Colour, type, spacing and motion are generated from
[`packages/design-tokens`](../../packages/design-tokens). After changing a
token, run `pnpm tokens:sync` from the repository root and commit the
regenerated `core/designsystem/.../tokens/StoryArcTokens.kt` in the same change.
Never edit that file.

## Signing

There is no upload keystore. Release builds are unsigned; signing lands with the
first release.

## The `:core:format` module

The one part below the shell that is built. It reads CBZ, CBT, CBR, PDF and plain
image folders — see
[docs/architecture/format-layer.md](../../docs/architecture/format-layer.md) for
the shape and the reasoning.

It is also **the only module with native code**, which makes it the only one with
build requirements beyond the SDK:

- `externalNativeBuild` compiles the vendored libarchive sources from
  [`third_party/libarchive`](../../third_party/libarchive) — the same copy SwiftPM
  compiles for iOS — plus the JNI shim in `src/main/cpp/`. The CMake path is
  relative, so moving either directory breaks it.
- `ndkVersion` is **pinned**. A miscompile in vendored C surfaces as a corrupt
  comic page rather than a build error, so the toolchain is not left to AGP's
  default.
- A first build of all four ABIs takes a couple of minutes. Afterwards CMake
  caches.

```bash
./gradlew :core:format:testDebugUnitTest        # JVM: parsers, ordering, arithmetic
./gradlew :core:format:connectedDebugAndroidTest # needs a device or emulator
```

The instrumented suite is not optional coverage. `ImageDecoder`, `Bitmap` and
`PdfRenderer` are framework stubs off-device, and the RAR decoder is a JNI library
that does not exist on a host JVM at all — `RarDecoder.isAvailable` is `false`
there, which is why the JVM suite exercises the header reader instead. CI runs the
instrumented job on `main` only, because booting an emulator costs minutes.

## Not yet implemented

The reader, the source connectors and persistence. The capability specs in
[`docs/openspec/specs`](../../docs/openspec/specs) are the contract. EPUB is
specified and waiting on the reflowable reader.
