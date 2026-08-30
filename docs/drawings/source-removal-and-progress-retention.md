# Source removal and the 30-day progress retention

Companion to
[`source-removal-and-progress-retention.mmd`](source-removal-and-progress-retention.mmd).

What removing a source takes with it, what it deliberately leaves behind, and
when the leftovers are collected. Board for the `source-lifecycle` change,
requirement 1 (Source registry), scenario "Removing a source".

## Read from

| File | Symbols |
| --- | --- |
| `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/SourceRegistry.kt` | `removing`, `readding`, `discarding`, `collectingExpiredTombstones`, `SourceTombstone` |
| `apps/android/feature/library/src/main/kotlin/app/storyarc/feature/library/SourceRemoval.kt` | `SourceRemoval.of` |

Both paths and all five `SourceRegistry` symbols were re-checked against the tree
at the time of writing.

## Why the retention is the hard part

The proposal calls it that, and it is: removal must not cascade to the progress
store, so progress rows outlive the source they belong to and something else has
to decide when they may go. Losing a reading position is the one thing ADR-0006
says the app must never do by accident. That is the single labelled edge in the
diagram — the one place where an arrow means *this deliberately does not
happen*.

Thirty days is `SourceTombstone.RETENTION_MILLIS`, and the constant carries its
own reason: long enough that a reader who removed a server by mistake and
noticed a week later loses nothing.

## Why the secret goes first, and unconditionally

The folder lookup used to gate the whole method, so removing a server or a share
did nothing at all — and left its password in the secure store with nothing left
in the app that would ever look it up.

It is deleted *by the stored reference*, never by one re-derived from
`source.id`: a source whose id and reference disagree would otherwise keep its
key for ever.

`SourceRemoval.of(source, folders)` reaches no screen and no keystore, which is
what lets the order above be asserted in a plain unit test.

## Why the clock is a separate step

Deciding that the 30 days are up is a different question from deciding a source
is gone, and the caller that deletes reading positions should be the one that
asks. `collectingExpiredTombstones(now)` returns the expired ids rather than
acting on them — so the test advances a clock instead of waiting.

## The other exit, which the diagram does not draw

`SourceRegistry.discarding(id)` drops a source and leaves no tombstone. It is
for a row that should never have existed — one the app added on the reader's
behalf — rather than for a removal the reader asked for. A tombstone there would
hold 30 days of retention open for nothing.

It is left out of the picture on purpose: it is not part of the path a reader
walks, and drawing it would imply a choice at the point where there is none.
