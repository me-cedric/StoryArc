---
status: accepted
---

# Architecture Decision Records

## Context and problem statement

Why StoryArc is built the way it is. Read the relevant one before proposing a
change that contradicts it — and if the reasoning no longer holds, write a new
ADR that supersedes it rather than quietly doing something else.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-independent-native-cores.md) | Two independent native cores, not a shared one | Accepted |
| [0002](0002-monorepo-layout.md) | One repository for two independent apps | Accepted |
| [0003](0003-platform-floors.md) | iOS 26 and Android 12 as the minimum versions | Accepted |
| [0004](0004-desktop-strategy.md) | Desktop: documented now, built later | Accepted — planning only |
| [0005](0005-format-and-rendering-libraries.md) | Format and rendering libraries per platform | **Proposed** — needs a spike |
| [0006](0006-progress-storage-and-sync.md) | Local-first progress with content-addressed identity | Accepted |
| [0007](0007-design-token-pipeline.md) | One OKLCH token source, generated into Swift and Kotlin | Accepted |
| [0008](0008-ranged-reads-and-own-zip-reader.md) | Ranged reads over a random-access source, with our own ZIP reader | Accepted |
| [0009](0009-page-curl-as-a-fragment-shader.md) | The page curl is a fragment shader over two decoded pages | Accepted |
| [0010](0010-smb-clients.md) | An SMB2 client per platform, both pure and permissively licensed | Accepted |
| [0011](0011-home-screen-widgets.md) | Home-screen widgets wait for a shared snapshot, and for a signing team | Accepted — deferral |
| [0012](0012-pdf-text-on-android.md) | PDF text on Android comes from the platform's own PDF module | Accepted |
| [0013](0013-cb7-support.md) | CB7: what a 7-Zip decoder would cost, and three ways to answer it | **Proposed** — open, awaiting a decision |
| [0014](0014-unpatchable-zip-in-the-readium-graph.md) | An unpatchable ZIP library ships in the iOS binary, and nothing calls it | **Proposed** — open, awaiting a decision |
| [0015](0015-epub-webview-network-egress.md) | A publication's own network access: deny it, admit it, or narrow it | **Proposed** — open, awaiting a decision |
| [0016](0016-ios-smb-response-signing.md) | iOS SMB responses are unsigned and unverified — extends 0010 | **Proposed** — open, awaiting a decision |
| [0017](0017-android-text-to-speech.md) | Android reads aloud with the platform engine, not a new Readium artifact | Accepted |

## Considered options

Not recorded: this file is the index of the folder, so no alternative to the
conventions below was ever written down. Needed if the index is ever promoted to
a decision of its own.

## Decision Outcome

Not recorded: the conventions this folder follows are stated in the sections
below — reading order, supersede in part, confidence labels, and how to write a
new one. Needed if the index is ever promoted to a decision of its own.

## Reading order

New to the project? **0001 → 0002 → 0003.** Those three explain the shape of the
repository. The rest answer specific questions when you reach them.

## When an ADR is superseded in part

[ADR-0008](0008-ranged-reads-and-own-zip-reader.md) supersedes only the ZIP rows
of [ADR-0005](0005-format-and-rendering-libraries.md), one day after they were
written. Both records stay: 0005 explains what was chosen and why it was
reasonable, 0008 explains what changed the answer. Deleting the first would hide
the reasoning, and the reasoning is the part worth keeping.

## Confidence labels

ADR-0005 tags every library choice *Known* or *Assumed*. **Assumed means it has
not been proven in a spike** — a reasonable pick, not a verified one. Treat an
Assumed row as an open question, not a decision, and do not build on it without
checking it first.

## Writing a new one

Copy [`000-template.md`](000-template.md) and number sequentially. Keep its YAML
frontmatter: `status` must be one of *proposed, accepted, rejected, deprecated,
superseded*, because the Decisions page reads that word and shows it as a badge.
Any qualifier — "planning only", "needs a spike" — goes in the body.

Cover context, the decision, alternatives with *why not*, and consequences —
including the costs you are accepting, not only the benefits. An ADR that lists
no downside is not an ADR, it is an advert.
