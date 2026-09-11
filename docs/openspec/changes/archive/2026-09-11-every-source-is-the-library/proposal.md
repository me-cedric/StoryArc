# Every source is the library

**Platforms: both.** The decision being reversed is recorded twice, once per
platform, in `SourceKind.isBrowsable`, and the index it feeds is mirrored. The
behaviour, the identity rules and the availability axis are mirrored here too.

## Why

A reader with a Kavita server, an OPDS catalogue and an SMB share opens the
library and sees only the files on the device. Their servers hold thousands of
publications and none of them are there. To reach any of it they leave the
library, travel to a source, and browse it — a second app inside the first.

That is not a gap that was overlooked. It is written down:
`SourceKind.isBrowsable` answers false for a local folder and true for the other
three, and its own comment explains why — "a local folder's publications are
scanned and land in the grid… the other three hold content that is not on the
device and each needs its own browser". `LibraryViewModel` fills the grid by
walking picked folder trees, so a source that is not a tree contributes nothing.

**`library-browsing` already says the opposite**, and has since before that code
was written. Its *Unified library* requirement: "publications from every
configured source are shown together", and "nothing on the shelf states which
source a publication came from". Its own text flags the contradiction at the
foot of the file — *publication status has no source* is left open "to be
resolved when a server's publications join the unified library".
`one-library-three-destinations` is 18 of 19 tasks done, reshaped the navigation
and built the availability axis, and never built this.

So the app has a requirement it does not meet, a decision in the code that says
it should not meet it, and a reader who can see the difference.

## What Changes

- **Every configured source contributes publications to the library and to
  Home.** A Kavita series, an OPDS entry, a file on an SMB share and a file in a
  local folder are the same kind of thing in the grid, ranked, sorted and
  filtered together, with nothing on the cell saying where it came from.
- **Browsing becomes a second way in, not the only way in.** The three browsers
  stay: a reader who wants to walk a server's own structure still can.
  `SourceKind.isBrowsable` stops meaning "not in the library" and means only
  "has a structure worth walking". **BREAKING** for that property's meaning, on
  both platforms.
- **A remote publication states that it is remote by what it can do, not by a
  label.** It carries the availability the library already has an axis for: it
  is not readable with no network until it is downloaded, and the grid says so
  the way it already says so for anything else that is not on the device.
- **A publication and its downloaded copy are one row, not two.** The identity
  rules that already exist decide it.
- **The index holds what it has, and the rest stays reachable.** A server with
  forty thousand series does not become forty thousand rows on first connect.
  `library-browsing`'s existing *More from a source than the library holds*
  scenario is the contract: what the index does not hold is reachable from
  search and from an explicit affordance, rendered by the same cells.
- **An unreachable source does not empty the library.** Its publications stay,
  dimmed, saying what they need — which `library-browsing` already requires and
  which currently applies to nothing, because nothing remote is ever in the grid.

## Capabilities

### New Capabilities

None. Every requirement this change needs already exists in
`library-browsing`; what is missing is a spec for *how a source's publications
get into the index at all*, which is the modification below.

### Modified Capabilities

- `library-browsing`: the *Unified library* requirement gains what "every
  configured source" means for a source that is not a folder — when its
  publications are read, how much is held, and what the grid shows while it is
  unreachable or has never been reached. The open question at the foot of the
  spec is answered and removed.
- `sources`: a source's contribution to the library is currently implicit in its
  kind. It becomes explicit and the same for all four kinds, and a source's own
  screen states when it last contributed and what it is holding back.
**Not `home-screen`.** It has no main spec yet — it arrives with
`one-library-three-destinations` — so there is nothing to write a delta against.
Its shelves read this index, so they gain remote publications the moment this
lands, and the one behaviour that needed saying, that a row not on the device is
a row like any other, is said in `library-browsing` above.

**This answers a deferral `sources` wrote down.** Its Open Questions ask whether
"an OPDS or Kavita response [should] be cached to disk so a server's contents
stay browsable offline", and defer it: "it is a real feature, and it needs its
own proposal covering eviction and the origin rule". This is that proposal, and
the delta covers both — what may not be written down, and what happens when the
cache is evicted.

**It collides with `one-library-three-destinations`.** That change also modifies
*Unified library*, and is unarchived. Whichever archives second has to reconcile
the two; the reconciliation is small — that change rewrites the axis a reader
narrows by, this one rewrites what fills the grid — but it will not merge itself.

## Impact

- `apps/android/feature/library`: `LibraryViewModel`'s scan is one of several
  contributors rather than the only one; `LibraryIndex`, the filters and the
  availability axis take rows they did not before.
- `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature`: `LibraryModel`, the
  same shape.
- `:core:model` / `Sources/StoryArcCore`: `SourceKind.isBrowsable`'s meaning,
  and `Publication` gaining whatever a remote row needs that a scanned one does
  not.
- `:core:kavita`, `:core:catalogue`, `:core:smb`: each gains a way to be asked
  for publications, rather than only for a browsable tree.
- ADR-0006 is the identity authority and is **not** changed:
  `PublicationIdentity` already carries `serverIdentifier(sourceId, remoteId)`
  beside `contentDigest` and `normalizedPath`, and `matches` already prefers the
  server's own answer. The machinery for this was built and is unused.
- Persistence: the library cache and the scan journal hold rows that no walk
  produced, and must not delete them when a walk does not see them.

## A series is the row, and the owner reversed a decision to get there

The first build of this change made a **chapter** the row: sixty of a server's
series arrived as roughly twelve hundred cells under sixty headings. The owner
saw it on the phone and asked for Kavita's own shape instead — a series is one
cell, and opening it lists its issues.

That is a change to a specified behaviour, not a preference.
`one-library-three-destinations` introduces *Sectioning a long library*, which
divides a long shelf "by series where a publication declares one, and otherwise
by the active sort key" — sections with headings, every issue its own cell. It
is built and mirrored on iOS in `LibrarySections`.

The reversal is right, and for a reason bigger than servers: the section model
scales with issues and the reader scans series. A local folder of sixty issues
is sixty cells today and one cell after. So the shape changes for every source,
which is also the only reading that satisfies both of the owner's instructions —
"like Kavita does" and "treated the same as the local files".

*Presentation* is therefore modified here too, and modified identically in
`one-library-three-destinations`, for the reason the *Unified library* block
gives: two different blocks on one requirement and whichever syncs second
deletes the other's.

## Non-goals

- **No change to how a publication is read.** A remote publication is opened by
  downloading it, which `offline-downloads` already owns.
- **No new browser, and no browser removed.**
- **No metadata write-back.** Editing a server's own metadata is not in scope.
- **No cross-source deduplication beyond the identity rules ADR-0006 sets.** Two
  servers holding the same comic under different ids stay two rows unless a
  digest says otherwise.
- **Not the reader, the player, or progress sync.** A remote publication's
  progress is `reading-progress` and `kavita-server`'s business and is unchanged.
