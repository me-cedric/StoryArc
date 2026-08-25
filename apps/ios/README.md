# StoryArc for iOS

Native SwiftUI reader for comics, manga and ebooks. iOS 26 and later.

## Layout

```
apps/ios/
├── project.yml                  XcodeGen spec — the Xcode project is generated, not committed
├── App/                         app target: entry point, appearance wiring, assets
│   ├── StoryArcApp.swift
│   └── Resources/Assets.xcassets
└── Packages/StoryArcKit/        one package, one dependency graph
    ├── Package.swift
    ├── Sources/
    │   ├── DesignSystem/        palette, theme, type roles + generated tokens
    │   ├── StoryArcCore/        domain: sources, identity, progress, preferences
    │   └── LibraryFeature/      the library screen and its localised strings
    └── Tests/
```

`StoryArc.xcodeproj` is **generated and gitignored**. Never edit it by hand —
change `project.yml` and regenerate.

## Modules

| Target | Contains | Depends on |
| --- | --- | --- |
| `DesignSystem` | `Palette`, `Theme`, `TextRole`, `AppearanceMode`, and `Generated/StoryArcTokens.swift` | — |
| `StoryArcCore` | `Source`, `PublicationIdentity`, `ReadingProgress`, `ProgressMerge`, reader preferences. **UI-free.** | — |
| `LibraryFeature` | `LibraryView`, the empty state, source presentation, `Localizable.xcstrings` | `DesignSystem`, `StoryArcCore` |

`StoryArcCore` stays free of SwiftUI so the domain is testable on the host with
no simulator. Presentation for a domain type — an SF Symbol for a source kind, a
colour for a connection state — lives in the feature that shows it.

Every target compiles under Swift 6 language mode with strict concurrency and
the `ExistentialAny` and `InternalImportsByDefault` upcoming features. That last
one is why public API exposing a Foundation or SwiftUI type needs
`public import`.

## Build and run

```bash
brew install xcodegen swiftlint            # once
cd apps/ios && xcodegen generate           # after any project.yml change
open StoryArc.xcodeproj
```

## Validate

```bash
# Fast loop: pure-Swift targets on the host, no simulator needed.
cd apps/ios/Packages/StoryArcKit && swift test

# Full app build against the simulator SDK.
cd apps/ios && xcodebuild build \
  -project StoryArc.xcodeproj -scheme StoryArc \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Visual proof

A change a user can see owes a screenshot from a booted simulator. A `#Preview`
is not proof — it exercises neither real data, real insets, nor real system
materials.

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted "$(find ~/Library/Developer/Xcode/DerivedData -name StoryArc.app -path '*Debug-iphonesimulator*' | head -1)"
xcrun simctl launch booted app.storyarc.StoryArc
xcrun simctl ui booted appearance dark
xcrun simctl io booted screenshot shot.png
```

Capture light and dark, at default and largest Dynamic Type.

## Putting comics in front of the app

Two ways in, and the app needs neither configured before it runs:

- **Pick a folder.** The document picker returns a security-scoped URL, and the
  bookmark behind it is what makes the folder readable again after a restart.
- **Drop files into the app's own folder.** `UIFileSharingEnabled` and
  `LSSupportsOpeningDocumentsInPlace` put StoryArc in the Files app, and the
  library scans its Documents directory when no folder has been picked. Android
  scans `getExternalFilesDir` for the same reason.

On a simulator the second is the quicker one:

```bash
cp packages/test-fixtures/comics/*.cbz "$(xcrun simctl get_app_container booted app.storyarc.StoryArc data)/Documents/"
```

## Two packages, and why

`Packages/StoryArcKit` holds everything: the domain, the format layer, the design
system, the library and the comic reader. It builds for iOS **and macOS**, so its
pure-Swift targets can be tested on the host without a simulator — that is what
makes 252 tests run in a fraction of a second.

`Packages/StoryArcEpub` holds one thing: reflowable EPUB rendering, on Readium.
It exists only because Readium declares iOS support alone, and SwiftPM validates a
dependency graph for **every** platform the depending package claims. Adding
Readium to `StoryArcKit` fails macOS resolution outright, and conditioning the
target dependency does not help — the validation happens before the condition
does.

So the rule is: if it can be tested on the host, it belongs in `StoryArcKit`.

```bash
pnpm test:ios        # StoryArcKit, on the host
pnpm test:ios:epub   # StoryArcEpub, on a simulator — Readium needs one
pnpm lint:ios        # SwiftLint, from the repository root where the config is
```

`pnpm check` runs everything that needs no simulator. `test:ios:epub` and
`build:ios` are left out of it deliberately — both want a simulator runtime, and
a gate that is slow to run is a gate that stops being run.

## Design tokens

Colour, type, spacing and motion are generated from
[`packages/design-tokens`](../../packages/design-tokens). After changing a
token, run `pnpm tokens:sync` from the repository root and commit the
regenerated `Sources/DesignSystem/Generated/StoryArcTokens.swift` in the same
change. Never edit that file.

## Signing

There is no Apple Developer team configured. `CODE_SIGNING_ALLOWED` is `NO`, so
the project builds for the simulator out of the box and device builds need a
team set locally. Signing and notarisation land with the first release.

## The `Formats` target

The one part below the shell that is built. It reads CBZ, CBT, CBR, PDF and plain
image folders, and it is where the vendored libarchive lives — see
[docs/architecture/format-layer.md](../../docs/architecture/format-layer.md) for
the shape and the reasoning.

Two things about it are unusual enough to note here:

- It depends on a **local path package** at
  [`third_party/libarchive`](../../third_party/libarchive), declared in
  `Package.swift` as `.package(path: "../../../../third_party/libarchive")`. That
  is because SwiftPM will not compile C sources living outside the package that
  declares them, and those sources are shared with the Android build rather than
  copied. Moving either directory breaks the relative path.
- `swift test` runs the whole suite on the **macOS host**, including PDF and
  archive reading, because PDFKit and ImageIO are available there. Android needs
  an emulator for the equivalent. That asymmetry is in the platforms, not in the
  coverage.

```bash
cd apps/ios/Packages/StoryArcKit && swift test
```

## Not yet implemented

The reader, the source connectors and persistence. The capability specs in
[`docs/openspec/specs`](../../docs/openspec/specs) are the contract. EPUB is
specified and waiting on the reflowable reader.
