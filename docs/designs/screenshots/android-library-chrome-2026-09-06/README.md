# The library's chrome under Material You — Android, 2026-09-06

Four frames from `storyarc-j6` (1080 × 2400, 411 × 914 dp, `-gpu host`), taken with
`scripts/capture-android.mjs` with the appearance settings at their defaults, so dynamic colour
is on and the scheme is the emulator's wallpaper. The 2026-09-05 design review's finding 10:
*library icon buttons override Material You with the brand accent*.

| Frame | Route | What to look at |
| --- | --- | --- |
| `android-library.png` | `Library` | The **+** and **⋮** in the top bar take the scheme's primary, the same colour as the selected tab's label and the text buttons |
| `android-library-dark.png` | `Library --dark` | The same, dark |
| `android-library-selection-two.png` | `Library > selection two` | The **×**, the download and the **⋮** of the selection bar, and the two picked ticks, all on the scheme's primary |
| `android-library-add-source-menu.png` | `Library > add source menu` | The **+** that opened the menu, and the menu's own icons |

## What was wrong

`docs/design.md` §7 ranks Material You above the brand for Android surfaces outside a
publication's context when dynamic colour is on, and `native-experience`'s *Android dynamic
colour* scenario says the scheme derives from the wallpaper by default. The text buttons on
these screens honoured that; the icon buttons beside them were hand-tinted `palette.accent` at
their call sites — `LibraryTopBar`, `AddSourceMenu`, `ShelfBulkActions`, `LibraryControls`,
`LibrarySelectionTopBar`, `CoverGrid`'s pick mark and the back chevrons — so a violet **+** sat
over a wallpaper-blue screen. The review photographed it as a violet back chevron over a
wallpaper-navy player.

Every chrome call site now reads `MaterialTheme.colorScheme.primary`. On the brand schemes
nothing moves, because their `primary` *is* `brand/accent` (`Theme.kt`); on the dynamic path the
icons agree with the label and the buttons beside them, which is what these frames show.
`BulkSelectionChromeTest` rasterises the selection bar under a scheme whose primary is a colour
the brand never uses and asserts the icon pixels carry it.

## What these frames do not show

A *before* pair. The parent of `65af6a18` would have to be installed to take one; the review's
`android-player-2026-09-04` frames carry the violet chevron over the wallpaper-navy player, and
are the before this change was measured against.

## How to retake them

```bash
C=docs/designs/screenshots/android-library-chrome-2026-09-06
node scripts/capture-android.mjs "Library" --out $C/android-library.png
node scripts/capture-android.mjs "Library" --out $C/android-library-dark.png --dark
node scripts/capture-android.mjs "Library > selection two" --out $C/android-library-selection-two.png
node scripts/capture-android.mjs "Library > add source menu" --out $C/android-library-add-source-menu.png
```

Dynamic colour must be on in the app's own Appearance settings, which is its default.
