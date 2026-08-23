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

## Design tokens

Colour, type, spacing and motion are generated from
[`packages/design-tokens`](../../packages/design-tokens). After changing a
token, run `pnpm tokens:sync` from the repository root and commit the
regenerated `core/designsystem/.../tokens/StoryArcTokens.kt` in the same change.
Never edit that file.

## Signing

There is no upload keystore. Release builds are unsigned; signing lands with the
first release.

## Not yet implemented

Everything below the shell. The capability specs in
[`openspec/specs`](../../openspec/specs) are the contract; the reader, the source
connectors, the format layer and persistence are all still to be built.
