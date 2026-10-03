## ADDED Requirements

### Requirement: Page browser

The app SHALL show the thumbnail browser of a publication with fixed pages as a
carousel that centres one page. When the publication has chapter markers, the
browser SHALL name the chapter of the centred page and mark where each chapter
starts. This requirement refines "Thumbnail browser" and agrees with "Page
slider with thumbnails" in "Navigation within a publication".

#### Scenario: One page in the centre
- **WHEN** a user opens the thumbnail browser
- **THEN** the current page is centred, drawn larger than the pages beside it, and marked as current
- **AND** each page shows its page number below it
- **AND** after a swipe, the carousel settles with one page centred

#### Scenario: Browsing does not move the reader
- **WHEN** a user swipes the carousel
- **THEN** the page that the reader is on does not change
- **AND** a tap on a page jumps there, as "Thumbnail browser" states

#### Scenario: The slider moves the carousel
- **WHEN** a user drags the page slider while the thumbnail browser is shown
- **THEN** the carousel follows the drag and centres the target page
- **AND** releasing jumps there, as "Page slider with thumbnails" states

#### Scenario: Chapters in the browser
- **WHEN** a publication has internal chapter markers
- **THEN** the name of the centred page's chapter is shown above the carousel, and it changes as the centred page enters another chapter
- **AND** the first page of each chapter carries a badge with the chapter's number, or with its position among the chapters when the marker gives no number
- **AND** the page slider carries a tick at the start of each chapter
- **AND** the chapter name in text is what states the chapter, so the ticks and the badges are never the only indication

#### Scenario: No chapter markers
- **WHEN** a publication has no internal chapter markers
- **THEN** the browser shows no chapter name, no badges and no ticks, and keeps the rest of its behaviour

#### Scenario: Right-to-left reading
- **WHEN** a publication reads right to left
- **THEN** the carousel runs right to left, with page one at the right end, the same way as the mirrored page slider

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is on
- **THEN** the pages do not scale as they move, and the outline that marks the centred page is the indication of the centred page

#### Scenario: Assistive technology
- **WHEN** VoiceOver or TalkBack reaches a page in the carousel
- **THEN** it announces the page number and, when the publication has chapter markers, the chapter name
- **AND** it announces the current page as current
