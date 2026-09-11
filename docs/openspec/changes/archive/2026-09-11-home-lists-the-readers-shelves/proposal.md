# Home lists the reader's shelves

**Platforms: both.** The home surface is `HomeScreen.kt` and `HomeScreen.swift`,
and both already draw a *pinned* shelf's contents. Neither lists the shelves
themselves.

## Why

Home offers Keep reading, Up next, Recently added and Finished. Every one of
them is a shelf of publications. Nothing on the surface says the reader owns
seven collections and two reading lists, and the only way to that set is a text
row on iOS (`HomeScreen.swift`, `shelvesLink`) and a rail item on Android that a
reader has to already know about.

A collection is curation the reader made. It is the one thing on this surface
that is theirs rather than computed from their history, and it is the one thing
the surface never shows.

**A server's collections are worse off than a local one.** Kavita answers with
both its collections and its reading lists, and the app asks for both — 
`ServerShelf.fetch` on iOS and the same two calls in `ShelvesScreen.kt` on
Android. But the answer is held in view state and thrown away when the screen
closes, so the home surface has never had a name to draw. `ShelfCard`'s own
documentation names this as a gap rather than a decision: "a home surface that
resolved such a pin would have to ask a server, which `home-screen` forbids
outright".

That constraint is real and is not being relaxed. `home-screen` requires the
surface to render "complete and immediately" with every source down, "with the
same shelves in the same order as when the sources are up". A shelf that
appeared when the Wi-Fi came back would break it.

So the fix is memory, not a request: what a server already told us is written
down, and the home surface reads what is written down.

## What Changes

- **Two shelves on the home surface: Collections, then Reading lists.** Two and
  not one, because the capability opens by refusing to conflate them and because
  both headings already exist in four languages on both platforms.
- **Each shelf is absent when it holds nothing.** A reader with collections and
  no reading lists sees one shelf. A reader with neither sees no heading at all.
- **A shelf's card is its artwork**, by the composite rule collections and
  reading lists already follow: the first four member covers as quadrants, one
  cover below four, and a cover-shaped blank when the device holds none of them.
- **A server's collections and reading lists are remembered.** The shelves
  screen writes down what each server answered — kind, source, the server's own
  id, and the title. The home surface lists them from that record, labelled with
  the source, and they stay listed while the server is away.
- **A removed source takes its remembered shelves with it.** They are named on
  the home surface only while their source is still configured.
- **Each heading leads to the shelves screen**, which is the exhaustive list and
  the only place a shelf is created, renamed or deleted.

## Capabilities

### Modified Capabilities

- `collections-and-reading-lists`: one new requirement, *Shelves on the home
  surface*. Nothing existing is reworded. The capability already requires local
  and server shelves to appear together "each labelled with its source"; it has
  never said where, and the home surface is now one of the places.

## Non-Goals

- **The home surface does not ask a server anything.** No fetch, no refresh, no
  loading state. This change exists to keep that property while still naming a
  server's shelves.
- **No OPDS collections.** An OPDS feed's groups are sections of a catalogue the
  publisher arranged, not shelves the reader owns, and `opds-catalog` models no
  collection at all. An OPDS source contributes nothing to these two shelves.
- **No new way to make, rename or delete a shelf.** The shelves screen keeps all
  of that.
- **No pinning change.** A pinned shelf still gets a shelf of its own contents
  further down the surface, and these two shelves list every shelf whether it is
  pinned or not.

## Impact

- `apps/android/core/model`: `RememberedShelf.kt` (new).
- `apps/android/core/persistence`: `LibraryPreferences.kt` gains one key.
- `apps/android/feature/library`: `HomeShelfListing.kt` and `HomeShelvesRow.kt`
  (new), `HomeScreen.kt`, `ShelvesScreen.kt`, `ShelfCover.kt`.
- `apps/android/app`: `HomeDestination.kt`.
- `apps/ios/Packages/StoryArcKit/Sources/StoryArcCore`: `RememberedShelf.swift`
  (new).
- `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature`:
  `HomeShelfListing.swift` and `HomeShelvesRow.swift` (new),
  `HomeScreen.swift`, `ShelvesView.swift`.
- No new user-facing string. Both headings, the item count and the source label
  are the ones the shelves screen already ships.
