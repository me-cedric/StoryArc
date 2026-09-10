# The navigation inset, paid twice — Android, 2026-09-10

Both frames are the **OnePlus 7T Pro** (`f7cee850`, Android 16, API 36,
1440×3120 at 560 dpi, gesture navigation), same screen, same server, dark, default
text size. Halved to 720×1560 for weight; nothing else is edited.

`android-list-dark-before.png` is build `75f1319f`. `android-list-dark-after.png`
is the same screen with the shell consuming the inset once.

## The measurement

Taken on the full-resolution captures by scanning rows for ink, not by eye:

| | last content row | bar band starts | gap |
| --- | --- | --- | --- |
| Before | 2727 | 2811 | 84 px = **24.0 dp** |
| After | 2731 | 2759 | 28 px = **8.0 dp** |

24.0 dp is exactly this device's gesture inset. The 8 dp that remains is the
list's own row spacing, not an inset.

## The report was the wrong way round, and so was this repository's own note

It was reported as content hidden *behind* the navigation bar, and
`server-shelves-2026-09-10/README.md` repeated it. Nothing was ever hidden:
`NavigationSuiteScaffoldLayout` measures the content at `layoutHeight - bar
height` and places the bar below it, so a row cannot be covered. What was
happening is the opposite — the viewport *ended early*, leaving a band of dead
background the width of the screen.

The cause is that the layout reserves the bar's **height** and does not consume
its **inset**. The modifier that consumes it,
`navigationSuiteScaffoldConsumeWindowInsets`, lives in `NavigationSuiteScaffold`
— the wrapper — and this app deliberately calls the bare layout instead, so that
the sync bar can sit above the control rather than inside it. Nothing else in
the app consumed it either: `consumeWindowInsets` appeared zero times in
`apps/android`. So the gesture inset was inside the bar's own height *and* still
reported to every hosted screen's `Scaffold`, which paid it again.

Two screens hid the symptom from themselves by discarding the Scaffold's bottom
padding and hard-coding 32 dp in its place — `DownloadsDestination` and the
unused `DestinationScaffold`. Both now read what they are given.

## Repeating the measurement

```bash
adb exec-out screencap -p > shot.png
```

Then scan rows from the bottom: the bar is a band of ink, above it the gap, above
that the last content row. At 560 dpi one dp is 3.5 device pixels.
