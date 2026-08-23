# Architecture Decision Records

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

## Reading order

New to the project? **0001 → 0002 → 0003.** Those three explain the shape of the
repository. The rest answer specific questions when you reach them.

## Confidence labels

ADR-0005 tags every library choice *Known* or *Assumed*. **Assumed means it has
not been proven in a spike** — a reasonable pick, not a verified one. Treat an
Assumed row as an open question, not a decision, and do not build on it without
checking it first.

## Writing a new one

Number sequentially. Cover context, the decision, alternatives with *why not*,
and consequences — including the costs you are accepting, not only the benefits.
An ADR that lists no downside is not an ADR, it is an advert.
