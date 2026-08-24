# Architecture

## The shape in one picture

```
                    docs/openspec/specs/          ← the contract
                    15 capability specs
                              │
                 ┌────────────┴────────────┐
                 │                         │
          apps/ios (Swift)         apps/android (Kotlin)
          ─────────────────         ────────────────────
          LibraryFeature            :feature:library
          DesignSystem              :core:designsystem
          StoryArcCore              :core:model
                 │                         │
                 └────────────┬────────────┘
                              │
              packages/design-tokens (OKLCH → Swift + Kotlin)
              packages/test-fixtures (one corpus, two suites)
```

Nothing crosses between the two columns at runtime. They share a specification,
a palette and a set of test files — three declarative artefacts, no code.
([ADR-0001](../decisions/0001-independent-native-cores.md))

## Layer model

Both apps follow the same layering, in their own idiom. The names differ; the
boundaries do not.

| Layer | Responsibility | iOS | Android |
| --- | --- | --- | --- |
| **Domain** | Publications, sources, identity, progress, preferences. No UI, no I/O. | `StoryArcCore` | `:core:model` |
| **Design system** | Tokens, palette, type roles, theme. | `DesignSystem` | `:core:designsystem` |
| **Format** | Archive and ebook parsing, page extraction, metadata. *Not yet built.* | `Formats` (planned) | `:core:format` (planned) |
| **Source** | Local folder, SMB, OPDS, Kavita connectors. *Not yet built.* | `Sources` (planned) | `:core:source` (planned) |
| **Persistence** | Progress store, catalogue cache, downloads. *Not yet built.* | SwiftData | Room |
| **Feature** | One module per screen area. | `LibraryFeature`, … | `:feature:library`, … |
| **App** | Entry point, navigation host, DI root. | `App/` | `:app` |

### Rules that hold on both sides

1. **The domain layer imports no UI framework.** `StoryArcCore` has no SwiftUI;
   `:core:model` has no Compose. This is what lets the domain — including the
   progress merge, the riskiest logic in the app — be tested on the host in
   milliseconds with no simulator or emulator.
2. **Presentation of a domain type lives with the feature that shows it.** The
   SF Symbol for a source kind and the colour for a connection state are not
   properties of the domain. They live in `LibraryFeature` /
   `:feature:library`.
3. **A feature module never depends on another feature module.** Cross-feature
   navigation goes through the app layer.
4. **Generated tokens are never hand-edited.** `pnpm tokens:sync` is the only
   writer.

## Where the hard problems are

| Problem | Why it is hard | Where it is decided |
| --- | --- | --- |
| **Format support** | CBR needs a RAR decoder whose licence is not a standard OSI licence, and CB7 may not have a symmetric answer on both platforms. | [ADR-0005](../decisions/0005-format-and-rendering-libraries.md) |
| **Progress identity** | The same book arrives from three sources under three names. Path-keyed progress treats them as three books. | [ADR-0006](../decisions/0006-progress-storage-and-sync.md) |
| **Sync conflicts** | Two devices read offline and both come back with a position. The resolution rule must be predictable without documentation. | [ADR-0006](../decisions/0006-progress-storage-and-sync.md) |
| **Streaming over SMB** | Rendering page 1 of a 400 MB archive without transferring 400 MB, across a link that drops. | [`network-share`](../openspec/specs/network-share/spec.md) |
| **The page curl** | A finger-tracked, interruptible page deformation at 120 Hz. The reader's signature interaction. | [`comic-reader`](../openspec/specs/comic-reader/spec.md), [DESIGN.md §6](../design/DESIGN.md) |
| **Two implementations drifting** | Nothing at compile time stops iOS and Android diverging. | The spec contract, plus [`packages/test-fixtures`](../../packages/test-fixtures) |

## Build independence

There is no root build. `apps/ios` builds with `xcodebuild`; `apps/android`
builds with `./gradlew`. Neither knows the other exists, and **neither needs
Node** — the token pipeline runs only when a token changes.
([ADR-0002](../decisions/0002-monorepo-layout.md))

CI runs three independent workflows, path-filtered so a change to one app does
not run the other's gate. The contract workflow runs on everything.
