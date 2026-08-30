# Two apps, one written contract

Companion to
[`two-apps-one-written-contract.mmd`](two-apps-one-written-contract.mmd).

## Why this one exists

[ADR-0001] is the project's founding decision and no picture of it existed. It is
also the decision that explains the most confusing thing about the repository to
a newcomer: why the same logic is written twice on purpose, and why "just extract
a shared module" is not an oversight waiting to be corrected.

## Read from

| File | What it settled |
| --- | --- |
| `docs/decisions/0001-independent-native-cores.md` | the decision, the three shared artefacts, and the enforcement column |
| `AGENTS.md` | the non-negotiables, and the reflowable-EPUB exception |
| `docs/openspec/STATUS.md` | the counts: 17 capabilities, 315 scenarios |

Counts were re-checked: `docs/openspec/specs/` holds 17 directories, and
`STATUS.md` states 315 scenarios. Note that `AGENTS.md` still says "15 capability
specs" in its own table — it is stale, and it is not a file this board owns.

## What the picture is claiming

**The three shared artefacts are all declarative.** Not one of them is code that
either app links. A spec is prose with scenarios, a token set is generated into
each language separately, and a fixture corpus is data plus a manifest of
expected parses. Nothing crosses the middle that a compiler ever sees.

**The fixture corpus is the honesty mechanism.** Two independent implementations
have nothing at compile time to catch them privately disagreeing about what a
correct parse is. Both suites reading `packages/test-fixtures/manifest.json` and
asserting the *same* recorded expectations is the entire substitute — the same
malformed CBZ, the same RTL manga, the same EPUB with a broken spine.

**The one exception is real and narrow.** Reflowable EPUB content is HTML by
definition, so it is the single place a web view is permitted. Every other pixel
is SwiftUI or Compose.

## Why it was decided this way

Kotlin Multiplatform was the strongest alternative and was rejected on three
grounds, not because it is wrong:

1. **The expensive parts are not shareable anyway.** EPUB rendering, PDF
   rendering and image decoding are the hardest, highest-risk parts of the app,
   and each is best solved by a mature platform library — Readium Swift and
   Readium Kotlin are separate implementations, PDFKit and pdfium are separate.
   A shared core would mostly be `expect`/`actual` wrapping platform code, which
   is indirection rather than reuse.
2. **It puts Gradle in the Xcode build.** Every iOS build would depend on a
   Gradle task producing an XCFramework — a permanent tax on the iOS loop, paid
   on day one for a benefit that arrives later.
3. **It is a solo project.** The bottleneck is one person's attention, not
   duplicated keystrokes.

The ADR names its own revisit condition: a second developer joining, or connector
logic drifting between the platforms. Flutter and React Native fail the primary
product requirement outright — the reader has to run a finger-tracked page curl
at the display refresh rate.

## What the picture leaves out

The asymmetries. Two independent implementations are *allowed* to differ where
the platforms differ, and about a dozen such differences are specified rather
than accidental — a PDF outline is iOS-only, Android reaches user folders
through a `Uri` where iOS has a URL, folder permission is stored on iOS and not
on Android. They are tabulated at the end of
[`docs/architecture/format-layer.md`](../architecture/format-layer.md), and
drawing them here would imply they are exceptions to the contract when they are
consequences of it.

[ADR-0001]: ../decisions/0001-independent-native-cores.md
