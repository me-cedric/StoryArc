---
status: accepted
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0006 — Local-first reading progress with content-addressed identity

## Context and problem statement

[`reading-progress`](../openspec/specs/reading-progress/spec.md) requires that
progress survive across sources, formats and devices, sync with Kavita, and
never silently move a user backwards. Two problems underlie all of it.

**Identity.** The same publication can arrive as a file in a folder, a file on
an SMB share, and a chapter on a Kavita server. A path-keyed progress record
treats those as three different books. The user does not.

**Authority.** Two devices can read the same publication offline and both come
back with a position. Something has to decide, and the rule has to be one a user
can predict without reading documentation.

## Considered options

**Authority**

1. Remote store authoritative, local cache behind it.
   - Bad, because the app must work fully with zero sources configured, and most
     sources cannot store progress at all.
2. Local store authoritative, sync as a projection outward. **Chosen.**

**Identity**

3. Path-keyed records.
   - Bad, because the same publication read from a folder, an SMB share and
     Kavita becomes three records. The user sees one book.
   - Kept only as the last-resort key when nothing else is obtainable.
4. Content hash, with the server identifier taking precedence. **Chosen.**
   - Good, because it is stable across renames, moves and re-downloads, and
     costs two ranged reads rather than a full transfer.

**Conflict**

5. Last-write-wins.
   - Bad, because clock skew between a phone and a NAS is real, and the failure
     mode is losing an evening's reading.
6. Furthest position wins, finished is sticky. **Chosen.**
   - Good, because its failure mode — a few pages ahead — is recoverable.

**Position for reflowable content**

7. Persist the page number.
   - Bad, because a page number is a function of the reader's typography.
8. Persist a locator into the content, display a page number. **Chosen.**

## Decision Outcome

### Local is authoritative; sync is a projection

Progress is written locally first, always, for every publication — including
ones from sources that cannot store progress. Remote sync is a projection of
that store outward, never a prerequisite for it. The app works fully with zero
sources configured.

### Identity is content-addressed, with a server override

A publication's identity is, in order of preference:

1. **The server's own identifier**, when it came from a source that has one
   (a Kavita chapter id). The server is authoritative for its own content.
2. **A content hash** otherwise: a digest of the file's size plus the first and
   last 64 KB. Cheap to compute over SMB (two ranged reads, no full transfer),
   and stable across renames, moves, and re-downloads.
3. **A normalised path**, only as a last resort when neither is obtainable.

Identity 1 and identity 2 are recorded together when both are known, which is
what lets a locally-read file and the same file on Kavita resolve to one record.

### Conflict resolution: furthest position wins, finished is sticky

| Situation | Result |
| --- | --- |
| Remote ahead, local unchanged since last sync | Adopt remote, silently |
| Remote behind local | Keep local, push it |
| Both changed since last sync | Adopt the **further** position; tell the user once, naming both, offering the other |
| One finished, one partial | **Finished wins** |

Furthest-wins is chosen over last-write-wins because clock skew between a phone
and a NAS is real, and because the failure mode of furthest-wins — being a few
pages ahead of where you actually were — is trivially recoverable, while the
failure mode of last-write-wins is losing an evening's reading.

Finished is sticky because unmarking a finished publication is a deliberate act.
Losing it to a stale sync is not something a user would ever want.

### Reflowable positions are not page numbers

For reflowable EPUB, position is stored as a location within the content, not as
a page number, because a page number is a function of the reader's typography.
Both Readium toolkits expose a locator model for exactly this; a page number is
displayed but never persisted as identity.

### Storage

- **iOS:** SwiftData, with the store excluded from iCloud backup for downloads
  but included for the progress database, which is small and worth restoring.
- **Android:** Room, with the same split.

Both are per-platform choices under [ADR-0001](0001-independent-native-cores.md)
and are not shared. The *schema semantics* — identity fields, conflict fields,
sync watermark — are specified here so the two implementations agree.

**Built, and the schema is what the ADR said it should be.** The three identity
components are separate columns on both sides rather than one encoded blob,
because the lookup rule above requires finding a record by *any* of them: a
publication written against a path is found again by its digest once one is
computed, and the components fill in as they become known rather than forking into
two rows. That behaviour has a test on each platform, asserting the same thing.

Two version notes for whoever refreshes the build. Room needs KSP, and KSP's
release train briefly lagged Kotlin 2.4.10 — the combination that works here is
**Room 2.8.4 with KSP 2.3.9**, which keeps Gradle's configuration cache intact.
The earlier KSP versioning scheme (`<kotlin>-<ksp>`) no longer applies.

## What the code reaches, and what it does not

Read out of both trees on 2026-08-30. The decision above stands — the rules are
the right rules, and `ProgressMergeTests` and `ProgressMergeTest` assert the whole
table on each platform. What is recorded here is that the app cannot currently
*reach* parts of it, because an ADR that describes behaviour the code does not
have is worse than no ADR.

### The sync watermark is never written, so one row of the table is unreachable

