# Android's empty state, before and after, 2026-09-08

A physical OnePlus 7T Pro (`HD1911`), Android 14, API 34, 1440 by 3120. The app's data was
cleared with `adb shell pm clear app.storyarc.debug` before every frame, so each is a genuine
first launch. Captured with `node scripts/capture-android.mjs <Home|Library> --out <path>`.

## The defect

The owner reported that home and the library drew the same empty state differently. They did.

| | Home, before | Library, before |
| --- | --- | --- |
| Vertical | Top-anchored, under the title | Centred in the remaining room |
| Horizontal | Left-aligned | Left-aligned |

Sharing one composable stopped the words and the actions drifting, and left the placement to
each caller. Home drew it as a `LazyColumn` item, which lays out at the top. The library drew
it inside `Box(contentAlignment = Alignment.Center)`. On this phone the two blocks sat about
400 pixels apart.

iOS was already correct: `EmptyLibraryView` is one `ContentUnavailableView` drawn by both
surfaces, and it centres on both axes for free. So the two platforms disagreed as well.

## After

Measured from the pixels, not by eye. In both `android-home-empty.png` and
`android-library-empty.png` the ink spans rows 395 to 1940 and its centre is row 1167.
Identical.

Two changes made it so. The composable now states its own alignment, so no caller can place
it differently. And home stops adding the shelf's extra bottom inset when the shelf is
bare — that inset is breathing room under the last cover, and on a centred block it moved the
middle up by half of `xxl`, which was 55 pixels of disagreement left after the first fix.

`EmptyStateIsPlacedTheSameTest` guards all three lines.
