## Context

`library-portability` defines the document. This decides where it lives, when it moves, and how
two devices that both moved are reconciled.

The reconciliation already exists in shape: `ProgressMerge`, `ProgressPull` and `ShelfMerge` are
on both platforms and implement ADR-0006. It is broken in fact, and that is the first task.

## Goals / Non-Goals

**Goals.** Two devices of one reader stay in step, across platforms, with no account and no
service. Say honestly what "automatic" means on each platform.

**Non-Goals.** Real-time sync. Sharing a library between two people. Syncing publication files —
the document carries choices, not books.

## Decisions

### The route is a place the reader already configured

Three routes cross both platforms: a document in a place the reader configured, Google Drive's
app-data folder over plain OAuth, and WebDAV. The first is chosen, and the project's own
contract is what chooses it.

`AGENTS.md` non-negotiable 2: "No backend, no account, no analytics, no crash reporting. Data
leaves the device only to sources the user configured." A share the reader added is a source
they configured. A folder they picked is a place they chose. A Google account is neither.

This also answers the original ask better than naming a provider would. A reader who wants the
file on iCloud Drive or Google Drive picks that folder in the system picker. The app writes a
file; the provider syncs it; StoryArc holds no account and needs no SDK. iCloud was never an
option as a *route*, because it reaches no Android device at all — Apple ships no iCloud app
for Android, and icloud.com in a browser is not something an app can drive.

The cost is real and is accepted: this is the highest-code-cost option, because records that
have never been merged before — settings, themes, the source list — need a merge now.

### The watermark bug is a prerequisite, not a sub-task

`reading-progress`'s *Conflict resolution* asks, four times, whether a side changed "since the
last sync". Production code never writes what the last sync was. `STATUS.md` records this: every
conflict notice the app shows today is false.

Sync cannot be built on that. Two devices would announce a conflict on every publication at
every sync. It is fixed first, it carries a spec delta because the requirement has to say the
watermark is written, and the delta adds the never-synchronised case explicitly, because a new
device is the common case and an absent watermark must not read as "the local side moved".

### A write merges, it does not replace

Two devices can write within moments of each other, especially through a file provider that
syncs on its own schedule. A device that reads, changes its own records and writes the whole
document back would drop whatever the other device added in between.

So a write is read-merge-write against the document as it is at that moment, and each record
carries which device last changed it and when. A provider that offers an atomic replace is used
where it offers one; where it does not, the losing writer re-reads and merges rather than
overwriting.

### Kavita keeps its own

A Kavita publication's position already goes to the Kavita server. Putting a second copy in the
document gives two sources of truth for one fact, which will disagree. Kavita keys every record
to its own series and chapter ids, so it can hold nothing about a local file, a share or an
OPDS row — which is exactly the set the document carries. The split is clean because the data
splits cleanly.

### What "automatic" is allowed to mean

- **Foreground**: guaranteed. The app is running.
- **Leaving a publication**: guaranteed, and it is the moment that matters — the position a
  reader will look for on the other device is the one they stopped at.
- **Background**: opportunistic, and different per platform. Android's shortest periodic work is
  15 minutes. iOS grants a background refresh it may skip entirely, at its own discretion.

The setting says this per platform. One sentence claiming the same behaviour on both would be
false on at least one.

## Risks / Trade-offs

**A file provider is not a database.** Two devices writing through iCloud Drive or Google Drive
can produce a conflicted copy at the provider's layer, which the app will see as a sibling file.
The app detects one and merges it rather than ignoring it.

**The share route needs SMB write**, and the client reads today. That is new surface on a
protocol this project has already found sharp.

**Records that have never been merged now must be.** Settings and themes have no merge rule.
The rule chosen is last-writer-wins per field with the device and moment recorded, because a
setting is a preference rather than an accumulating value — unlike a reading position, where
furthest wins.

## Migration Plan

Sync is off until turned on. A reader who never turns it on is unaffected. The watermark fix
changes behaviour for everyone, and changes it from wrong to right: conflict notices that were
false stop appearing.

## Open Questions

**One.** Should a reader be able to point two devices at one Kavita server *instead of* a
document, for the subset Kavita can hold, and skip the document entirely? It would be the
smallest possible sync for a Kavita-only reader. It is not proposed here because it covers
nothing outside Kavita, and a reader with a share and a Kavita server would then have two sync
mechanisms with different coverage.
