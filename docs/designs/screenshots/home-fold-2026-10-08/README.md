# The next heading above the fold on Home, 2026-10-08

Task 0b.4 of `one-library-three-destinations`, with owner answer O17: shrink the cover on a
compact height so the next heading shows. Do not accept the heading below the fold.

## Android

Pixel 6a emulator, API 33, debug build, gesture navigation, light. One book in progress (*The Long
Field*) so Home draws the Keep reading card, with Recently added under it.

| Frame | Window | Text size | What it shows |
| --- | --- | --- | --- |
| `android-home-411x914.png` | 411 x 914 dp | default | The *Recently added* heading is whole above the navigation bar. |
| `android-home-360x800.png` | 360 x 800 dp (`wm density 480`) | default | Same, with a shorter cover box. The card stays 200 dp wide and *Resume* stays on one line. |

### What the first frames found

The task predicted a pass at 411 x 914 and a 4 dp miss at 360 x 800. Both frames showed the heading
cut by the navigation bar. The height model put the card 74 dp too high: the card starts 242 dp from
the top, and the model said 168. From the card's bottom edge to the bottom of the next heading's text
the frame measures about 66 dp, and the model said 56. `HOME_CHROME_DP` is now 324 and
`HOME_NEXT_HEADING_DP` is 68, both measured.

A narrower card is not the fix. A first try took the card to 138 dp wide on the small phone, and the
frame showed *Resume* wrapped as "Resu / me". So the card keeps its 200 dp floor and the cover box
gives up height (`homeHeroArtHeight`). The cover is letterboxed in the shorter box, not cropped.

## iOS

iPhone 17 Pro simulator, iOS 26.4, 402 x 874 pt, light. *Fine Print* is read for one page, so Home
draws the Continue reading card. `SweepHomeFoldTests` takes the frame.

| Frame | Text size | What it shows |
| --- | --- | --- |
| `ios-home-fold.png` | default | The *Recently added* heading is whole above the tab bar, with about 60 pt to spare. The card is the one emphasis. |

The task predicted a pass on iOS by arithmetic. The frame confirms it, so iOS needs no change.
The card is 1.25 times its width and the window is tall enough. A 375 x 812 pt phone has about 35 pt
to spare by the same arithmetic. That is a calculation and not a frame.
