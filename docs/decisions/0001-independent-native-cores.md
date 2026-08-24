---
status: accepted
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0001 — Two independent native cores, not a shared one

## Context and problem statement

StoryArc ships the same product on iOS and Android: source connectors (SMB,
OPDS, Kavita), archive and ebook parsing, a download queue, a progress store
with two-way sync, and library indexing. That is a lot of logic to write twice.

The obvious candidate for sharing it is Kotlin Multiplatform: one module for
domain, networking and persistence, with SwiftUI and Compose left fully native
on top. Nothing about KMP compromises the native feel of the *interface*.

Three things argue against it here.

1. **The expensive parts are not shareable anyway.** EPUB rendering, PDF
   rendering, and image decoding are the hardest and highest-risk parts of this
   app, and each is best solved by a mature platform library — Readium Swift and
   Readium Kotlin are separate implementations, PDFKit and pdfium are separate,
   image decoding is separate. A shared core would mostly be `expect`/`actual`
   declarations wrapping platform code, which is indirection, not reuse.
2. **It puts Gradle in the Xcode build.** Every iOS build would depend on a
   Gradle task producing an XCFramework. That is a real, permanent tax on the
   iOS development loop, paid on day one for a benefit that arrives later.
3. **This is a solo project.** The bottleneck is one person's attention, not
   duplicated keystrokes. Shipping iOS well, then Android well, beats shipping
   two half-apps behind a shared abstraction that has to satisfy both before
   either works.

## Considered options

| Option | Why not |
| --- | --- |
| **Kotlin Multiplatform shared core** | Reasonable, and the strongest alternative. Rejected for the three reasons above, not because it is wrong. Revisit if a second developer joins or if connector logic drifts between platforms. |
| **Flutter or React Native** | Fails the primary product requirement. The app must feel stock, and the reader must run a finger-tracked page curl at the display refresh rate. |
| **Swift on Android** | Immature toolchain for app-level code, and no Compose interop story. |
| **C++ or Rust core via FFI** | Solves the parsing layer, but the parsing layer is the part with good native libraries already. Buys the FFI cost without the FFI benefit. |

## Decision Outcome

**Two independent native codebases.** `apps/ios` is Swift and SwiftUI.
`apps/android` is Kotlin and Compose. Neither depends on the other or on any
shared runtime.

They share exactly three artefacts, all of them declarative:

| Shared | Where | Enforced by |
| --- | --- | --- |
| Behaviour contract | `docs/openspec/specs/` | `pnpm spec:validate` in CI |
| Design tokens | `packages/design-tokens` | Generated into both apps; contrast gate in CI |
| Test fixtures | `packages/test-fixtures` | Both test suites read the same corpus |

The fixture corpus is what keeps the two implementations honest: the same
malformed CBZ, the same RTL manga, the same EPUB with a broken spine, asserted
against the same expected parse on both platforms.

## Consequences

**Accepted costs**

- Connector logic is written twice. OPDS parsing, the Kavita client, the sync
  state machine, and the download queue each exist in two languages.
- The two apps can drift. A bug fixed in one is not fixed in the other.

**Mitigations**

- Every behaviour lives in an OpenSpec capability before it is implemented, so
  the two implementations are written against the same written contract rather
  than against each other.
- The shared fixture corpus catches divergence in parsing, which is where
  divergence would hurt most.
- A change to a capability spec obliges the author to state the status of the
  other platform in the handoff. See `AGENTS.md`.

**Benefits**

- Each app uses the best library its platform has, with no wrapper.
- The iOS build is Xcode and SPM. The Android build is Gradle. Neither knows the
  other exists.
- Either platform can be worked on, released, or paused independently.

## Revisit when

- A second developer joins and duplicated connector work becomes the bottleneck.
- The fixture corpus catches the same class of divergence three times.
- A desktop target lands that would share a core with one of the mobile apps —
  note that macOS shares with iOS through SwiftUI, not through KMP. See
  [ADR-0004](0004-desktop-strategy.md).

## Links

- Specs: the whole of [`docs/openspec/specs/`](../openspec/specs) — this ADR is
  what makes the written contract the only thing the two apps share.
- Related decisions: [ADR-0002](0002-monorepo-layout.md) puts both codebases in
  one repository. [ADR-0004](0004-desktop-strategy.md) extends the rule to
  desktop.
- Contract: `AGENTS.md` §2, non-negotiable 1 — no cross-platform UI, ever.
