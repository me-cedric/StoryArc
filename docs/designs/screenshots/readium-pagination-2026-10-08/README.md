# Readium pagination on both platforms - 2026-10-09

Task 7.8 of `reader-theming-and-page-transitions`, owner answer O15. Book: `fixture.epub`
(*Fixture Publication*): two chapters, 40 paragraphs each, 2 lines per paragraph at the default
size. Devices: iPhone 17 simulator (iOS 26.4, 402 x 874 pt) and Pixel 9 Pro XL emulator (API 36),
the emulator set to 1206 x 2622 px at 480 dpi so both panels have the same width in pixels. Same
theme (Paper, Literata), default text size, no change to the nine axes.

## (a) Page counts

| | iOS | Android |
| --- | --- | --- |
| Chapter One | 4 pages | 4 pages |
| Chapter Two | 4 pages | 4 pages |
| First paragraph of each page of a chapter | 1, 11, 24, 37 | 1, 11, 24, 37 |

The page counts and every page break agree, so the column width does not differ at this width.
Frames: `ios-pages-chapter-1-and-2.png`, `android-pages-chapter-1-and-2.png`.

## (b) A stored position resumed on the other platform

Method: put `href` and one progression of Chapter One into each platform's progress store (the
two fields a sync carries), start the book, and read the first paragraph on the page. The store is
the SwiftData file on iOS and `progress.db` on Android. Frames: `ios-resume-by-fraction.png` and
`android-resume-by-fraction.png`. The first column is 0.05, then 0.26, 0.45, 0.52, 0.74, 0.76 and
0.95.

| Progression in Chapter One | 0.05 | 0.26 | 0.45 | 0.52 | 0.74 | 0.76 | 0.95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iOS first paragraph on the page | 1 | 11 | 11 | 24 | 24 | 37 | 37 |
| Android first paragraph on the page | 1 | 11 | 24 | 24 | 37 | 37 | 37 |
| Page that holds the fraction | 1 | 2 | 2 | 3 | 3 | 4 | 4 |

- **iOS opens the page that holds the fraction.** Android opens the **nearest page start**. At
  0.45 Android opens page 3 and the stored paragraph (about 18) is on the page before it. At
  0.74 it opens page 4 and the stored paragraph (about 30) is on page 3.
- **The gap is up to one page.** Here a page is 13 paragraphs, 26 lines. The largest gap seen is
  7 paragraphs, 14 lines, and Android is always the later one. A position that a platform
  stored itself is a page start, and resumes exactly on that platform. The gap shows when a
  fraction comes from a place with other page breaks: the other platform, another font size, a
  Kavita progress value.

## (c) One text-size step

Both platforms: resume at 0.5 of Chapter One (page 3, first paragraph 24), apply one step
larger from the theme sheet (Android shows 115% of the publisher's size), close the sheet.
Both open a page whose first paragraph is 23, which holds the old first paragraph, with 3 lines
per paragraph. The step moves the reader by the same amount on both. Neither platform wrote a
new position at once. Frames: `ios-one-step-larger.png`, `android-one-step-larger.png`.

## Decision, by O15

**The gap is larger than two lines, so it is not a bounded limit.** O15 asks for a finer stored
locator (the first visible element) through a reading-progress delta in
`reader-theming-and-page-transitions`.

- **Cause.** The gap is the rounding in the step from a fraction to a page offset (Android
  rounds, iOS does not). It is not the column geometry. Divergence 1 in the task text (the
  `--RS__viewportWidth` pin) changed nothing here: page counts and page breaks are equal. So
  **Android `--RS__viewportWidth` is not pinned.** The pin stays an open option for a device where
  `width / dpr` is not whole. This run cannot show it.
- **Why code did not start.** A locator with `cssSelector` helps one device with itself. For the
  gap between devices the selector must travel with `href` and the fraction, which changes what
  `reading-progress` and the Kavita push carry. `AGENTS.md` section 3b says to specify before
  building, and this lane may not edit `docs/openspec`. The delta to write: *the stored position
  of a reflowable publication also holds the locator of the first visible element
  (`cssSelector`, and the text before and after it); resume goes to that element when the
  publication and the resource are the same, and to the fraction otherwise*. Both toolkits
  already expose it (`firstVisibleElementLocator` on iOS and Android).
- **Cheaper partial fix, not taken.** Android could resume at the fraction minus half a page.
  That hides the rounding but not the other causes, and it needs the page count, which Readium
  does not give before layout.

## How to repeat

iOS: `ReadiumPaginationWalkTests/testCaptureResumeThenOneSizeStep` after the store holds the
position (`UPDATE ZSTOREDPROGRESS SET ZPOSITIONDATA=... WHERE ZNORMALIZEDPATH LIKE '%Fixture%'`
in the App Group's `default.store`, with the app closed). Android: `adb exec-out run-as
com.mecedric.storyarc.debug cat databases/progress.db`, edit the `locator` and `progression`
columns of the row, push it back, start the book, then `adb exec-out screencap`.
