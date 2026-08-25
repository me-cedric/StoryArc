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
│   ├── designsystem/            theme, palette, typography + generated tokens
│   └── model/                   domain: sources, identity, progress, preferences
└── feature/
    └── library/                 library screen, source presentation, strings
```

## Modules

| Module | Contains | Depends on |
| --- | --- | --- |
| `:core:model` | `Source`, `PublicationIdentity`, `ReadingProgress`, `ProgressMerge`, reader preferences. **No Compose.** | — |
| `:core:designsystem` | `StoryArcTheme`, `StoryArcPalette`, typography, `tokens/StoryArcTokens.kt` | Compose, Material 3 |
| `:feature:library` | `LibraryScreen`, empty state, source presentation, localised strings | `:core:designsystem`, `:core:model` |
| `:app` | `MainActivity`, `StoryArcApplication`, manifest, launch theme | all of the above |

`:core:model` has no Compose dependency so the domain is testable as plain JVM
code. Presentation for a domain type — an icon for a source kind, a colour for a
connection state — lives in the feature that shows it.

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
