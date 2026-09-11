# Design

## The choice is a third boolean on a gate that already exists

Both platforms already refuse to collapse a series twice, for two reasons each.
iOS:

```swift
guard model.matchGroups.isEmpty, !selection.isActive else { return [] }
```

Android:

```kotlin
if (isGrouped || isPicking) { ShelfRows(publications, emptyMap()) }
```

An empty row set already means *list every publication* on both platforms —
`shelved` falls back to `shown` on iOS, and Android hands `publications` straight
through. So the issues view is the third reason to take that branch, and nothing
downstream changes: the series count on a cell comes from a map lookup that finds
nothing, the cell's title falls back to the publication's own, the sections are
cut from the list that is drawn, and the index is computed from the same list.

That is the whole of Feature A on the model side. It is one parameter on each
gate and one term in each condition.

## Where the choice is held

`LibraryGrouping`, a two-case enum in the library **feature** module on both
platforms — `feature/library/LibraryGrouping.kt` and the tail of
`LibraryFacets.swift`, beside `DownloadFilter`. Not a case on `LibraryLayout`:
grid-or-list and series-or-issues are two axes, and a four-state enum makes the
next layout question a multiple of this one. Not a field on `LibraryQuery`
either, for the reason `DownloadFilter` gives in its own comment — the query is
the value both platforms encode, and a field on it is a change to `:core:model`
and to `StoryArcCore` for a value one screen reads.

Persisted by name, globally rather than per scope:

- Android: `LibraryPreferences.grouping()` / `saveGrouping(String)`, the shape
  `downloadFilter()` already has, plus `rememberSaveable` in `LibraryScreen` so a
  rotation does not read the disk.
- iOS: `@AppStorage(LibraryGrouping.storageKey)` in `LibraryView`, the shape
  `DownloadFilter` already has.

Global, not per scope. The layout is per scope because a dense list suits one
library and not another; how a reader wants a series presented is a habit, not a
property of a source. One key, no scope plumbing.

`LibraryView.swift` is 397 lines against a 400-line cap and cannot hold the new
`@AppStorage` declaration with its comment. `title` and `selectionTitle` — what
the navigation bar calls this surface — move to `LibraryTitles.swift`. Android's
`LibraryScreen.kt` is 799 against 800; the private `KavitaSearchOffer` composable
at its foot moves to `KavitaSearchOffer.kt`. Both are lifts of a whole
declaration with its documentation, not deletions.

## The control

iOS: one more `Picker` inside `ViewMenu`, between the layout picker and the sort
picker, with its own `Divider`. The menu is already the named home of *what is
shown, how it is grouped, how it is sorted* and the requirement asks for exactly
that grouping.

Android: one more chip in `LibraryControls`' `FlowRow`, built from `SortChip` and
not from `LayoutToggle`. `SortChip` is a boxed `FilterChip` with a `DropdownMenu`
under it and `Role.RadioButton` on every row; `LayoutToggle` is an unlabelled
`IconButton`, which is the shape the grouping rule exists to prevent. The chip's
label is framed the way `sortChipLabel` frames the sort — `Grouping: Series` —
so the reader cannot mistake it for a filter.

## The index

### What it points at

Sections are the wrong source. A section title is a series name, a letter, a year
or one translated word for the unplaceable, and a rail of series names is a
different control. So the index is computed from the drawn list directly, by a
pure twin on each platform:

```
LibraryRail.of(publications, sort, locale) -> [RailEntry(label, publicationID)]
```

- `.title` → the first character of `LibraryIndex.sortKey(displayTitle)`, which is
  the key the shelf is *ordered* by. Reading the raw title would file *The
  Sandman* under T in the middle of the S run.
- `.series` → the first character of `LibraryIndex.sortKey(seriesName)`, and `#`
  where the publication names no series. `compareBySeries` puts every
  series-less publication after every series, in one pile, so those rows are one
  contiguous `#` run at the end rather than a second alphabet interleaved.
- the other five → no entries at all.

A non-letter first character is `#`, uppercased for the reader's locale — the rule
`LibrarySections.initial` already applies, for the reason it already gives.

Entries are the **distinct labels in first-appearance order**, each carrying the
id of the first publication under it. That is monotone by construction under both
sorts, because the shelf is ordered by the same key the label is read off.

### When it is drawn

Three conditions, all of them reusing something that exists:

1. The sort files rows under letters — title or series.
2. The list is longer than `LibrarySections.threshold`, the existing definition of
   "more rows than a reader can scan". Not a second threshold.
3. More than one entry. A one-letter index moves the shelf nowhere.

The shelf surface only, not Downloads and not search, for the reason the sections
already stay off search.

### How the jump happens

iOS needs no index arithmetic. `ScrollViewReader` wraps the three shelf branches
in `LibraryContent.content` once, and `proxy.scrollTo(publicationID, anchor: .top)`
reaches a `ForEach` row in the grid, in the sectioned grid and in the `List`
alike. The pattern is `ThumbnailStrip`'s, already working in the reader.