`syncedPosition` is the field the table's *"since last sync"* is measured
against, and **no production code on either platform writes it**. Every
construction outside a test takes the default `nil`: `ReaderModel.swift:374` on
iOS, `ReaderViewModel.kt:644` and `EpubReaderViewModel.kt:705` on Android. The
stores persist whatever they were handed (`ProgressStore.swift:128`,
`ProgressStore.kt:208`), so a nil goes in and a nil comes back.

`ProgressMerge` reads that absence as "assume it moved" —
`ReadingProgress.swift:108` and `ReadingProgress.kt:104` both fall back to
`true`. `localMoved` is therefore permanently true, `remoteMoved` with it, and
the first row above — *remote ahead, local unchanged since last sync → adopt
remote, silently* — cannot be reached. That case falls through to the third row.

**What a reader sees.** A chapter read on another device, and nothing read on
this one, is handled as a disagreement rather than a hand-over: the app raises
the "Read in two places" alert and asks which position to keep. The position it
settles on is the right one — furthest wins, and the further one is the remote —
but the reader is asked to resolve a conflict that is not one, which is exactly
the interruption the silent row exists to avoid.

Writing the position down as `syncedPosition` when it is pushed or adopted is
what closes this. Nothing in the rule itself needs changing.

**And the two stores would not agree even once it is written.** iOS encodes the
whole `ReadingPosition` as JSON and decodes it back (`ProgressStore.swift:128`
and `:304`). Android keeps only its fraction, in a single `syncedProgression`
column, and rebuilds it as `ReadingPosition.Reflowable(fraction, "")`
(`ProgressStore.kt:208` and `:320`). The merge compares positions by value, so on
Android a restored watermark would not equal the page position it was made from,
nor a reflowable one whose locator it dropped — `localMoved` would stay true
there after the write that fixes iOS. The column has to carry the position, not a
number derived from it.

### A pull that finds the server behind pushes nothing

`ProgressPull` sorts a merge into three piles, and the `toPush` pile —
`ProgressPull.swift:14`, `ProgressPull.kt:20` — is **discarded by both of its
callers**. `KavitaSync.swift:65-66` and `KavitaSync.kt:77-78` consume `toSave`
and `conflicts` and nothing else. A pull that establishes the server is behind
saves the local record it already had and tells the server nothing.

Positions do still reach Kavita by the ordinary route: the reader reports one on
leaving (`KavitaSync.report`, from `StoryArcAppActions.swift:70` and
`MainActivity.kt:1093`), and held ones are flushed when the server is reachable
again. What is missing is the second row of the table — *remote behind local →
keep local, push it* — at the one moment the app has just proved it applies.

### Identity nearly always falls to the last resort

**Rule 1, the server identifier, is never constructed in production.** The only
`ServerIdentifier` built outside a test is the one each store decodes back out of
a stored key (`ProgressStore.swift:297`, `ProgressStore.kt:296`), and nothing
writes that key non-nil, because nothing hands a store an identity carrying one.

**Rule 2, the content digest, has one production caller in the repository.**
`OpenedFile.kt:69`, where Android digests a file handed to it from outside the
app. On iOS, `PublicationIndexer.contentDigest` (`PublicationIndexer.swift:384`)
is called only by its own test. Both library scanners key on the path instead —
`PublicationIndexer.swift:372`, `LibraryScanner.kt:384`,
`PublicationIndexer.kt:409`.

So anything the library scanned is identified by rule 3, the normalised path,
which this ADR calls a last resort. Two of the consequences claimed below — that
a position survives a rename or a move, and that one file read from a folder and
from a share resolves to one record — do not hold at runtime for those
publications. The lookup that would honour a digest is written and tested
(`ProgressStore.swift:264`, `ProgressStore.kt:285`); it is the digest that is not
supplied.

One promised outcome does hold, by a route this ADR does not describe: a Kavita
chapter finds its local progress record because `KavitaProgressStore` keeps its
own chapter-id → publication-id table (`remember(_:for:)`), which `KavitaSync.pull`
reads. That is a side mapping beside the identity, not identity rule 1, and it
covers Kavita only.

## Consequences

- Progress works with no server, which is the common case for a folder of CBZs.
- Reading the same file from two different sources resolves to one record
  without the user configuring anything.
- The content hash costs two ranged reads per publication at index time. Over
  SMB this is milliseconds; over a slow link it is deferred until first open.
- A user who deliberately re-reads from the start on one device and continues on
  another will see the furthest position win. That is the documented trade, and
  the one-time notice names both positions so it is recoverable.
- Sync is queue-based and retried, so a failed push is never surfaced as an
  error — it just happens later.

## Links

- Spec: [`reading-progress`](../openspec/specs/reading-progress/spec.md), and
  [`kavita-server`](../openspec/specs/kavita-server/spec.md) for the server side.
- Related decisions: [ADR-0001](0001-independent-native-cores.md) — SwiftData and
  Room are per-platform choices; only the schema semantics are shared.
  [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) provides the ranged reads
  the content hash depends on.
