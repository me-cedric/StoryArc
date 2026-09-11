# A shelf of issues, and a rail to scan it

**Platforms: both.** One capability, `library-browsing`, and one screen. iOS puts
both controls in the `ViewMenu` it already draws; Android puts the first on the
chip row it already draws and the second down the trailing edge of the shelf.

## Why

The library collapses issues into a series cell. A reader with two issues of
*Superman Batman (2003)* sees one cell reading "2 titles", and the owner asked
for the other view back: each issue, as its own cell. The collapse is right for
sixty series of twenty issues and wrong for a reader who came to find issue #7,
so it has to be a choice rather than a rule.

The data is already there. The library holds one `Publication` per issue and
groups them for display only — `LibraryRows.of` on both platforms. So this is a
presentation switch over rows the app already computes, not a new fetch.

The second half is what makes a long shelf usable once it stops collapsing.
Turning off the collapse turns sixty cells into twelve hundred, and the sections
this repository already draws are headings without a way to jump between them. An
index down the side is the way, and Kavita's own client has one.

An index can only point at letters, and the library offers seven sort orders.
Only *Title* and *Series* file a row under a letter. **Under the other five the
index is absent, not disabled.** Three reasons, in the order they decide it:

1. Nothing to point at. Under *last read*, *progress*, *date added* and *size on
   this device* the shelf divides into nothing at all — `LibrarySections` returns
   no sections, by a decision this repository already argued: "a heading over a
   continuum is an invented boundary". *Year* divides, and a year is not a letter.
2. An inert control is not free. It takes a strip down the edge of the artwork,
   and `AGENTS.md` §2, non-negotiable 5, says the artwork is the interface.
3. A screen reader has to step over it. A control announced and then refusing
   every action is worse than one that is not there, and the shelf already hides
   its headings under the same five sorts — so hiding the index follows a rule the
   shelf follows already, rather than inventing a second one.

## What Changes

- **The shelf offers series or issues.** A named choice beside the other view
  choices, stating which of the two is showing. Series stays the default, because
  the owner reversed the first build to get it.
- **The choice reaches both layouts.** The grid and the compact list draw the same
  rows, and a row standing for a series opens the series in either. Today the
  Android list draws series rows that open the first issue and leave the rest
  unreachable, and the iOS list quietly lists issues whatever the reader chose —
  two platforms answering one question three ways.
- **A long shelf sorted by title or by series carries an index down its trailing
  edge.** One entry per letter the shelf actually files a row under, in the
  shelf's own order, with `#` for the rows no letter claims. Choosing an entry
  moves the shelf to the first row under it.
- **Under the other five sorts there is no index.** Stated as a scenario, so
  nobody later reads its absence as a defect.
- **The index is operable without sight.** One named group, one announced letter
  per entry.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `library-browsing`, the **Presentation** requirement. Its *A series is one row*
  scenario says the collapse happens, full stop; it now says it happens while the
  shelf is grouped by series. Three scenarios are added for the choice and for
  what the two layouts owe each other, and three for the index — the one it draws,
  the five sorts that draw none, and what a screen reader hears.

## Impact

- `apps/android/feature/library`: `LibraryGrouping.kt` and `LibraryRail.kt` are
  new. `LibraryRows.kt`, `LibraryControls.kt`, `LibraryScreen.kt`, `CoverGrid.kt`
  and `CoverList.kt` change. `KavitaSearchOffer.kt` is a lift out of
  `LibraryScreen.kt`, which sits one line under the 800-line cap.
- `apps/android/core/persistence`: one more key in `LibraryPreferences`.
- `apps/android/feature/library/src/main/res/values{,-de,-es,-fr}`: five strings.
- `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature`: `LibraryRail.swift` and
  `LibraryTitles.swift` are new — the second a lift out of `LibraryView.swift`,
  which sits three lines under the 400-line cap. `LibraryFacets.swift`,
  `LibraryContent.swift`, `LibraryBrowsingControls.swift`, `LibraryView.swift` and
  `CoverList.swift` change, and the module's `Localizable.xcstrings` gains the same
  five strings in the same four languages.
- No model change on either platform. The choice is a screen preference beside
  `DownloadFilter`, not a field on `LibraryQuery` — `DownloadFilter`'s own comment
  sets out why, and a case on `LibraryQuery` is a change to `:core:model` and to
  `StoryArcCore` for a value only one screen reads.
- No migration. A reader who has never chosen gets series, which is what they see
  today.

## Non-goals

- **A four-state layout enum.** Grid-or-list and series-or-issues are two axes.
  One enum of four states would make every future layout question a multiple of
  the other.
- **Dragging along the index.** A tap jumps. A continuous drag is a gesture that
  exists nowhere in either app, and the tap is what the owner asked for.
- **The index on the reading-list screen.** A curated order has no sort key at
  all, so it files nothing under a letter. The library shelf only.
- **The index on search results.** Results are already grouped by why they
  matched, and a second structure across the first is two answers to one question
  — the same reason the sections stay off search.
- **A wider index that draws whole series names.** That is a different control,
  and it is not what "A-B-C-D" asks for.
