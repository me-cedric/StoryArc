# Shelves, marks and the by-library filter — Android, 2026-09-12

Frames for three tasks of `one-library-three-destinations`, taken on `emulator-5554`
(1080 × 2400, Android 16) with `node scripts/capture-android.mjs`. They were taken during a
`source-lifecycle` device pass and first landed in that change's folder; they are here because
a folder named for one change should not hold another's evidence.

The state behind all of them is two mock OPDS catalogues registered by
`scripts/seed-android-sources.mjs`, plus a collection and a reading list made by hand.

| Frame | Task | What it shows |
| --- | --- | --- |
| `android-four-marks-{light,dark}` | 3.3 | all four combinations of progress and availability in one screen, sorted by *Last read* |
| `android-filter-libraries-{light,dark}` | 3.2 | the filter sheet open on *Which library*, which is drawn only when more than one source has put something on the shelf |
| `android-filtered-to-one-{light,dark}` | 3.2 | the shelf narrowed to *Attic Catalogue*, the control reading **1 filter active** |
| `android-clear-filters-{light,dark}` | 3.2 | *Clear filters* offered while the shelf is narrowed — the way out |
| `android-home-shelves-blank-before` | 3.3 / the defect below | Home listing a collection and a reading list, both drawn as **blank white frames** |
| `android-home-shelves-named-after` | the fix | the same surface after it: each shelf carries the placeholder a publication with no cover carries |
| `android-home-shelves-dark` | 2.1 | Home's shelf sections in dark |

## The defect the before-and-after pair holds

`collections-and-reading-lists` says a shelf whose members have no artwork "shows the same
placeholder a publication with no cover shows", and that it is "never drawn as an empty
frame". It was an empty frame: `ShelfComposite` drew a filled rectangle, so a collection of
one coverless book was a white tile with its name only underneath it.

Found twice on 2026-09-12 and by two routes — by an agent reading `ShelfCover.kt:381` against
the delta, and by this capture. The Android half is fixed: the composite draws `CoverlessWell`
when none of its members' covers arrived, and the shelf's name travels with it.

**The iOS half is not fixed, and the reason is an API rather than an oversight.** iOS's
`CoverlessWell` takes a `PublicationFormat` and draws a glyph for it; a shelf has no format to
give it. Closing that needs a decision — a formatless initialiser, or the first member's
format — and it is recorded as a task rather than guessed at here.

## What the four-marks frame measures

Sampled from `android-four-marks-light.png`: the available well is `rgb(233, 230, 227)` and
the away well `rgb(236, 233, 230)`. The dim is about one percent, and the away one is
*lighter*. `AWAY_ALPHA` is 0.45 and does what it says — it is applied to a coverless well,
because a row from an OPDS catalogue draws no cover at all. That second finding is task 3.6 of
`one-library-three-destinations`.

So on this shelf the **accessibility label is the only thing that carries the state**:
*Ashfall, Ada Lovelace, CBZ, Needs its library to be reachable* against
*Ashfall, Ada Lovelace, CBZ*.
