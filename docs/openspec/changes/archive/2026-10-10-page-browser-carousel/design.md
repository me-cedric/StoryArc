# Design: page browser carousel

## Context

Both platforms have a lazy thumbnail strip in the reader menu:
`ThumbnailStrip.swift` (64-point cells, `LazyHStack`, `ScrollViewReader`) and
`ThumbnailStrip.kt` (a `LazyRow` inside the `Ltr { }` pin from task 15.8 of
`close-the-audited-gaps`). The model on each platform asks for a thumbnail when a
cell scrolls into view, and keeps a bounded number of thumbnails. The chapter
starts come from `ReaderChapters.swift` and `PdfOutlineChapters.swift` on iOS,
and from `ReaderViewModelChapters.kt` on Android (decision D4: ComicInfo
bookmarks on both platforms, plus the PDF outline on iOS).

## Goals and non-goals

Goals: the behaviour in the spec delta, with native parts only, and no new
dependency.

Non-goals: a fixed-layout EPUB browser, a vertical browser, and changes to the
stored data.

## Decisions

### 1. The carousel

- iOS: keep `ScrollView(.horizontal)` with `LazyHStack`. Add
  `.scrollTargetBehavior(.viewAligned)` and `.scrollTargetLayout()` so that the
  carousel settles on one page. Use `.contentMargins` so that the first and last
  pages can be centred. Read the centred page with `.scrollPosition(id:)`.
  Scale the pages with `.scrollTransition`. With Reduce Motion on, the
  transition does not scale.
- Android: use `HorizontalCenteredHeroCarousel` from material3 1.5.0-alpha26,
  which the project already pins. It is lazy, it centres one item, and it snaps.
  Keep the `Ltr { }` pin, and reverse the item order for a right-to-left
  publication, as the strip does now. If the hero carousel cannot hold the page
  numbers under the items, use `HorizontalPager` with `contentPadding`, and
  scale with `graphicsLayer` from `currentPageOffsetFraction`.
- Size: the centred page is about 1.6 times as wide as its neighbours. Each cell
  keeps the page's own aspect ratio, so a double-page spread shows as one wide
  cell.
- Thumbnails: decode at the size of the centred page, and draw the neighbours
  from the same image, scaled down. The cache bound stays as it is.

### 2. Preview versus jump

The centred page is a preview state that the browser owns. The reader's current
page changes only on a tap, or on the release of a slider drag. Both go through
the existing jump path, so the "return to the previous position" control keeps
working.

### 3. The slider drives the carousel

During a drag, the slider's value sets the carousel's centred page with no
animation. Each platform throttles this to one update per frame. On release,
the existing jump runs.

### 4. Chapter ticks on the slider

- iOS: `Slider` tick marks (iOS 26), one tick for each chapter start. If the
  tick API cannot place a tick at an arbitrary value, draw the ticks in an
  overlay aligned to the track, under the thumb. Mirror the overlay for a
  right-to-left publication.
- Android: M3 `Slider` with its `track` slot. Draw the ticks in the track with a
  `Canvas`, at each chapter start. The built-in `steps` cannot mark chapters,
  because they are evenly spaced.
- Ticks use the theme's accent colour, and reach 3:1 contrast against the track.

### 5. Chapter name and badge

- The name above the carousel is the marker's title. A marker without a title
  uses the localized "Chapter %d", with the chapter's position.
- The badge text is the issue number that the marker gives (for example `#4`).
  Without a number, the badge shows the chapter's position. Android uses M3
  `Badge`. iOS uses a capsule in the system material, with the accent colour.

### 6. Accessibility

Each cell is one accessibility element. Its label is "Page %d" plus the chapter
name when there is one. The current page has the selected trait (iOS) or the
selected state (Android). The chapter name above the carousel is a live label
that is not focusable, so a moving carousel is not read twice.

## Risks

- The hero carousel draws items with a mask. Page numbers under the items can
  fall outside the mask. Section 1 names the fallback.
- On a large omnibus, scrolling the carousel to the target page on each drag
  frame can drop frames. Section 3 throttles the updates to one per frame. Also
  measure on the largest comic in the test corpus.
