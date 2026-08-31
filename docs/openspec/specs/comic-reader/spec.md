# comic-reader Specification

## Purpose

The paged image reader used for comics, manga and fixed-layout publications.
Featureful, but never crowded: every control is one gesture away and nothing is
on screen while the user is reading.

## Requirements

### Requirement: Page transitions in the comic reader

The comic reader SHALL use the transition engine defined in
[`page-transitions`](../page-transitions/spec.md) — Curl, Slide, Fast fade and
Scroll — and SHALL add only the behaviour that is specific to image pages.

#### Scenario: Mode persistence
- **WHEN** a user changes reading mode for a publication
- **THEN** the choice applies to every publication in the same series
- **AND** a global default applies to publications in series never opened before
- **AND** the comic default is independent of the reflowable default, per [`reading-themes`](../reading-themes/spec.md)

#### Scenario: Continuous scroll
- **WHEN** a user reads in Scroll mode
- **THEN** pages are stitched with no gap by default, with an option to show a separator
- **AND** scroll position is preserved exactly when leaving and returning

#### Scenario: Scroll axis for webtoons
- **WHEN** a publication is a webtoon, or its pages are materially taller than they are wide
- **THEN** Scroll defaults to the vertical axis
- **AND** the axis remains overridable

#### Scenario: Curl over image pages
- **WHEN** a curl runs over a comic page
- **THEN** it uses the already-decoded page directly rather than a re-raster, because the page is an image before the turn begins

### Requirement: Reading direction

The app SHALL support left-to-right and right-to-left reading, defaulting from
publication metadata.

#### Scenario: Manga defaults
- **WHEN** a publication declares right-to-left, or is Japanese with no declared direction
- **THEN** it opens right-to-left, page-turn gestures and the page slider are mirrored, and the first page is on the right

#### Scenario: Overriding direction
- **WHEN** a user changes reading direction
- **THEN** it applies immediately without losing the current page, and is remembered for the series

### Requirement: Page fitting and zoom

The app SHALL fit pages sensibly by default and allow free zoom.

#### Scenario: Fit modes
- **WHEN** a user chooses a fit mode
- **THEN** fit-to-screen, fit-to-width, fit-to-height, and original size are available, and the choice persists per series

#### Scenario: Double-page spreads
- **WHEN** two consecutive pages are portrait and the device is in landscape
- **THEN** they are shown side by side in the correct order for the reading direction
- **AND** a page detected as a single wide spread is shown alone, never split across two turns
- **AND** the user can offset the pairing by one page, for publications whose cover throws the pairing off

#### Scenario: Zooming
- **WHEN** a user pinches
- **THEN** the page zooms about the pinch centre, pans within bounds, and double-tap toggles between fit and a zoomed level centred on the tapped point

#### Scenario: Zoom persists across pages
- **WHEN** a user turns the page while zoomed in fit-to-width mode
- **THEN** the next page keeps the zoom level and returns to the top of the page in reading order

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

### Requirement: Image adjustments

The app SHALL offer per-publication image adjustments for poorly scanned material.

#### Scenario: Adjustments available
- **WHEN** a user opens image adjustments
- **THEN** brightness, contrast, sharpness, colour inversion, and greyscale are available with a live preview

#### Scenario: Cropping borders
- **WHEN** a user enables border cropping
- **THEN** uniform white or black margins are detected and trimmed per page, and the user can disable it for a page that crops wrongly

#### Scenario: Persisting adjustments
- **WHEN** a user changes an adjustment
- **THEN** it applies to the series and is not applied globally

### Requirement: Reader performance

The reader SHALL feel immediate regardless of source.

#### Scenario: Prefetching
- **WHEN** a user is reading
- **THEN** at least the next three and previous one page are decoded and held ready
- **AND** prefetch depth shrinks under memory pressure rather than the app being terminated

#### Scenario: Page not yet available
- **WHEN** a page is still loading from a slow source
- **THEN** a placeholder holding the correct aspect ratio is shown, so the turn does not jump when it arrives
- **AND** a progress indicator appears only after 400 ms

#### Scenario: Screen stays awake
- **WHEN** a user is in the reader
- **THEN** the screen does not auto-lock while a page is visible, and normal locking resumes on leaving

### Requirement: System integration

The reader SHALL honour platform reading conventions.

#### Scenario: Hardware page turns
- **WHEN** a keyboard, volume buttons if enabled in settings, or an external controller is used
- **THEN** the mapped keys turn pages

#### Scenario: Orientation lock
- **WHEN** a user locks the reader's orientation
- **THEN** it stays locked for the reader only, and the rest of the app follows the device

#### Scenario: Screenshot and recording
- **WHEN** a user takes a screenshot
- **THEN** the page is captured without chrome, since chrome is hidden while reading
