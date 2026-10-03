## 1. iOS

- [x] 1.1 Make `ThumbnailStrip.swift` a carousel: centred page, larger than its neighbours, settles on one page, page number under each page. Decode thumbnails at the centred size. Right-to-left order and Reduce Motion as design.md §1 states.
- [x] 1.2 Keep the centred page as a preview: a swipe does not move the reader, a tap jumps through the existing jump path (design.md §2).
- [x] 1.3 Let a drag on `ReaderSlider` centre the target page in the carousel, one update per frame, and jump on release (design.md §3).
- [x] 1.4 Add the chapter name above the carousel, the chapter badge on each chapter's first page, and a tick on the slider for each chapter start (design.md §4 and §5).
- [x] 1.5 Give each cell its accessibility label and the selected trait, and make the chapter name a label that is not focusable (design.md §6). Add the new strings in en, fr, de and es.

## 2. Android

- [x] 2.1 Make `ThumbnailStrip.kt` a carousel with `HorizontalCenteredHeroCarousel`, or the `HorizontalPager` fallback that design.md §1 names. Keep the `Ltr { }` pin and the reversed order for right-to-left.
- [x] 2.2 Keep the centred page as a preview: a swipe does not move the reader, a tap jumps through the existing jump path.
- [x] 2.3 Let a drag on the page slider in `ReaderMenuSheet.kt` centre the target page, one update per frame, and jump on release.
- [x] 2.4 Add the chapter name, an M3 `Badge` on each chapter's first page, and the chapter ticks in the slider's `track` slot.
- [x] 2.5 Give each cell its content description and the selected state, and add the new strings to the four `strings.xml` files.

## 3. Proof

- [x] 3.1 Add unit tests for the rules that have no view: the badge text, the chapter name for the centred page, the tick positions, and the right-to-left order. Run each test against a mutation and see it fail.
- [ ] 3.2 Capture iOS and Android frames of the browser on a comic with chapter markers, in light and dark, at the largest text size, and on a right-to-left comic.
