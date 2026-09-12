## Context

See [`proposal.md`](proposal.md) for motivation. One thing about the current state
has to be said before any decision below makes sense.

**Most of this change is already built.** The proposal was written on 2026-08-27
against a capability whose only code was a value type and two uncalled helpers.
Since then the registry, the credential stores, the probe and its backoff, the
diagnosis value and the per-source health screen have landed on both platforms —
and `ProgressMerge` and `PublicationIdentity.serverIdentifier`, the two pieces the
proposal called "built and dead", are now reached through `KavitaExchange`.

So this document is not a plan for greenfield work. It **records the decisions the
code already took**, so they are reviewable and so the next connector inherits them
rather than re-deciding, and it names the four things that remain. Where a
decision differs from what the proposal expected, it says so.

The audited position, from [`STATUS.md`](../../STATUS.md)'s `sources` row: 16
scenarios, 12 built on both platforms, 2 built and asserted by nothing, 2 on one
platform only. **None of it has been driven on a device.**

## Goals / Non-Goals

**Goals:**

- Record the concrete API per platform for each of the five requirement groups, so
  a reviewer can check the choice rather than infer it from the code.
- Name the decisions that are *not* obvious from reading one file: what is
  deliberately not persisted, what is deleted in which order, and where the
  30-day retention lives.
- Close the change: name the remaining work precisely enough that `tasks.md` is a
  short list rather than a restatement of the capability.

**Non-Goals:**

- No new source type. The proposal's non-goal still holds: a folder is the only
  source that exists, and the first OPDS catalogue is a separate change.
- No caching of OPDS or Kavita responses. That question was settled by amending
  the spec, not by building a cache — see **Decisions**, and it stays recorded as
  an open question rather than deferred silently.
- No change to any requirement in `sources`. This change carries no delta, which
  is why `.openspec.yaml` declares `skip_specs: true` with the reason beside it.

## Decisions

### 1. The registry is a value type; the store is a JSON blob under one key

`SourceRegistry` (iOS `StoryArcCore/SourceRegistry.swift`, Android
`core/model/SourceRegistry.kt`) is an immutable value with pure operations —
`adding`, `renaming`, `moving`, `replacing`, `removing`, `dropping`. Persistence is
one JSON document: `UserDefaults` under `app.storyarc.sources` on iOS
(`Persistence/SourceStore.swift`), the mirrored `SourceStore.kt` on Android.

*Why, over the alternative:* a per-key store lets two halves of one ordered list
disagree after a partial write, and the whole registry is read together to draw a
single screen. Order is not decoration — `sources` requires the combined library to
list higher sources first for a publication two sources both hold, so position
carries meaning and a `Set` would lose it.

*Not Room or SwiftData,* although Room 2.8.4 is already in the Android version
catalogue: the registry is a handful of rows read whole, and a schema plus a
migration per field is cost with no query to justify it.

### 2. Connection state is never persisted

Every source loads as *connecting* and whatever probes it says otherwise.

*Why:* the state describes a network at this instant. A state read back from disk
is a claim about the past presented as the present — the same argument that keeps
the last error derived from the state in `SourceDiagnosis` rather than remembered
beside it, so a source that failed an hour ago and is answering now reports no
error.

### 3. Backoff is arithmetic, in a pure function, mirrored

`SourceProbe.delay(afterFailures:)` doubles from 5 seconds and caps at 300 —
5, 10, 20, 40, 80, 160, 300 — by shifting rather than `pow`, so the sequence is
readable in the source. `SourceProbe` also maps an HTTP response to a state.

*Why the split:* reaching a server is platform work and hard to test. Deciding
what a 401 means and how long to wait after the fourth failure is neither, and
that is where the requirement lives. Both platforms assert the same table.

*The cap is a product decision, not a default:* a source off the network for a day
is asked every five minutes, so a laptop rejoining the network is noticed while the
reader still has the phone in their hand.

### 4. Secrets: Keychain on iOS, Android Keystore on Android — not the class the spec names

- **iOS**: `Persistence/CredentialStore.swift`, `SecItem` against the Keychain
  (Security framework, iOS 26 floor — no shim).
- **Android**: an AES-256-GCM key held in the Android Keystore, ciphertext in an
  ordinary `SharedPreferences` entry (`core/persistence/CredentialStore.kt`).

**The requirement names `EncryptedSharedPreferences`, and the code deliberately
does not use it.** That class and its `MasterKey` are deprecated in
`androidx.security:security-crypto` 1.1.0 with no replacement offered, and this
project compiles with `allWarningsAsErrors`. What the implementation does is what
that class did: the key never enters the app's memory, only the cipher does. The
Keystore *is* the platform secure store the requirement means.

*One entry per source,* keyed by the source's identifier — not one entry holding a
map. Removing a source must remove exactly its own secret, and a shared blob turns
a delete into a read, an edit and a write.

The registry holds an **opaque reference**, never a secret, and a secret is read at
the moment of use rather than retained. That is what makes the "never in
preferences, logs, backups or diagnostics" clause structural instead of a habit.

### 5. Removal order: the secret first, unconditionally, by the stored reference

