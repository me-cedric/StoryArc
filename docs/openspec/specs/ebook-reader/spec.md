# ebook-reader Specification

## Purpose

The reflowable reader for EPUB, and the paged renderer for PDF. Text that
reflows needs a different set of controls from images that do not, but it needs
the same restraint: nothing on screen while reading.

## Requirements

### Requirement: Reflowable rendering

The app SHALL render reflowable EPUB 2 and EPUB 3 publications with
user-controlled typography.

#### Scenario: Typography controls
- **WHEN** a user opens typography settings
- **THEN** typeface, size, line height, character spacing, word spacing, paragraph spacing, text alignment, margins, and hyphenation are adjustable with live preview

#### Scenario: Bundled typefaces
- **WHEN** a user chooses a typeface
- **THEN** the publisher's own fonts, the system sans, a bundled serif, and Atkinson Hyperlegible are offered
- **AND** Atkinson Hyperlegible is labelled as designed for low vision

#### Scenario: Publisher styles
- **WHEN** a user disables publisher styles
- **THEN** the publication renders with StoryArc's typography alone, and the setting is reversible without losing the reading position

#### Scenario: Fixed-layout EPUB
- **WHEN** a fixed-layout EPUB is opened
- **THEN** it renders paginated at its intended aspect ratio with the zoom and spread behaviour of [`comic-reader`](../comic-reader/spec.md), and typography controls are hidden rather than shown disabled

### Requirement: Reader themes

The app SHALL offer reading themes tuned for long-form text.

#### Scenario: Theme choice
- **WHEN** a user picks a reading theme
- **THEN** Paper, Sepia, Night, and High Contrast are available, each meeting WCAG AAA contrast for body text
- **AND** brightness is adjustable within the reader without leaving it

#### Scenario: Theme follows appearance
- **WHEN** the app appearance is set to follow the system and the system switches to dark
- **THEN** the reading theme switches between the user's chosen light and dark reading themes, not to an arbitrary default

### Requirement: Pagination and progress

The app SHALL paginate reflowable text stably and report progress meaningfully.

#### Scenario: Changing type size mid-chapter
- **WHEN** a user changes type size while reading
- **THEN** the reading position is preserved to the paragraph, not the page number

#### Scenario: Progress display
- **WHEN** a user is reading
- **THEN** progress is shown as percentage through the publication and as pages remaining in the current chapter
- **AND** because reflowable page counts depend on typography, the app never presents a reflowable page number as a stable identity

#### Scenario: Scroll mode
- **WHEN** a user chooses continuous scrolling instead of pagination
- **THEN** the whole publication scrolls continuously, and position is preserved when switching modes

### Requirement: Navigation and annotation

The app SHALL let a user move around a publication and mark places in it.

#### Scenario: Table of contents
- **WHEN** a user opens the table of contents
- **THEN** the publication's own navigation is shown to its full depth, with the current position highlighted

#### Scenario: Bookmarks
- **WHEN** a user bookmarks a position
- **THEN** it is saved with its chapter title and a text excerpt, and is listed alongside the table of contents

#### Scenario: Highlights and notes
- **WHEN** a user selects text
- **THEN** highlight in several colours, add a note, copy, and search-in-publication are offered
- **AND** highlights and notes are listed in one place and exportable as plain text or Markdown

#### Scenario: Search within a publication
- **WHEN** a user searches inside a publication
- **THEN** matches are listed with surrounding context and tapping one jumps to it

#### Scenario: Following an internal link
- **WHEN** a user follows a footnote or internal link
- **THEN** a footnote opens in place as a popover, and a longer jump navigates with a control to return to where they were

#### Scenario: Returning from any jump
- **WHEN** a user has been moved away from where they were reading — by a link, a table-of-contents entry, a bookmark, or a search result
- **THEN** the same control to return is offered, because these are one act from the reader's side
- **AND** it is offered until it is used or another jump replaces it, and using it does not itself become somewhere to return from

#### Scenario: Following a link out of the publication
- **WHEN** a user follows a link to somewhere outside the publication
- **THEN** it is handed to the system rather than opened over the text, and nothing is fetched until the link is followed

### Requirement: PDF rendering

The app SHALL render PDF as a paged publication.

#### Scenario: Text-based PDF
- **WHEN** a PDF contains a text layer
- **THEN** text selection, in-publication search, and the document outline work
- **AND** a selection offers the same four things a reflowable selection does — highlight in several colours, add a note, copy, and search-in-publication — stored as the same record and exported by the same document
- **AND** where a platform's PDF library exposes no document outline, that control is absent rather than empty, which [ADR-0011](../../decisions/0011-pdf-text-on-android.md) records

#### Scenario: Scanned PDF
- **WHEN** a PDF is images only
- **THEN** it is read with the image-reader behaviour of [`comic-reader`](../comic-reader/spec.md), and text-dependent controls are hidden
- **AND** a reader who presses on a word expecting to select it is told in one sentence that the file is images of pages, rather than being met with silence

#### Scenario: A device that cannot read PDF text
- **WHEN** the platform's PDF text API is absent on this device
- **THEN** the publication behaves exactly as a scanned PDF does: no search control, no selection, and the same one-sentence statement
- **AND** nothing names the missing API, because a reader can act on neither that nor the file's contents and only the second is about the book

#### Scenario: Large PDF
- **WHEN** a PDF of several hundred megabytes is opened from a remote source
- **THEN** pages render on demand rather than the whole document being loaded

### Requirement: Reading aloud

The app SHOULD read a publication aloud using the platform speech engine.

#### Scenario: Starting playback
- **WHEN** a user starts read-aloud on a reflowable publication
- **THEN** speech begins at the current position, the spoken sentence is highlighted, and the page follows

#### Scenario: Background and lock screen
- **WHEN** read-aloud is playing and the app is backgrounded
- **THEN** playback continues, and platform media controls show the publication title and offer play, pause, and sentence skip
