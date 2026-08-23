# ADR-0006 — Local-first reading progress with content-addressed identity

- **Status:** Accepted
- **Date:** 2026-08-24
- **Deciders:** Cédric Meyer

## Context

[`reading-progress`](../../openspec/specs/reading-progress/spec.md) requires that
progress survive across sources, formats and devices, sync with Kavita, and
never silently move a user backwards. Two problems underlie all of it.

**Identity.** The same publication can arrive as a file in a folder, a file on
an SMB share, and a chapter on a Kavita server. A path-keyed progress record
treats those as three different books. The user does not.

**Authority.** Two devices can read the same publication offline and both come
back with a position. Something has to decide, and the rule has to be one a user
can predict without reading documentation.

## Decision

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
