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

## Not yet implemented

Everything below the shell. The capability specs in
[`docs/openspec/specs`](../../docs/openspec/specs) are the contract; the reader, the
source connectors, the format layer and persistence are all still to be built.
