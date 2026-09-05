# The six presets at the largest text size — iOS, 2026-09-05

`reader-theming-and-page-transitions` §7.4 asks for the theme sheet and all six presets "in
light and dark, at default and largest text size". The sweep of 2026-09-02 took the presets at
the **default** size only (`ios-sweep-2026-09-02/ios-epub-theme-presets{,-dark}.png`), so the
largest size — the one the task exists for — had never been photographed on iOS. These are it.

Taken on `StoryArc-iPhone17Pro` (402 pt wide) with
`SweepEpubReaderTests/testCaptureEpubThemePresetsAtLargestText` at
`UICTContentSizeCategoryAccessibilityXXXL`.

| Frame | What it shows |
| --- | --- |
| `ios-epub-theme-presets-ax5-before.png` | The defect: three fixed columns, *Original* broken as `Origi-` over `nal` |
| `ios-epub-theme-presets-ax5.png` | After: one column, every name whole |
| `ios-epub-theme-presets-ax5-dark.png` | The same in dark |

## What the first frame found

The grid was `Array(repeating: GridItem(...), count: 3)` — a **fixed** three columns at every
text size. On a 402 pt phone that leaves each card about 170 pt, which holds every preset's
name at the ordinary sizes and holds none of them at the accessibility ones. *Original* wrapped
mid-word.

**A preset card is the one control in this app whose label may not shrink to fit.** The whole
point of the grid is that each name is drawn in its own typeface at its own weight — that is
what `ebook-reader` means by "six samples, not six labels" — so shrinking the name to make it
fit would be showing the reader the wrong typeface, which is the thing being chosen.

One column rather than two at those sizes: two still leave roughly 170 pt against a name
needing about 250 pt, so two would have moved the wrap without preventing it.

`ThemePresetGridTests` asserts the rule across every `DynamicTypeSize` — one column at all five
accessibility sizes, three at all seven ordinary ones. The second half matters as much as the
first: a rule that answered 1 everywhere would satisfy the defect and quietly throw the layout
away for every reader who has not raised their text size.

## A second finding, recorded and not fixed

**At this text size the presets sit below the fold.** The sheet opens on *Preview* with
*Themes* only beginning to appear at the bottom edge, so a reader must scroll to reach the grid
at all — and the first version of this walk photographed the fold rather than the tiles.

That is not obviously wrong: the preview is what a preset changes, so showing it first is
defensible, and the sheet scrolls. It is recorded because nobody has decided it. The walk
scrolls to the grid rather than resizing the sheet, so these frames show what a reader would
actually see after one swipe.

## A third finding: one of the two theme-sheet walks cannot reach the sheet at this size

`ScreenshotTests.testCaptureThemeSheetAtLargestText` **fails** at `AccessibilityXXXL`, in both
appearances, with `XCTAssertTrue failed - the reader revealed no menu to open`. Its sibling
`SweepEpubReaderTests.testCaptureEpubThemePresetsAtLargestText` — the walk that took the frames
above — reaches the same sheet at the same text size in the same run.

So the sheet is reachable and the app is not at fault; the older walk is. Left failing rather
than quietly repaired, because which of the two is wrong is worth deciding rather than
patching: they photograph the same surface from two files, and the sweep's version already
asserts more before its shutter.

That is why `reader-theming-and-page-transitions` §7.4 stays `[~]` — the **sheet** at the
largest size is still unphotographed on iOS, even though the **presets** at that size now are.

## How to retake them

```bash
for appearance in light dark; do
  node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-theme-presets-2026-09-05 \
    --only "SweepEpubReaderTests/testCaptureEpubThemePresetsAtLargestText" \
    --appearance $appearance
done
```

Read the run summary rather than the exit code: `xcodebuild` exits 0 when a `-only-testing:`
filter matches nothing, and each run should print `1 test case(s): 1 passed, 0 failed, 0
skipped`. The `0 skipped` matters as much as the `1 passed` — a walk that skips passes and
photographs nothing.
