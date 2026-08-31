# The second batch of 2026-08-31, after

Same devices and same commands as [`before-2026-08-31b/`](../before-2026-08-31b/README.md),
which carries the setup and the caveats. This is what changed.

## What each pair proves

| Pair | Before | After |
| --- | --- | --- |
| `ios-downloads` | Foreign Codec, Harbour Lights 01 and Harbour Lights 02 are black rectangles. Three of the nine cells on screen say nothing about the book they stand for. | Each draws the well the library has drawn all along: the title as stand-in artwork, the format underneath. `Foreign Codec` and `CBZ`, exactly as the library shows them one tab away. |
| `ios-library` | — | Unchanged, and that is the point. The library's cell now asks for a shared well instead of writing its own, and the two shots differ only in the clock. |
| `ios-home` | — | Unchanged too. Home's well lost its own copy of the same code; its padding is now derived from whether a format is named rather than set separately, and the visible result is the same. |

## What was actually wrong

Three surfaces draw a cover-shaped well: the library's grid, Home's shelf, and the downloads
destination. `CoverlessWell.swift` already shared **the rule** about what a well does as the
reader's text grows — its own comment calls the two copies it replaced "two wells, one
defect" — but it shared only the rule. The view was still written out twice, and the third
surface had never had one at all.

So the file now owns the well itself, and the surfaces ask for it. The one thing that
genuinely differs between them is whether the format is named, and the layout follows from
that rather than from three separate opinions: a well that names a format keeps its title
clear of the label at the bottom, and a well that does not simply centres it.

## Why nothing caught this

Worth writing down, because the same blind spot will produce the same kind of defect again.

The well is `accessibilityHidden` and the caption below the cell carries the title, so the
screen reads correctly to VoiceOver whether or not anything is drawn in the box. Apple's
audit has exactly one finding on Downloads and it is about contrast. Android's own scanner
*did* see it — as `UNNAMED View` and `SMALL View 114.3x14.1dp` in `pnpm smoke:android:a11y`
— because it measures boxes rather than labels, and nobody had connected that line to a
missing placeholder.

A defect invisible to every automated check and obvious to anyone looking at the screen is
the case §6 of [`AGENTS.md`](../../../AGENTS.md) asks for a screenshot to catch. It went
unnoticed until someone photographed the screen for an unrelated reason.

## Still open on these screens

The Android half of the same defect. `OnDeviceCover` in
`apps/android/app/src/main/kotlin/app/storyarc/DownloadsParts.kt` has the identical empty
box, and the library's `CoverCell` is private to `:feature:library` — so the fix is the same
shape as the iOS one and was blocked on another change already moving code in that file.
Recorded in [the delivery note](../../../delivery/remaining-work-2026-08-31.md).
