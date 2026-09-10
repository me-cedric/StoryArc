## Context

See proposal.md — Why. What matters here is how little is missing: the data is
already on the wire and the drawing code already exists on both platforms. This
change mostly connects them.

Probed against the owner's own Kavita server on 2026-09-10, authenticated with
the key in `.env`:

- `GET /api/ReadingList/items?readingListId=<id>` returns each entry with
  **`pagesRead` and `pagesTotal`**, alongside `order`, `chapterId`, `seriesId`,
  `volumeId`, `seriesName`, `title` and `lastReadingProgressUtc`. A list of 77
  entries returned all of it in one call.
- `POST /api/ReadingList/lists` returns each list with `coverImage`,
  **`coverImageLocked`**, `itemCount`, `primaryColor` and `secondaryColor`.
- The app's own models discard exactly the fields this change needs:
  `KavitaReadingListItem` (`core/kavita/KavitaShelves.kt:29`) keeps `id`,
  `order`, `seriesId`, `chapterId`, `title`, `seriesName` and drops the two
  progress numbers; `KavitaReadingList` (`:21`) keeps `id`, `title`, `summary`.
  Both are `@Serializable` and decoded with `ignoreUnknownKeys`, so widening
  them is additive.

What already exists and is not being built again:

- `CompositeCover` (`core/model/CompositeCover.kt`) picks the four tiles, and
  `ShelfCover` (`feature/library/ShelfCover.kt:66`) draws quadrants or one cover
  across the frame. `ShelfCover.kt:141` already takes a reading list's entries
  in list order — it is called for local shelves only.
- **`ShelfCover` does not take covers.** It takes local publication ids and a
  `LibraryViewModel`, and resolves the artwork itself out of
  `viewModel.publications`; iOS's `ShelfCover.swift:19` takes a `LibraryModel`
  the same way. A Kavita shelf's tiles are chapter ids whose artwork comes from
  the client, which neither composable can reach. The blank tile itself is
  `ShelvesScreen.kt:473` and `ShelvesView.swift:328`, where the server's card
  passes an empty tile list.
- `KavitaClient` already exposes `Image/series-cover` and `Image/chapter-cover`
  (`KavitaClient.kt:145,151`), so an entry's poster needs no new route.
- `KavitaSeriesCell` (`feature/library/KavitaSeriesGrid.kt:48`) is the pattern
  for a cover fetched through the client rather than an image loader — Kavita's
  image routes want the reader's key, and a loader has nowhere to put one — and
  it already draws a series' read fraction.

## Goals / Non-Goals

**Goals:**

- One request per screen. Progress arrives with the entries; nothing is fetched
  per row to learn a number that was already in the payload.
- The server's shelves reuse the local shelves' cover code rather than growing a
  second composite.
- The reader who cannot see the artwork loses nothing: order, title and progress
  are all in the accessibility tree.

**Non-Goals:**

- Design-level: no image-loading library is introduced. The key problem that
  kept `KavitaSeriesCell` off Coil has not changed.
- No caching layer beyond what is described under Risks. A disk cache for server
  artwork is its own change.

## Decisions

**Progress comes from the list payload, not from a per-entry request.**
`pagesRead`/`pagesTotal` are already returned per entry, so the two fields are
added to `KavitaReadingListItem` and to its Swift twin, and the row reads them.
The alternative — asking `Reader/progress` per entry — costs one round trip per
row on a 77-entry list and answers the same numbers. `KavitaExchange.position`
(`core/kavita/KavitaExchange.kt:55`) already turns `pagesRead` into a
`ReadingPosition`, and `KavitaChapter.isFinished` (`KavitaLibrary.kt:123`)
already states the finished rule as `pages > 0 && pagesRead >= pages`; both are
reused rather than restated.

**"No read state" is `pagesTotal <= 0`, not `pagesRead == 0`.** Kavita sends
`pagesRead: 0` for an unread entry and the spec's failure scenario asks for
nothing to be claimed when the source reports nothing. A total of zero is the
only honest signal that the server has nothing to say; zero read of twenty-two
is a real answer and is drawn as unread.

