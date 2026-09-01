## MODIFIED Requirements

### Requirement: Auto-hiding chrome

The reader SHALL show no controls while reading, and reveal them on demand.

Revealed chrome SHALL consist of **a way out and a way in, and nothing else**: an
affordance that closes the publication, and one menu affordance that leads to
everything the reader can do with it. No third control appears over the page.

> **Why this is now a count.** The previous text specified a top bar, a bottom bar
> and a page slider, and each of the eleven controls between them was added on its
> own justification. Naming the two that may be over the page is the only form of
> this rule that holds: any other wording invites a twelfth.

#### Scenario: Entering the reader
- **WHEN** a publication opens
- **THEN** the page fills the screen, the system status and home indicators dim per platform convention, and the two controls are shown once and then withdraw themselves within a few seconds without being asked
- **AND** they are not shown again until a centre tap asks for them

> **This sentence used to say "chrome is hidden", and the screenshots caught that no
> reader had ever done it.** All four — both platforms, both readers — start with chrome
> visible and withdraw it after four seconds, and no source-level test looks at the
> arrival frame, so the divergence survived every gate for as long as the requirement has
> existed. See [`before-2026-08-31d`](../../../../designs/screenshots/after-2026-08-31d/README.md).
>
> The behaviour is the half that is right, and the sentence is the half being fixed. A
> reader who has just opened a book has not yet learned that a centre tap brings back the
> way out; showing it once and taking it away teaches that in the only place it can be
> taught, and costs four seconds of a page nobody is reading yet. Apple Books, which this
> change follows, does the same. A requirement that forbids it would make the app harder
> to leave in exchange for a purity no reader asked for.
>
> What is kept is the part that matters: the controls go **by themselves**, and nothing
> is drawn over the page again until it is asked for.

#### Scenario: Revealing controls
- **WHEN** a user taps the centre of the screen
- **THEN** exactly two controls fade in over the page — one that closes the publication and one that opens the reader's menu — and the page does not reflow
- **AND** they fade out again after 4 seconds of no interaction, or immediately on a second centre tap
- **AND** no title, page number, percentage or slider is drawn over the page, because each of those is a fact the menu states better and none of them is an action

#### Scenario: Everything else is in the menu, and labelled
- **WHEN** a user opens the reader's menu
- **THEN** it offers the table of contents, bookmarks, search within the publication, reading themes and reader settings, each named in words rather than by icon alone
- **AND** every control that was reachable from the reader before this change is reachable from here in one action

#### Scenario: Edge taps turn pages
- **WHEN** a user taps within the left or right edge zone
- **THEN** the page turns in the corresponding direction and chrome does not appear
- **AND** the edge zones are mirrored in right-to-left mode

#### Scenario: Chrome does not obscure the page
- **WHEN** chrome is visible
- **THEN** it floats over the page on a translucent material and the page is not resized or shifted

#### Scenario: Fewer controls is not fewer ways in
- **WHEN** a user uses any gesture the reader supported before this change — edge tap, swipe, pinch, drag to zoom, or the mirrored equivalents in right-to-left mode
- **THEN** it behaves exactly as it did, because moving controls into a menu must not make the reader harder to drive

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
- **THEN** an end screen offers the next publication in the series or reading list, marks this one finished, and offers to delete the download if the setting is on