`SourceRemoval` deletes the stored secret **before** anything else, and by the
reference the registry holds — not one re-derived from `source.id`.

*Why it is spelled out:* a source whose id and credential reference disagreed (as
every iOS Kavita source's did) would otherwise keep its key for ever. And a folder
lookup used to gate the whole method, so removing anything that was not a folder
did nothing at all. Both are fixed; the ordering is the part that must not
regress.

### 6. The 30-day retention is a tombstone plus a separate collection pass

`removing(_:at:)` leaves a `SourceTombstone`; `collectingExpiredTombstones(as:retention:)`
is what drops one. Re-adding a source with the same identifier clears its
tombstone, which restores the reader's position.

*Why the two are separate functions:* deciding *when* the 30 days are up is a
clock decision, and a function that read the clock itself could only be tested by
waiting. Passing the moment in is what lets a test advance a clock instead —
which the proposal's risk section asked for, and which matters because losing a
reading position is the one thing [ADR-0006](../../../decisions/0006-progress-storage-and-sync.md)
says the app must never do.

### 7. "Cached contents remain browsable" was answered by amending the spec

The clause was only ever true for a local folder. OPDS and Kavita responses are
never written to disk, and three reasons kept it that way:

1. Caching them means a second catalogue store per source type.
2. It lives in a caches directory the system may evict mid-browse, so the "not
   available offline" screen is still needed — the cache removes no code.
3. It puts server-supplied acquisition URLs on disk, which is where an embedded
   credential could survive a launch.

So opening an unreachable server says it cannot be reached, says its downloads stay
readable, and offers to try again. The scenario was rewritten to state that. The
caching question is recorded as open, with those reasons, rather than dropped.

**What *is* cached** is the folder walk: the catalogue is written when a walk
finishes and restored before the next one starts, and covers likewise — keyed by
publication *and* pixel size, both in the caches directory, so they are evictable
independently of downloads with no code for it. A refresh updates incrementally,
and a publication a walk no longer finds is removed while its progress stays.
Neither the removal nor the write fires on a walk that saw *nothing at all*: that
is far more likely to be a folder that could not be read than a reader who deleted
every book.

## Accessibility consequence

The per-source health screen is where this change is felt by a reader who does not
look at the screen, and two of its choices are accessibility choices:

- **The last error is plain language, not a code.** A screen reader announces a
  sentence; `NSURLErrorDomain -1009` announced letter by letter is noise.
- **Unreachable is grey, not red, and never colour alone.** State is announced as
  text in the accessibility label. A source that is merely off the network has not
  failed, and a reader who cannot distinguish grey from red must not have to.
- The five actions are individually labelled controls, not one menu, so each is
  reachable by direct navigation rather than by opening a container first.

The bytes-and-files figure in the removal confirmation is announced as part of the
same label as the question, so the consequence and the choice are one utterance
rather than two the reader must correlate.

## Risks / Trade-offs

- **[The collection pass runs at the wrong moment and a reading position is lost.]**
  → The pass takes the moment as a parameter and is asserted with an advanced
  clock on both platforms. Re-adding the same identifier clears the tombstone
  before any collection can see it.
- **[A secret reaches the diagnostic export.]** → `DiagnosticRedaction` exists and
  is tested, and the export carries no free text. The export's source section
  stays a **count**, never a list — sources are the first values that could carry a
  hostname or a token.
- **[The metadata cache becomes a second source of truth.]** → The staleness
  window and the refresh are visible, per the spec's "cached-content indicator".
  **The honest limit recorded here is closed** (task 5.1, 2026-09-05): the scanner
  reports every directory it could not list, and the notice now leaves only when a
  walk genuinely read the folder. Closing it turned up two things this section had
  not seen. The emptiness rule it described — a walk that found nothing removes
  nothing — was an inference that only ever covered a folder unreadable *whole*; a
  folder that lost one subdirectory still returned rows, so the books under the
  branch it could not list were removed as though deleted. And on iOS nothing had
  ever called `cacheLibrary` after a walk at all, so no snapshot was written, none
  was restored, and the indicator could not appear in the first place.
- **[Everything above compiles and is asserted, and nobody has watched it work.]**
  → This is the largest open risk in the change and it is not a test gap. The
  Simulator control this repo uses has been down and no emulator was available, so
  the source detail screen, the reconnect sheet, the offline notice, pull-to-refresh
  and the precedence rule with two sources holding one title have been seen by
  nobody. Task group 4 is the visual proof, and this change is not archivable
  without it.

## Open Questions

1. **Should OPDS and Kavita catalogue responses be cached to disk after all?**
   Deferrable: the spec now says what the app does, so the answer changes no
   requirement and no task here. Revisit when the first catalogue connector lands
   and there is a real response shape to reason about. The three reasons against
   are in decision 7.
2. **Where does a reachability observer belong?** Neither platform retries on
   regained connectivity or on returning to the foreground, because nothing is
   wired to the probe. Whether that observer lives in the library model or beside
   the probe is a placement question, not a behaviour one — task 3.1 decides it
   in the code review of that task. `Assumed`: `NWPathMonitor` on iOS and
   `ConnectivityManager.NetworkCallback` on Android are the platform APIs; neither
   has been used in this repository yet.
