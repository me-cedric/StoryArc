# A server shelf shows what it holds

**Platforms: both.** The two implementations are already mirrored line for line —
`KavitaShelfScreens.kt` and `KavitaShelfViews.swift` have the same rows, the same
grids and the same three gaps. Behaviour, rules and data are mirrored here too.

## Why

A reader opened a Kavita reading list on a real server and found a numbered list
of titles: no artwork, no sense of where they had got to, and a shelf tile that
was blank. The same reader's *local* reading list, one screen away, shows a
composite cover built from its own members. The server's shelves are the ones
that hold everything, and they are the poorer of the two.

One of the three is not new work at all. `collections-and-reading-lists` already
requires *Progress through a list* — "it shows how many entries are finished and
where the user's position is" — and no server list has ever shown either number.
The row that reports 14 of 18 clauses built and tested counts the local list;
the server list was never separately scored.

## What Changes

- **An entry in a server's reading list states its read progress.** Finished,
  part-read with a position, or unread — the same three states the library grid
  already draws for a publication. The list states its own count with them: how
  many of its entries are finished, and which one the reader is on.
- **A server-backed collection or reading list with no cover of its own is drawn
  from what it holds**, by the rule local shelves already follow: the first four
  member covers as quadrants, or one cover across the frame below four.
  `CompositeCover` and `ShelfCover` already decide this; the server's shelves do
  not call them.
- **An entry row carries the publication's cover at its leading edge**, at the
  same aspect and rounding a library cell uses. The number keeps its place
  before it, because the order is the point of a reading list.
- **Nothing is invented where a server says nothing.** A server that has no
  progress for an entry draws no progress rather than an assumed zero, and an
  entry whose cover cannot be fetched keeps the placeholder the library already
  uses.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `collections-and-reading-lists`: the *Cover for a collection* scenario is
  widened — it says "collection" and applies to a reading list as well, and it
  says nothing about server-backed shelves, which are the ones drawn blank
  today. A new scenario gives a reading list's entry its own artwork, which no
  requirement asks for at present.

## Impact

- `apps/android/feature/library`: `KavitaShelfScreens.kt` (`EntryRow`,
  `KavitaCollectionScreen`, `KavitaListScreen`), `ShelfCover.kt`,
  `ServerList.kt`.
- `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature`:
  `KavitaShelfViews.swift`, and the shelf cover view beside it.
- `:core:kavita` / `Sources/Kavita`: whichever of the read-state and cover
  endpoints the list rows need that the client does not already expose.
  `KavitaProgressStore` on both platforms already holds positions pulled from
  the server; the read state of an entry may be reachable without a new call.
- No data migration. No change to how progress is stored or synchronised.

## Non-goals

- **The unified library.** Kavita publications appearing on Home or in the
  library grid is `one-library-three-destinations`, not this change. This change
  improves the screens a reader reaches *inside* a server source.
- **Reordering, pending edits, and conversion.** Those clauses of
  `collections-and-reading-lists` are built and are not touched.
- **A cover the reader chooses for a server shelf.** The spec already allows a
  specific cover to override the composite; setting one on a server-backed shelf
  is out of scope here, and the composite is the fallback either way.
- **Progress written back to the server.** This change reads and draws progress.
  `kavita-server` owns pushing it.
