# Page browser carousel

**Platforms: both.** The behaviour is the same on both platforms. Each platform
uses its own native parts, which design.md names.

## Why

The reader's thumbnail browser is a row of small cells, 64 points wide on iOS. A
reader who looks for a page in a 300-page omnibus cannot see much of a page at
that size. The browser also does not say which chapter a page is in, although
the reader already knows where each chapter starts (ComicInfo bookmarks, the PDF
outline). The page slider has the same gap: it shows a fill and a number, but no
chapter starts.

The owner asked for a browser like the one in other comic readers: one page
large in the centre, smaller pages beside it, a page number under each page, the
chapter named above the strip, and the chapter starts marked on the slider.

## What Changes

- The thumbnail browser becomes a carousel. It centres one page and draws that
  page larger than the pages beside it. It settles on one page after a swipe.
  Each page shows its page number below it.
- A swipe in the carousel only previews. The page that the reader is on does not
  change until the reader taps a page.
- A drag on the page slider moves the carousel with it. A release jumps, as it
  does now.
- When a publication has chapter markers, the carousel names the chapter of the
  centred page, the first page of each chapter carries a badge, and the slider
  carries a tick at each chapter start.
- Reduce Motion, VoiceOver and TalkBack, and right-to-left reading are covered.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `comic-reader`: adds the requirement "Page browser". The open change
  `close-the-audited-gaps` already modifies "Navigation within a publication",
  so this change adds a requirement next to it and does not modify that one.
  The new requirement refines the scenario "Thumbnail browser" and agrees with
  the scenario "Page slider with thumbnails".

## Impact

- iOS: `ThumbnailStrip.swift`, `ReaderSlider.swift`, `ReaderMenu.swift`, and the
  ReaderFeature string catalog.
- Android: `ThumbnailStrip.kt`, `ReaderMenuSheet.kt`, and the reader's
  `strings.xml` in four languages.
- No new dependency. No change to stored data.
- A fixed-layout EPUB is out of scope. Its reader is `ebook-reader`, and it has
  no thumbnail browser.
