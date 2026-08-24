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
| **Format** | Archive parsing, page extraction, page decoding, PDF rendering. See [format-layer.md](format-layer.md). | `Formats` | `:core:format` |
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
5. **The format layer parses; it does not fetch.** Every reader takes a
   `RandomAccessSource` rather than a path, so nothing below the source layer
   knows whether bytes came from a file, an SMB share or an HTTP range request
   ([ADR-0008](../decisions/0008-ranged-reads-and-own-zip-reader.md)). The one
   exception is documented and deliberate: decompressing a RAR entry needs a
   local file, because it is sequential by nature.
6. **A dependency is the last resort in the format layer, not the first.** ZIP,
   TAR and RAR *headers* are parsed by hand; page decoding and PDF are the
   platform's; libarchive exists for one function. The test of whether a
   dependency is warranted is whether the platform or a documented file layout
   can do it instead.

## Where the hard problems are

| Problem | Why it is hard | Where it is decided |
| --- | --- | --- |
| **Format support** | **Largely settled.** CBR needed a RAR decoder with an OSI-approved licence, which narrowed to libarchive. CB7 is refused by name. The surprise was that most of the work needed no library at all: only RAR *decompression* does. | [ADR-0005](../decisions/0005-format-and-rendering-libraries.md), [VENDORING.md](../../third_party/libarchive/VENDORING.md) |
| **Vendored C in two build systems** | One copy of libarchive is compiled by SwiftPM and by CMake. Two copies would drift; two decoders would drift worse. | [VENDORING.md](../../third_party/libarchive/VENDORING.md) |
| **Untrusted archive parsing** | Four hand-written parsers read attacker-supplied bytes, and libarchive reads them in C. Every length in every header is a lie until checked. | [SECURITY.md](../../SECURITY.md) |
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
