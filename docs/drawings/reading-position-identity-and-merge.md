# The reading position: identity, merge, and the rules the code cannot reach

Companion to
[`reading-position-identity-and-merge.mmd`](reading-position-identity-and-merge.mmd).

## Why this one exists

Losing a reading position is the one thing [ADR-0006] says the app must never do
by accident, and the rules that prevent it are the least guessable thing in the
repository. The diagram is drawn **honestly rather than tidily**: two of the four
conflict rules do not behave at runtime the way the table describes, and a
picture that hid that would be worse than no picture.

## Read from

| File | What it settled |
| --- | --- |
| `docs/decisions/0006-progress-storage-and-sync.md` | the whole decision, and its "What the code reaches, and what it does not" section |
| `docs/openspec/specs/reading-progress/spec.md` | the requirement the ADR answers |
| `docs/openspec/specs/kavita-server/spec.md` | the server side |

The ADR's gap analysis was read out of both trees on 2026-08-30 and carries
`path:line` evidence for each claim; the diagram repeats its conclusions rather
than re-deriving them. The line references below are the ADR's.

## The two things the diagram says that the table does not

**Rule 1 cannot be reached.** `syncedPosition` is the field that *"since last
sync"* is measured against, and no production code on either platform writes it
— every construction outside a test takes the default nil (`ReaderModel.swift`,
`ReaderViewModel.kt`, `EpubReaderViewModel.kt`). `ProgressMerge` reads that
absence as "assume it moved", so `localMoved` is permanently true and the
silent-adoption row falls through to rule 3.

What a reader actually sees: a chapter read on another device, and nothing read
on this one, raises the "Read in two places" alert and asks which position to
keep. The position it settles on is still the right one — furthest wins, and the
further one is the remote — but the reader is asked to resolve a conflict that
is not one, which is exactly the interruption rule 1 exists to avoid.

Writing the position down as `syncedPosition` when it is pushed or adopted is
what closes this. Nothing in the rule itself needs changing. Note that the two
stores would still disagree once it is written: iOS encodes the whole
`ReadingPosition` as JSON, while Android keeps only its fraction in a single
column and rebuilds a reflowable position with an empty locator — so the column
has to carry the position, not a number derived from it.

**Rule 2 is reached and pushes nothing.** `ProgressPull` sorts a merge into
three piles, and the `toPush` pile is discarded by both of its callers:
`KavitaSync` consumes `toSave` and `conflicts` and nothing else. A pull that
establishes the server is behind saves the local record it already had and tells
the server nothing. Positions do still reach Kavita, by the ordinary route —
`KavitaSync.report` on leaving the reader, with held ones flushed when the server
is reachable again — which is why that node hangs off rule 2 rather than
replacing it.

## Identity, and why the last resort is the common case

The order of preference is server identifier, then content digest, then
normalised path. In practice:

- **Rule 1 is never constructed in production.** The only `ServerIdentifier`
  built outside a test is the one each store decodes back out of a stored key,
  and nothing writes that key non-nil.
- **Rule 2 has one production caller in the repository** — `OpenedFile.kt`,
  where Android digests a file handed to it from outside the app. On iOS,
  `PublicationIndexer.contentDigest` is called only by its own test.
- **So anything the library scanned is identified by rule 3.** Both library
  scanners key on the path.

Two consequences the ADR claims therefore do not hold at runtime for scanned
publications: that a position survives a rename or a move, and that one file read
from a folder and from a share resolves to one record. The lookup that would
honour a digest is written and tested; it is the digest that is not supplied.

One promised outcome does hold, by a route the ADR does not describe: a Kavita
chapter finds its local record because `KavitaProgressStore` keeps its own
chapter-id to publication-id table. That is a side mapping beside the identity,
not identity rule 1, and it covers Kavita only.

## Why the rules are these rules

Furthest-wins beats last-write-wins because clock skew between a phone and a NAS
is real, and the failure mode of furthest-wins — being a few pages ahead of where
you were — is trivially recoverable, while the failure mode of last-write-wins is
losing an evening's reading. Finished is sticky because unmarking a finished
publication is a deliberate act, and losing it to a stale sync is not something
anyone would want.

The decision itself is sound and is not what the gaps call into question:
`ProgressMergeTests` and `ProgressMergeTest` assert the whole table on each
platform. What the diagram records is that the app cannot currently *reach* parts
of what those tests prove correct.

[ADR-0006]: ../decisions/0006-progress-storage-and-sync.md
