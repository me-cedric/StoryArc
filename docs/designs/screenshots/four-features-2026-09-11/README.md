# Four features, photographed — 2026-09-11

The library's grouping switch, the alphabetical index, and the two shelves Home
gained, on a `storyarc-ci` emulator (`emulator-5554`, 1080 × 2400, Android 16).
Changes: `a-shelf-of-issues-and-a-rail-to-scan-it`,
`home-lists-the-readers-shelves`.

**The device was seeded, and that is not a detail.** The shelf holds 140
publications from `node scripts/corpus.mjs --count 140`, pushed to the app's own
managed folder — `/sdcard/Android/data/com.mecedric.storyarc.debug/files`, which
`LibraryViewModel.managedFolder` documents as "what the emulator and the
instrumented tests scan without a picker". An emulator nobody seeds has an empty
shelf, and an empty shelf draws neither the chips nor the rail: there is nothing
to group and no letter to jump to. The first frames taken here were of *Nothing
here yet*.

## Series, or every issue

| Frame | What it shows |
| --- | --- |
| `android-grouping-menu.png` | the *Grouping* chip open, offering Series and Issues |
| `android-rail-light.png` | grouped by issues, sorted by title, light |
| `android-rail-dark.png` | the same, dark |
| `android-issues-light.png` | the same shelf, light |
| `android-issues-dark.png` | the same shelf, dark |

Grouped by **Series** a run is one cell reading *Ashfall · 2 titles*. Grouped by
**Issues** the same run is *Ashfall* and *Ashfall #2*, two cells, which is what
was asked for: a reader who wants one issue no longer opens the series to reach
it.

## The rail, and the column it cost

`android-rail-*.png` — the index down the trailing edge, reading
**A B C F G H L P Q S T**. Letters only where the shelf has one: the corpus has
no D and no E, and the rail says so rather than drawing a dead letter.

**Two frames were thrown away before these.** The rail is an overlay at the end
edge, and the shelf did not inset itself, so the third column was drawn
underneath it — the first captures show *Broken Transfer* and *Copper Wake #2*
cut off down the right edge. Reserving the rail's whole width on top of the
gutter fixed the clipping and cost a whole column: the same shelf fell from
three cells to two.

So the rail stands **in** the end gutter rather than beside it. The gutter is
empty margin, the rail is 36 dp and the gutter is 20 dp, and the end reserves the
wider of the two rather than their sum. Three columns, nothing clipped. `iOS`
carried the same defect and took the same fix, in `LibraryContent.swift`.

`android-rail-ax.png` is the shelf at **200 % text**. The chips reflow to three
rows, the shelf falls to two columns because the cells grew, and the rail is
still legible and still clips nothing.

## The two shelves on Home

| Frame | Theme |
| --- | --- |
| `android-home-shelves.png` | light |
| `android-home-shelves-dark.png` | dark |

**Collections** holding *Lantern Run*, and **Reading lists** holding *Summer
Reading*, each with a heading that leads to the shelves screen. Both were made
by hand on the emulator through *Shelves → New*, because a device with no
collection and no reading list draws neither shelf — which is the rule the
change states, and the reason the first Home capture showed only *Recently
added*.

A card is a cover-shaped blank with a count of zero. That is the change's own
decision, recorded in its `design.md`: the card is the shelf rather than its
contents, and a collection the reader just made must not vanish from the surface
they were on.

## Not shown

**The Kavita search that finds issues**, from `a-search-that-finds-the-issue`.
It needs a Kavita source with an API key and a library walk to fill the index.
The emulator has no server and the owner's key is not on it, so no frame here
proves it. `KavitaIssuesTest` and `KavitaIssuesTests` assert the join on both
platforms, eight cases each.

**The refresh line**, from `a-refresh-that-says-it-is-running`. It states that a
*source* is being checked, and this emulator has no remote source to check.

**iOS.** Every frame here is Android. The two changes are twins by ADR-0001 and
the iOS unit suites pass, but nothing on that platform has been photographed.
