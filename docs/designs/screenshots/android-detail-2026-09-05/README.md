# The publication page said its own name twice — Android, 2026-09-05

Three frames from `storyarc-j6` (1080 × 2400, 411 × 914 dp, `-gpu host`), taken with
`scripts/capture-android.mjs` against the `Publication page` and `Publication page > series`
routes. Condition **A** — the 17 publications `scripts/corpus.mjs` generates, in the app's own
external files directory, belonging to no source.

| Frame | What it shows |
| --- | --- |
| `android-detail-standalone-before.png` | The defect: **Broken Transfer** in the app bar, **Broken Transfer** again beneath it |
| `android-detail-standalone.png` | After: the title drawn once |
| `android-detail-series.png` | A publication that really has a series, reading `Tidal Reach #2` |

## What the first frame found, and it was not what anyone was looking for

This page was opened to settle a *layout* question — whether the hero takes too much of the
window on a publication with nothing to say. It does, and that question is still open. What the
frame settled instead was a defect nobody had reported: the page prints the title, and then
prints the series under it, and for a standalone publication those are the same string.

`Broken Transfer.cbz` has no metadata, so the indexer infers both its title and its series from
the filename. A page that draws one and then the other says the same thing twice.

## The rule already existed, in three places, and this page used none of them

That is the part worth recording. `seriesLine` has withheld a series line that only repeats the
title since the grid and list captions were written —
`feature/library/.../PublicationSeries.kt` — and iOS has had the same rule in
`SeriesLine.swift`, case-insensitive, for the same stated reason: *a title inferred from a
filename is often the series and the number joined back together*.

`DetailSubtitle` built its own line instead, out of `publication.series`,
`publication.number` and `publication.year`, comparing none of them to anything. So the app
already knew the answer and the page did not ask.

Two more callers were in the same position and are fixed with it:

- **`CatalogueDetailScreen`** drew `"$series #$index"` under an entry's title. Most OPDS feeds
  are generated from filenames, so most entries already read `Harbour Lights #1` as their
  *title* — and this line said it a second time on every one of them. iOS's `SeriesLine.swift`
  names this exact case in its own comment; Android had no equivalent.
- **`SearchResult.held`** put `publication.series` in a row's detail line, under the title. A
  standalone made the row repeat itself.

The rule now lives once, in `core/model/SeriesLine.kt`, with thin overloads for a publication
and a catalogue entry — the shape iOS settled on. It is in `core/model` rather than
`feature/library` because `SearchResult` is a model type and cannot see the feature module,
and because `PublicationSeries.kt`'s own comment warns that two copies of this rule disagreeing
would make the layout toggle change what a publication says it is.

## A wording change that came with it, deliberately

The page used to join the series and the number with its own separator — `Ashfall · #1 · 2024`.
Everything else in the app, and iOS, renders `seriesLine`'s `Ashfall #1`. Going through the
shared rule makes the page agree: `Tidal Reach #2` in the third frame, and
`DetailAbsencesTest`'s control was updated to assert the new form rather than the old.

## What is still open

**The hero's proportions on a degenerate page.** With no subtitle the app bar is shorter, the
room is larger, and the cover stays pinned at its maximum — the second frame shows the cover
and its one action filling most of the window above a single *On this device* line. That was
the question this capture was taken to answer and it needs a decision, not a fix.

## How to retake them

```bash
node scripts/corpus.mjs /tmp/corpus-android            # then push into the app's files dir
node scripts/capture-android.mjs "Publication page" \
  --out docs/designs/screenshots/android-detail-2026-09-05/android-detail-standalone.png
node scripts/capture-android.mjs "Publication page > series" \
  --out docs/designs/screenshots/android-detail-2026-09-05/android-detail-series.png
```

`--out` takes a **file path**, not a directory.

**Two traps this session hit, both of which produce a confident picture of the wrong thing.**
The emulator's System UI wedged into an *"isn't responding"* dialog that sat over every screen,
and `capture-android.mjs` reported the route as captured — the dialog blocks taps but not the
shutter. Check the frame, not the exit code. And a reinstall or a snapshot reload empties the
app's files directory, so the corpus has to be pushed again; the route helpfully says "this
device has no publication in the state it needs" rather than photographing an empty shelf.
