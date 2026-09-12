# Source lifecycle

## Why

`sources` is the keystone. It is fully specified, and what exists of it is a value
type and two pure helpers that nothing constructs:

- `Source` — a name, a kind, a state, a last-sync timestamp. Never instantiated.
- `SourceConnectionState` — four states, `canFetch`, `needsUserAction`. Never assigned.
- `ReconnectBackoff` — the 5-second-to-5-minute doubling. Never called.
- A source list in the library, dimmed correctly for an unreachable source, that is
  passed an empty array from both app shells and therefore never draws a row.

So the shape is right and the lifecycle is missing. Four capabilities cannot start
without it, and three tasks in a change that is otherwise complete are held on it:

| Waiting on this | Why |
| --- | --- |
| `opds-catalog` | a catalogue is a source; there is nowhere to put one |
| `kavita-server` | the same, plus a credential to store |
| `network-share` | the same, plus a credential to store |
| `offline-downloads` | a download belongs to a source, and removal has to account for its bytes |
| `reading-progress` → synchronisation | the merge rules are written and unreachable; they need a remote to merge with |
| `format-scope-and-libraries` 5.2, 5.3, 6.5 | all three need something remote to download from |

Two of those are worth naming separately, because they are already *built and dead*:

1. **`ProgressMerge`.** Every conflict rule `reading-progress` states is implemented on
   both platforms and tested, and nothing calls it. It has never run against a real
   remote position.
2. **`PublicationIdentity.serverIdentifier`.** The first of ADR-0006's three identity
   keys. It was silently dropped when read back on iOS until this week, and nobody could
   have noticed, because nothing sets it.

Code that cannot run is not an asset. This change is what makes it run.

## What changes

Nothing about the capability's requirements. They are written, and this change does not
modify them. What changes is that they exist.

Five requirements, in the order they unblock each other:

1. **Source registry.** An ordered, persistent list. Add, rename, reorder, remove. The
   removal path is the interesting one: it has to state how many files and how much disk
   space it will free *before* asking, and it has to keep local reading progress for 30
   days so re-adding the same source restores where the reader stopped.
2. **Credential storage.** The iOS Keychain and an `EncryptedSharedPreferences`-backed
   store on Android. The registry holds an opaque reference, never a secret, and a secret
   is read at the moment of use rather than retained.
3. **Connection state.** The four states produced for real, with the backoff wired in and
   a retry on network regained or on foreground. Unreachable is grey, not red — a source
   that is merely off the network has not failed.
4. **Metadata cache.** What a source contains, kept on disk so the library stays
   browsable when the source is not reachable, with a staleness window and an explicit
   refresh.
5. **Source health.** A screen per source: last error, item count, bytes held, and the
   four actions — test connection, refresh, clear cache, remove.

## What this change does not do

It adds no source *type*. A folder is the only source that exists today and it will be
the only one when this lands. That is deliberate: the lifecycle is what four other
capabilities wait on, and building it against the source that already works means the
first OPDS catalogue is a connector rather than a connector plus a registry plus a
keychain plus a cache.

The consequence is worth stating plainly: **when this change lands, the app will look
almost the same.** A folder becomes a real source with a real state and a real health
screen, and that is all a reader sees. The value is entirely in what can be built next.

## Risks

**The 30-day progress retention is the hard part.** It means removal cannot cascade to
the progress store, so progress rows have to outlive the source they belong to and then
be collected. A collection pass that runs at the wrong moment loses a reading position,
which is the one thing ADR-0006 says the app must never do. This wants a test that
advances a clock rather than one that waits.

**A secret must not reach the diagnostic export.** `DiagnosticRedaction` already exists
and is tested, and the export deliberately carries no free text. Adding sources adds the
first values that could carry a hostname or a token, so the export's source section has
to stay a count rather than becoming a list.

**The cache invites a second source of truth.** A cached catalogue that disagrees with
the live one is how a reader ends up unable to open a book the library shows. The
staleness window and the refresh have to be visible, per the spec's own wording:
"a cached-content indicator".
