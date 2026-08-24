# comic-reader Specification

## Purpose

The paged image reader used for comics, manga and fixed-layout publications.
Featureful, but never crowded: every control is one gesture away and nothing is
on screen while the user is reading.

## Requirements

### Requirement: Reading modes

The app SHALL offer the following page-transition modes, selectable per
publication and remembered per series.

| Mode | Behaviour |
| --- | --- |
| Page curl | Interactive page turn that follows the finger, with a lit page edge and a shadow cast on the page beneath |
| Slide | Paged horizontal transition |
| Fade | Cross-dissolve between pages |
| Vertical scroll | Continuous vertical scrolling, for webtoons |
| Horizontal scroll | Continuous horizontal scrolling |

#### Scenario: Page curl follows the finger
- **WHEN** a user drags horizontally across the page in page-curl mode
- **THEN** the page deforms and lifts in real time under the finger, at the display's refresh rate
- **AND** releasing past the halfway point completes the turn, releasing before it springs back, and flick velocity completes the turn regardless of distance

#### Scenario: Page curl is interruptible
- **WHEN** a user starts a new drag while a page-curl animation is still settling
- **THEN** the new gesture takes over from the current position without the page snapping

#### Scenario: Reduce Motion
- **WHEN** the system Reduce Motion setting is on
- **THEN** page curl and slide are replaced by a cross-dissolve
- **AND** the mode picker states why the animated modes are unavailable, rather than hiding them without explanation

#### Scenario: Continuous scroll
- **WHEN** a user reads in vertical scroll mode
- **THEN** pages are stitched with no gap by default, with an option to show a separator
- **AND** scroll position is preserved exactly when leaving and returning

#### Scenario: Mode persistence
- **WHEN** a user changes reading mode for a publication
- **THEN** the choice applies to every publication in the same series
- **AND** a global default applies to publications in series never opened before

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

#### Scenario: Entering the reader
- **WHEN** a publication opens
- **THEN** the page fills the screen, chrome is hidden, and the system status and home indicators dim per platform convention

#### Scenario: Revealing controls
- **WHEN** a user taps the centre of the screen
- **THEN** the top bar, bottom bar and page slider fade in over the page without reflowing it
- **AND** they fade out again after 4 seconds of no interaction, or immediately on a second centre tap

#### Scenario: Edge taps turn pages
- **WHEN** a user taps within the left or right edge zone
- **THEN** the page turns in the corresponding direction and chrome does not appear
- **AND** the edge zones are mirrored in right-to-left mode

#### Scenario: Chrome does not obscure the page
- **WHEN** chrome is visible
- **THEN** it floats over the page on a translucent material and the page is not resized or shifted

### Requirement: Navigation within a publication

The app SHALL let a user move anywhere in a publication quickly.

#### Scenario: Page slider with thumbnails
- **WHEN** a user drags the page slider
- **THEN** a thumbnail of the target page follows the drag, and the page number and total are shown
- **AND** releasing jumps there, with a control to return to the previous position

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
