## Context

What already exists, read out of the source rather than assumed:

- **The model is complete.** `PublicationCollection`, `ReadingList`, `Shelves`
  and `ShelfOrigin` are mirrored types (`core/model/Shelves.kt`,
  `StoryArcCore/Shelves.swift`). `CompositeCover` picks a collection's four
  tiles; `shelfTiles(list)` / `ShelfCover.tiles(of:)` pick a reading list's four
  in list order.
- **The card is complete.** `ShelfCard` (`feature/library/ShelfCover.kt:214`,
  `LibraryFeature/ShelfCover.swift`) draws cover, name, subtitle, the pending
  count and an optional progress rail. `ShelfComposite` draws quadrants, one
  cover, or a cover-shaped blank.
- **The exhaustive screen is complete.** `ShelvesScreen.kt` and
  `ShelvesView.swift` list local and server shelves in two sections, with the
  headings `shelves_collections` / `shelves_lists` and
  `shelves.collections` / `shelves.lists` already shipped in four languages.
- **Both kinds of Kavita shelf are already fetched, together.**
  `ServerShelf.fetch` (`KavitaShelfViews.swift:43`) calls
  `client.collections()` and `client.readingLists()` in the same pass, each
  guarded separately so a server that answers one still gives the other;
  `ShelvesScreen.kt:126-142` is the same code on Android. Checked in the client:
  `KavitaClient.kt:227` is `GET Collection` and `:250` is the reading-list
  route. Neither kind is missing, so the home surface can name both.
- **The home surface is deliberately offline.** `home-screen`, *The home surface
  never waits on a source*: it is assembled from "locally held reading history,
  local metadata and local curation alone" and renders "with the same shelves in
  the same order as when the sources are up".
- **`ShelfOrigin.Server` is declared and nothing writes it.** Only
  `Shelves.removingAll(sourceId)` reads it. A server's shelves live in view
  state on the shelves screen and are discarded when it closes.
- **OPDS has no shelf.** `opds-catalog` models no collection and no reading
  list. `OpdsGroup` is a section of a catalogue feed, drawn by
  `CatalogueGroupSection`, and it belongs to the publisher rather than to the
  reader.

## Goals / Non-Goals

**Goals:**

- The home surface names every shelf the device knows about, including a
  server's, with no request and no waiting.
- One card, one composite rule, one heading string: nothing is drawn twice by
  two pieces of code that can disagree.
- The assembly is pure and asserted on a plain JVM and a host Swift test, the
  way `HomeShelves` already is.

**Non-Goals:**

- No request from the home surface, ever. This is the constraint the design
  serves, not a cost it pays.
- No change to how a shelf is made, renamed, deleted or pinned.
- No OPDS shelf. There is nothing to list.

## Decisions

### One shelf or two: two

Two shelves, Collections first, then Reading lists.

The capability's own purpose paragraph refuses to conflate them, and the
difference is visible on the card rather than only in the heading: a reading
list carries the progress rail `ShelfCard` already draws, because the reader has
a position in an ordered thing. A collection has no order, so it has no position
and never carries the rail.

Two is also the cheaper option, which settled it. The two headings exist in four
languages on both platforms because the shelves screen ships them, so two
shelves need **no new string**; one merged shelf would need a new name for a
merged idea in eight files. And the "always present, always empty" failure the
task names cannot happen here, because each shelf is absent when its kind holds
nothing — a reader with two collections and no lists sees exactly one heading.

### A shelf with no cover of its own

`ShelfComposite` already decides this and is reused unchanged: four tiles as
quadrants, one tile across the card below four, and `surfaceRaised` in the shape
of a cover when there are none. The blank case is the one the home surface meets
most, because a shelf a server defined has no local members at all.

`ShelfComposite` is `private` in Android's `ShelfCover.kt`; it becomes
`internal`, which is what iOS's already is. That is the whole of the change to a
shared file.

### When a source is away, and when there is nothing

- **A source that is away changes nothing.** The list comes from what was
  written down, so the same shelves are named whether the server answers or not.
  This is the requirement, not a fallback.
- **A source that is removed takes its shelves with it.** The listing keeps only
  remembered shelves whose source is still in the registry, so an uninstalled
  server does not leave names behind. The record itself is left alone rather than
  tidied during a draw, for the reason `HomeScreen.swift` gives about an orphan
  pin: writing to storage while drawing turns a redraw into a write.
- **Nothing at all draws nothing at all.** Each shelf returns early on an empty
  list, the way `shelf()` and `keepReading()` already do on Android and
  `if !recentlyAdded.isEmpty` does on iOS.

### How a server's shelf reaches the home surface: it is remembered

A new pure type, `RememberedShelf`, mirrored token for token:

```
collection:<source UUID>:<server id>:<title>
list:<source UUID>:<server id>:<title>
```

Modelled on `ShelfPin`, which is the house pattern for exactly this — a word and
an identity, readable in a preferences file, and immune to a case being
reordered. The title is last and the token is split at most three times, so a
title holding a colon survives. Tokens are separated by a newline, which a shelf
title cannot contain, rather than by the space `PinnedShelves` uses.

Written where the pins are written: a `Set<String>` under one new
`LibraryPreferences` key on Android, and one `@AppStorage` scalar under
`RememberedShelf.storageKey` on iOS. The container differs and the tokens do
not, which is the half that has to match.

The shelves screen writes the record once per fetch, replacing it wholesale: the
fetch already asks every configured server, so its answer is the complete set
and a merge would only preserve shelves that have been deleted on a server.

**Why not `ShelfOrigin.Server` inside `Shelves`.** `Shelves` is the reader's own
store: `AddToShelfSheet` offers every collection in it as a place to put a
publication, `ShelfEditQueue` tracks pending edits against it, and the shelves
screen draws all of it as locally owned. Writing a server's shelves in would put
rows into all three that none of them can honour. A record beside it costs a
preference key and touches nothing.

### What a card leads to

A local shelf opens its own detail screen, as it does from the shelves screen. A
remembered shelf opens that server's shelf page —
`Screen.ServerShelfPage` on Android, `KavitaCollectionView` /
`KavitaListView` on iOS — which is where an unreachable server is reported, and
reporting it there is what keeps the home surface silent about it.

A remembered shelf whose source has lost its key cannot build a page to open, so
it is not listed. The registry filter and the credential filter are the same
filter: the app layer passes the set of source ids it can actually open, and the
pure assembly keeps only those.

## Risks / Trade-offs

- **A remembered card is usually blank artwork.** Its members are chapters on a
  server, and the device holds no cover for them. Accepted: the alternative is
  fetching, which is the one thing forbidden. The name and the source label
  carry the card, and `ShelfComposite`'s blank is cover-shaped so the row still
  reads as a row.
- **A stale name.** A collection renamed on the server keeps its old name on the
  home surface until the reader next opens the shelves screen. Accepted: the
  record is a memory of what a server said, and it is corrected by the screen
  that asks.
- **A shelf deleted on the server is still listed** until the same moment.
  Choosing it lands on a page that says the shelf is gone, which is the existing
  behaviour for a shelf that disappears between a fetch and a tap.
- **Two more shelves on a long surface.** They sit between Recently added and
  the pinned shelves: the index before the expansions, and above Finished, which
  `home-screen` fixes as last.

## Migration

None. A reader who has never opened the shelves screen has no record, so the
two shelves list their local collections and lists and nothing else, which is
the correct answer for that device.
