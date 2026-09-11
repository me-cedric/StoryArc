# The *Page turn* row, reached by a run — 2026-09-11

Three frames from an iPhone 17 Pro simulator, iOS 26.5, build `d102112d`.

`one-vocabulary-in-four-languages` task 4.2 renamed the comic reader's transition
row to `reader.transition` — *Page turn* — and edited the two UI walks that reach
it by its label. Task 6.5 recorded the gap that left: "They compile; no run has
reached the row."

**A run has now reached it.** `SweepComicReaderTests` and `CurlWalkTests` pass 11
of 11 together, and these are the frames:

| Frame | What it shows |
| --- | --- |
| `ios-comic-reader-menu.png` | the reader's menu, **Page turn · Curl** under *Settings* |
| `ios-comic-reader-menu-ax5.png` | the same menu at the largest accessibility size |
| `ios-comic-reader-transition-picker.png` | the picker the row opens |

The row reads *Page turn* and its value reads *Curl*, so the renamed key resolves
and the element the walks look for by label is the element on screen.
`SweepWalk.swift` records why the lookup is not an exact-label match: the element
is called `Page turn, Slide`, because a menu row states its name *and* its current
setting.

## What this does not close

Task 6.5 asks for every capture from **1.7, 2.4, 3.4 and 4.6** with its control.
Only the frame that task 4.2 added is here. 4.6 waits on `publication-detail`
archiving, because that page's requirements are still in its delta and not in a
main spec, so the captures under it cannot be judged against anything yet.

**No dark frame.** `capture-ios.mjs --appearance dark` was run and wrote no
`-dark` file for this walk. Why is not established, and the light frames are not
labelled as if they were both.