**The quadrant drawing is extracted; `ShelfCover`'s signature is not touched.**
The tiles the server needs come from `Image/chapter-cover` through the client,
and the tiles a local shelf needs come from the library's own decoder. What the
two share is the *layout* — four quadrants, or one cover across the frame below
four — so that is what moves: a private composable taking the resolved artwork,
with two thin callers over it. `ShelfCover(tiles:viewModel:)` keeps its shape
and every local call site is untouched; `ServerShelfCover(tiles:load:)` is new
and fetches through the client, as the entry poster does. iOS mirrors it, with
`ShelfCover(model:tiles:)` left alone beside a new `ServerShelfCover`.

Alternative considered and rejected: giving `ShelfCover` a cover-source
parameter in place of the view model. It rewrites every existing local call site
and pushes the library's own "re-ask as the scan grows" effect out to callers
that do not need to know about it, to gain nothing the extraction does not.

`coverImageLocked` from the list payload is the "unless the user sets a specific
one" clause: when it is true the server's own `coverImage` wins and no composite
is built. Also considered: always use Kavita's `readinglist-cover` route.
Rejected because Kavita generates that from the first entry alone, which is not
the four-tile composite the spec describes and not what a local list shows
beside it.

**The entry poster is the chapter's cover at the library's aspect and
rounding** — 2:3 in a `StoryArcRadius.md` surface, as `KavitaSeriesCell` draws
it. A row is 48 dp minimum today; the poster sets the row height instead, and
the number moves to the leading edge of the poster rather than being displaced
by it.

**Platform APIs.** Android: Jetpack Compose from the version catalogue
(`androidx.compose` BOM as pinned in `gradle/libs.versions.toml`),
`BitmapFactory.decodeByteArray` as `KavitaSeriesGrid.kt:57` already does, no new
dependency. iOS: SwiftUI on the deployment target `project.yml` sets, `UIImage`
from `Data`, no new package. Both are verified present in the tree, not assumed.

**Accessibility.** The poster is decorative and carries no description of its
own; the row merges its descendants into one label that names the position, the
title, the series and the progress, as `KavitaSeriesCell` already merges its
own. Progress is never colour alone — the percentage or "finished" is in the
label and in the visible text, so the list is usable at any contrast setting and
by a reader who cannot distinguish the bar. The list's summary ("14 of 18
finished") is a single node ahead of the rows rather than a per-row aria fact,
so a screen reader hears the shape of the list before its contents.

## Risks / Trade-offs

- **77 bitmaps on one screen.** A long list fetches a cover per visible row and
  decodes it. → Fetch inside the row composable keyed by `chapterId`, as the
  series grid does, so only visible rows fetch; decode at the displayed size
  rather than full resolution. If memory is still a problem the answer is a
  bounded cache in `KavitaClient`, which is a smaller change than an image
  library.
- **Four extra requests per shelf tile.** A screen of ten server shelves fetches
  forty covers to composite them. → The tiles are the *first four* entries, and
  the fetches are the same `Image/chapter-cover` calls the rows make. The list
  payload names the entries only once the list has been read, so a shelf card
  asks the server for its list before it can composite; that read is one request
  per shelf and is what `itemCount` on the card already needs.
- **Two composites drifting apart.** Extracting the layout is what prevents it,
  and the local shelves' existing cover tests are what prove the extraction did
  not change them.
- **`coverImageLocked` may not exist on an older server.** → It is decoded with
  `ignoreUnknownKeys` and defaults to false, so an older server composites,
  which is the behaviour it has today plus artwork.
- **Progress the server has and the device disagrees about.** A local position
  pulled by `KavitaSync` can be ahead of `pagesRead`. → Out of scope: this change
  draws what the list endpoint returned. `kavita-server` owns reconciliation, and
  drawing the server's own number is what the other Kavita screens already do.

## Migration Plan

None. No stored data changes shape: the two model widenings are additive fields
on payloads that are already decoded with unknown keys ignored, and nothing
persisted gains or loses a column.
