## Context

See proposal.md — Why. What matters here is how much already exists, because it
decides the shape of the work.

**The identity rules were built for this and are unused.**
`PublicationIdentity` (`core/model/PublicationIdentity.kt:19`) carries
`serverIdentifier(sourceId, remoteId)` beside `contentDigest` and
`normalizedPath`, and `matches` (`:105`) already prefers the server's own answer
over a digest and a digest over a path — ADR-0006's order. Nothing in the app
ever fills `serverIdentifier` from a live server's listing, so the branch that
decides "these two rows are the same publication" has never fired for a remote
row. Making a Kavita series a `Publication` does not need a new identity model;
it needs that field populated.

**The index is a scan, and only a scan.** `LibraryViewModel.rescan`
(`feature/library/LibraryViewModel.kt:698`) walks picked trees through
`LibraryScanner`, `adopt`s what it finds, and reconciles what a walk did *not*
see. Two things follow: there is no seam for a contributor that is not a walk,
and `ScanReconciliation` will delete rows nothing walked past unless it is told
which sources a given round actually covered — it already distinguishes "found
nothing" from "could see nothing" per source, which is the hook.

**A cached server catalogue is a deferral, not a blank.** `sources`' Open
Questions name exactly why it was deferred: a second catalogue store per source
type, in a caches directory the system may evict mid-browse, holding
server-supplied acquisition URLs "which is where an embedded credential could
survive a launch". Both are design problems this document has to answer, and the
delta now requires answers.

## Goals / Non-Goals

**Goals:**

- One index, one cell, one publication page. A remote row differs from a local
  one in what it can do, never in what draws it.
- A contributor seam narrow enough that a fifth source kind is a new
  implementation and nothing else.
- No credential reaches disk, and evicting the cache is safe at any moment.

**Non-Goals:**

- Design-level: no background sync schedule, no push. A source is read when the
  library is opened, when a reader refreshes, and when its staleness window has
  passed — which `sources` already specifies.
- No pagination UI. "More from this library" is one affordance, already
  specified; how a browser pages is the browser's business.

## Decisions

**A source contributes through one interface, and the scan becomes one
implementation of it.** `LibraryViewModel` stops owning "the walk" and owns "the
contributors": something that, given a source, produces publications and says
whether it saw the whole of it. The folder scan is one, a Kavita client another,
OPDS a third, SMB a fourth. The alternative — teaching the scanner to walk a
server — was rejected because a server is not a tree and a walk that cannot
report partial coverage is what makes `ScanReconciliation` delete rows.

**Coverage is per source and explicit, and reconciliation obeys it.** A
contributor answers with what it found *and* whether that is everything. A
partial answer never deletes: the spec's *A source that answered nothing* is the
same rule the scanner already applies to an unreadable directory, extended to a
server that answered a page and no more.

**A remote publication is a `Publication` with no local path.** Availability is
already an axis; a row with nothing on disk is already expressible. What it
gains is `serverIdentifier`, and what it lacks is `normalizedPath` — which is
what `matches` needs to fold a downloaded copy into the same row, and what
`PublicationIdentity.key` (which prefers the path, "and only here") needs
watching: a row filed under a server key that later gains a path must not change
key, or every stored thing keyed to it moves at once.

**How much is read: a bounded first page, then on demand.** The first read of a
source takes a bounded, recency-ordered slice — newest first, because that is
what Home's *Recently added* wants and what a reader recognises. The count is
stated as partial, per the delta. A reader who asks for more gets more; search
asks the server directly, which `library-browsing`'s *Mixed local and server
search* already requires and which is why an unread publication is still
findable. Alternative considered: read everything on first connect. Rejected on
the owner's own server — 40k series is minutes of requests and a cache nobody
asked for. **[NEEDS CLARIFICATION: what the first slice's size should be. 200 is
a guess that fills several screens; it wants a number chosen against a real
server, not asserted here.]**

**The catalogue cache is one store, not one per source kind.** Rows are
`Publication` values keyed by source, written where the library cache already
lives (`core/persistence/LibraryCache.kt:28`) rather than in a caches directory
the system evicts unpredictably — so eviction is the app's decision and the spec
can say what it costs. Alternative considered: one store per client, in
`Caches/`. Rejected for the reason `sources` already gave: mid-browse eviction,
and two more places for a secret to land.

**No acquisition URL is stored whole.** An OPDS acquisition link can carry a key
in its query, and a Kavita image or download route carries `apiKey`. What is
cached is the address with the secret removed plus the source id; the secret is
read from the credential store and re-applied when the request is made. This is
the origin rule `sources` deferred, and it is also what the 2026-08-30 security
review asked for when it found `app.storyarc.sources.xml` in the backup set.

**Platform APIs.** Nothing new on either side: Kotlin coroutines and
`StateFlow` as `LibraryViewModel` already uses; Swift concurrency and
`@Observable` as `LibraryModel` already uses. No new dependency on either
platform, verified against `gradle/libs.versions.toml` and `Package.swift`.

**Accessibility.** A remote row must not be distinguishable only by dimming:
`library-browsing` already requires it to "say plainly that it needs its source
to be reachable", so that sentence is in the accessibility label of every such
cell and not only in its opacity. The partial-count statement is text, not a
badge. Nothing here adds a colour-only signal.

## Risks / Trade-offs

- **The grid grows by an order of magnitude and the scan path was written for
  hundreds.** → The first slice is bounded, and the sort and filter already run
  over a `StateFlow` list; the number in that slice is the knob, and it is the
  open question above rather than a guess baked into code.
- **`ScanReconciliation` deletes what it does not see.** A contributor that
  fails mid-round could empty a source. → Coverage is explicit and a partial
  round deletes nothing; the existing per-source `partial` set is the mechanism,
  and the first task is a test that a failed contributor removes no row.
- **A key that moves.** A row filed under a server key that later gains a
  downloaded path could change `key` and orphan everything stored against it.
  → `key`'s own contract says it must not move; the merge keeps the original
  key and adds the path, and a test pins it.
- **Two sources holding the same comic.** Out of scope per the proposal, but the
  library now has the chance to show duplicates it never could before. → They
  stay separate rows unless a digest matches, which is ADR-0006's answer, and
  `sources`' own open question on de-duplication stays open.

## Migration Plan

The cache gains rows no walk produced. A device upgrading mid-way has a cache
written by the old code: it holds only scanned rows, every one with a path, so
it loads unchanged and the first read of each source adds the rest. No stored
row changes shape, and nothing needs rewriting on first launch. Rolling back
leaves remote rows in the cache that the old code will drop on its next
reconciliation, which is the correct outcome for a build that cannot open them.

## Open Questions

- The size of a source's first slice, as above. It does not change the specs,
  the contributor seam or the task breakdown — only a constant — which is why it
  is here rather than blocking.
