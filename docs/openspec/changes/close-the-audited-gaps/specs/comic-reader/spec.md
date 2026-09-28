## MODIFIED Requirements

### Requirement: Navigation within a publication

The app SHALL let a user move anywhere in a publication quickly.

The page slider SHALL live in the reader's menu rather than over the page, and
SHALL be offered where pages are the unit a reader moves in — a comic, a
fixed-layout publication, a scanned PDF. A reflowable publication is covered by
[`ebook-reader`](../ebook-reader/spec.md), which states its position in words.

#### Scenario: Page slider with thumbnails
- **WHEN** a user opens the reader's menu on a publication with fixed pages and drags the page slider
- **THEN** a thumbnail of the target page follows the drag, and the page number and total are shown
- **AND** releasing jumps there and dismisses the menu, with a control to return to the previous position

#### Scenario: Where the reader is, at a glance
- **WHEN** the reader's menu is open
- **THEN** the coarse position through the publication is drawn as a fill behind the menu's own contents row, and stated in text on that row
- **AND** the text is what conveys the position, so the fill may be absent without anything being lost — it is not the only indication

#### Scenario: Thumbnail browser
- **WHEN** a user opens the thumbnail browser
- **THEN** every page is shown in a scrollable strip with the current page marked, and tapping one jumps to it

#### Scenario: Chapter navigation
- **WHEN** a publication has internal chapter markers, or is one chapter of a series
- **THEN** the reader offers previous and next chapter actions without returning to the library

#### Scenario: Reaching the end
- **WHEN** a user turns past the last page
- **THEN** an end screen offers the next publication in the series or reading list and marks this one finished
- **AND** when "remove downloads after finishing" is off, the end screen offers to remove this publication's download
- **AND** when "remove downloads after finishing" is on, the end screen states that the download is removed when the reader closes, per [`offline-downloads`](../offline-downloads/spec.md) "Automatic cleanup", with a "Keep" action that exempts this publication from that removal