Android has no proxy, so a letter's target is an **item index** and the index has
to count what the grid puts around the cells: an optional full-span
continue-reading row, a sticky header per section, and a full-span *more from
this library* row at the foot. One pure function, so a test can hold it rather
than a screenshot:

```kotlin
internal fun itemIndexes(
    publications: List<Publication>,
    sections: List<LibrarySection>,
    leading: Int,
): Map<String, Int>
```

`leading` is 1 when the continue-reading row is drawn and 0 when it is not. The
compact list needs none of this: its `LazyColumn` draws one item per publication
and the index is the position. The jump itself is
`state.animateScrollToItem(index)`, the call `feature/reader`'s `Paging` already
makes.

`CoverList` on Android has no hoisted scroll state today. It gains a
`rememberLazyListState()` and passes it to its `LazyColumn`, which is what the
overlay needs and nothing else.

### How it is drawn, and how it is heard

A `Column` / `VStack` on the trailing edge, inside the shelf's own overlay so the
covers keep the full width. Each entry is a button of its own with a minimum
22 pt / 22 dp height and a centred single character.

Accessibility is the part that is not optional:

- The rail is one traversal group with a name — *Alphabetical index* — so a
  screen reader announces it once rather than announcing twenty-seven unexplained
  letters.
- Each entry carries a spoken label of its own, *Jump to S*, because the drawn
  glyph is a single character and a single character is not an instruction.
- Every entry is a real button on both platforms: `Button` on iOS,
  `Modifier.clickable` with `Role.Button` on Android. Neither is a tap target
  painted on a decoration.
- The letters are never the only statement of anything. The shelf's own section
  headings say the same thing in the content, and removing the index removes no
  information.

## What the compact list owed the grid, and now pays

Three answers to one question exist today:

- Android hands `CoverList` the **collapsed** list, and `CoverList` knows nothing
  about series — so a row standing for *Superman Batman* opens issue #1 and the
  other nineteen are unreachable in that layout.
- iOS hands `CoverList` the **uncollapsed** list, so its list always showed
  issues whatever the grid showed.
- The grid, on both platforms, collapses and opens the series.

Both lists now take the same rows the grid takes and the same two arguments the
grid takes — `seriesRows` and the way to open a series. `CoverCell` and
`ListRow` then answer identically, which is what the amended scenario's last
clause asks for. This is not scope creep: the existing *Opening a series*
scenario already requires a series to open, and one of the two layouts could not.

## Versions

No new dependency on either platform. Android: Compose BOM and material3 as
pinned, `LazyListState` and `LazyGridState` from `androidx.compose.foundation`.
iOS: SwiftUI's own `ScrollViewReader`, available far below the iOS 26.1 floor.

## A row is not a publication, and counting them as one raised a false alarm

A branch report on 2026-09-11 said the shelf "is not drawing what the library
holds": six covers on screen against twenty-five publications in
`Library/Caches/library.json`, with fourteen CBZ and one PDF apparently missing.
It was offered as the more serious of three findings.

**It was measured, and there is no defect.** On a clean iPhone 17 Pro simulator
holding exactly those twenty-five publications:

| Grouping | Rows drawn |
| --- | --- |
| Series | 16 |
| Issues | every publication, `Harbour Lights 01`, `Tidal Reach #1` and the rest |

Sixteen is the arithmetic, not a coincidence: the twenty-five publications carry
sixteen distinct series names and not one of them is series-less, so series
grouping must draw sixteen rows. CBZ is present throughout — *Ashfall · 2 titles*,
*Copper Wake · 4 titles*, *Fine Print · CBZ* — and no publication is outside a
row, so nothing is hidden.

The report's own device is the explanation. That measurement was taken while its
author had moved `Documents/Sea Room` and the `seed-sea-room` download record
aside and had edited the progress store with `sqlite3`, to make a separate
before-and-after deterministic. The shelf was answering honestly about a library
somebody was holding open at the time.

**The lesson is for this change rather than for that branch.** This change made a
row stop meaning a publication, and the first person to compare the two numbers
read the difference as loss. The count beside a series name is what says
otherwise, so it is not decoration: `2 titles` is the sentence that makes sixteen
rows and twenty-five publications the same statement.

## Risks

- **A rail of twenty-seven entries on a small phone.** 27 × 22 dp is 594 dp, which
  fits a portrait phone's shelf and does not fit it at the largest text size with
  chrome. The entries are fixed-height and the column is centred, so the rail
  clips rather than pushing anything; a shelf holding every letter is also the
  shelf that needs the rail most. Measured on a device in task 5, and the frame is
  the proof.
- **`animateScrollToItem` against a grid that has not laid the target out.** The
  call is safe on an index past the laid-out window — that is what it is for — but
  iOS's `scrollTo` is not always, which is why `SettingsHighlight` waits 120 ms
  before its own. If a jump misses on a cold grid, the fix is that wait and not a
  redesign.
- **The two sibling deltas.** `every-source-is-the-library` and
  `one-library-three-destinations` hold the same `Presentation` block. All three
  now hold one identical block, word for word, so the order they sync in cannot
  matter. `pnpm delta:drop` reports the pair the moment one drifts.
