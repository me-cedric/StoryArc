# ebook-reader Specification

## Purpose

The reflowable reader for EPUB, and the paged renderer for PDF. Text that
reflows needs a different set of controls from images that do not, but it needs
the same restraint: nothing on screen while reading.

## Requirements

### Requirement: Reflowable rendering

The app SHALL render reflowable EPUB 2 and EPUB 3 publications with
user-controlled typography, exposing every axis defined in
[`reading-themes`](../reading-themes/spec.md) through a single sheet reachable
without leaving the page.

#### Scenario: Typography controls
- **WHEN** a user opens the theme sheet
- **THEN** font size, font family, bold text, line spacing, character spacing, word spacing, paragraph spacing, margins, text alignment, background colour and brightness are all adjustable
- **AND** each change is reflected in the page behind the sheet as it is made
- **AND** a live preview inside the sheet shows the pending change on a chapter title and body text

#### Scenario: One sheet, two depths
- **WHEN** the theme sheet opens
- **THEN** the first level shows the six presets, the font-size stepper, the page-mode control and brightness — the things changed mid-chapter
- **AND** the fine axes sit one level deeper behind a single "Customise" action, so the common case is one tap and the rare case is two

#### Scenario: Bundled typefaces
- **WHEN** a user chooses a typeface
- **THEN** the publisher's own fonts, the system serif, the system sans, at least three bundled reading serifs, and Atkinson Hyperlegible are offered
- **AND** Atkinson Hyperlegible is labelled as designed for low vision
- **AND** every bundled family is openly licensed, and its licence appears in acknowledgements

#### Scenario: Publisher styles
- **WHEN** a user disables publisher styles
- **THEN** the publication renders with StoryArc's typography alone, and the setting is reversible without losing the reading position

#### Scenario: An axis is inert while publisher styles are on
- **WHEN** line spacing, character spacing, word spacing, paragraph spacing, text alignment or hyphenation is shown while publisher styles are enabled
- **THEN** the control is marked unavailable with a one-line reason and a single action to disable publisher styles
- **AND** it is never shown as an active control that silently does nothing

#### Scenario: Fixed-layout EPUB
- **WHEN** a fixed-layout EPUB is opened
- **THEN** it renders paginated at its intended aspect ratio with the zoom and spread behaviour of [`comic-reader`](../comic-reader/spec.md), and typography controls are hidden rather than shown disabled
- **AND** background colour, brightness and page transition remain available, because they apply to the container rather than the text

### Requirement: Reader themes

The app SHALL offer the six reading-theme presets defined in
[`reading-themes`](../reading-themes/spec.md), each meeting WCAG AAA contrast
for body text.

The theme surface SHALL have **two levels**. The first offers the presets and
nothing else. The second offers the axes, and is reached from one action on the
first. A reader who wants a preset SHALL NOT pass an axis to reach it.

#### Scenario: Theme choice
- **WHEN** a user picks a reading theme
- **THEN** Original, Quiet, Paper, Bold, Calm and Focus are available, each meeting WCAG AAA contrast for body text
- **AND** brightness is adjustable within the reader without leaving it

#### Scenario: The theme surface opens on the presets
- **WHEN** a user opens reading themes from the reader's menu
- **THEN** the six preset swatches are what is shown, with no axis control among them
- **AND** one action, given equal prominence to the grid, opens the axes
- **AND** picking a preset applies it and leaves the surface, because that was the whole errand

#### Scenario: Themes are named, not numbered
- **WHEN** the preset grid is shown
- **THEN** each preset is rendered as its own swatch, showing its name and a specimen of real letterforms in its own background, text colour, face and weight
- **AND** the active preset is visibly selected, and a preset deviated from is marked as modified rather than silently shown as active

#### Scenario: The axes, over the reader's own text
- **WHEN** a user opens the axes
- **THEN** they appear on a surface of their own, over a specimen of the publication's own text in the active theme, which updates as an axis changes
- **AND** every axis states its current value in words or numbers beside its control, rather than as an unlabelled position on a track
- **AND** the axes offered are exactly those in [`reading-themes`](../reading-themes/spec.md), with none added and none dropped

#### Scenario: Getting back to the preset
- **WHEN** a preset has been modified and the reader wants it back
- **THEN** the axes surface offers a reset that names the preset it restores
- **AND** it is described in [`reading-themes`](../reading-themes/spec.md), which owns what resetting means

#### Scenario: Theme follows appearance
- **WHEN** the reader has turned on the setting that links app appearance to reading theme, and the system switches to dark while a publication is open
- **THEN** the reading theme switches, then and there rather than at the next open, between the light and dark reading themes the reader chose as their pair, not to an arbitrary default
- **AND** with that setting off the reading theme is untouched, per [`reading-themes`](../reading-themes/spec.md)

#### Scenario: Both levels at the largest text size
- **WHEN** either surface is shown at the largest accessibility text size
- **THEN** every preset name, axis label and value is readable in full, the surface scrolls if it must, and the action that opens the axes stays reachable
- **AND** no label is truncated to fit its value beside it

### Requirement: Pagination and progress

The app SHALL paginate reflowable text stably and report progress meaningfully.

A reflowable publication SHALL report its position **in words, in one line**, and
SHALL NOT draw a page slider. Pages are not the unit a novel is read in, and the
app already refuses to treat a reflowable page number as a stable identity — a
slider whose track is measured in those pages is that same claim in another form.

#### Scenario: Changing type size mid-chapter
- **WHEN** a user changes type size while reading
- **THEN** the reading position is preserved to the paragraph, not the page number

#### Scenario: Progress display
- **WHEN** a reader opens the reader's menu on a reflowable publication
- **THEN** one line states how far through the publication they are and how much of the current chapter is left, in words
- **AND** because reflowable page counts depend on typography, the app never presents a reflowable page number as a stable identity
- **AND** no slider is offered, and the position is not drawn over the page

#### Scenario: Moving somewhere else in a reflowable publication
- **WHEN** a reader wants to go somewhere other than the next page
- **THEN** the table of contents is how they get there, reached from the same menu
- **AND** removing the slider therefore removes no destination

#### Scenario: A publication that declares no chapters
- **WHEN** a reflowable publication carries no navigation to divide it
- **THEN** the line states progress through the publication alone rather than naming a chapter that does not exist
- **AND** it does not fall back to a page count, because that is the identity the app refuses to present

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
- **AND** the destination host is shown and confirmed first, because the reader is leaving the book on a publication's say-so
- **AND** only `http` and `https` are followed; a link naming any other scheme is dropped rather than handed on

#### Scenario: A publication reaching the network on its own
- **WHEN** a publication's content references a remote image, font, stylesheet or script, or its scripts try to open a connection
- **THEN** the request is denied, because a book is a document and a document that phones home was not asked to
- **AND** the reader is not prompted and no setting is offered, since a publication has no legitimate claim on the network the reader did not make for it
- **AND** the publication still renders: scripting stays enabled, and only what leaves the device is stopped
- **AND** a remote resource a publication genuinely wanted is simply absent rather than reported as an error, which is the accepted cost

### Requirement: PDF rendering

The app SHALL render PDF as a paged publication, over each platform's own PDF
library. Text selection and in-publication search work on both. The document
outline is the one part of it that only one platform exposes, which
[ADR-0012](../../../decisions/0012-pdf-text-on-android.md) records.

#### Scenario: Text-based PDF
- **WHEN** a PDF contains a text layer
- **THEN** text selection, in-publication search, and the document outline work
- **AND** a selection offers the same four things a reflowable selection does — highlight in several colours, add a note, copy, and search-in-publication — stored as the same record and exported by the same document
- **AND** where a platform's PDF library exposes no document outline, that control is absent rather than empty, which [ADR-0012](../../../decisions/0012-pdf-text-on-android.md) records

#### Scenario: Scanned PDF
- **WHEN** a PDF is images only
- **THEN** it is read with the image-reader behaviour of [`comic-reader`](../comic-reader/spec.md), and text-dependent controls are hidden
- **AND** a reader who presses on a word expecting to select it is told in one sentence that the file is images of pages, rather than being met with silence
- **AND** this is the behaviour on both platforms, because there is no text layer to expose

#### Scenario: A text layer is detected rather than assumed
- **WHEN** a PDF is opened
- **THEN** whether it has a text layer is determined by looking for text, not by the file extension
- **AND** a scanned PDF therefore offers no selection or search on either platform, because there is nothing to select or find

#### Scenario: A device that cannot read PDF text
- **WHEN** the platform's PDF text API is absent on this device
- **THEN** the publication behaves exactly as a scanned PDF does: no search control, no selection, and the same one-sentence statement
- **AND** nothing names the missing API, because a reader can act on neither that nor the file's contents and only the second is about the book

#### Scenario: Large PDF
- **WHEN** a PDF of several hundred megabytes is opened from a remote source
- **THEN** pages render on demand rather than the whole document being loaded
- **AND** opening the document rasterises nothing, so page count and page geometry are available before any page is drawn

#### Scenario: A rendered page is bounded by what it is shown at
- **WHEN** a page is rendered for display
- **THEN** it is rasterised to at most the size it will occupy, never to the page's full resolution regardless of the screen
- **AND** asking for more pixels than the page has does not upscale it, matching how an image page is decoded

#### Scenario: Page rendering is identical across platforms
- **WHEN** the same PDF page is rendered on both platforms
- **THEN** it appears at the same aspect ratio, fit and zoom behaviour, because only the document outline differs — not the page
- **AND** page geometry is reported in PDF points rather than pixels, so the two platforms are comparable without reference to a screen

### Requirement: Reading aloud

The app SHOULD read a publication aloud using the platform speech engine.

#### Scenario: Starting playback
- **WHEN** a user starts read-aloud on a reflowable publication
- **THEN** speech begins at the current position, the spoken sentence is highlighted, and the page follows

#### Scenario: Background and lock screen
- **WHEN** read-aloud is playing and the app is backgrounded
- **THEN** playback continues, and platform media controls show the publication title and offer play, pause, and sentence skip
- **AND** the second line names the chapter being spoken, or the author where the publication declares no navigation

#### Scenario: Reaching the end of a chapter
- **WHEN** the voice reaches the end of the resource it is reading
- **THEN** it carries on into the next one without being asked, because a chapter boundary is not something a listener asked to stop at
- **AND** at the end of the publication it stops, the highlight is withdrawn, and the media controls go away rather than offering to play a book that has run out of words

#### Scenario: Where the listening got to
- **WHEN** a reader has listened for a while and closes the publication
- **THEN** the position [`reading-progress`](../reading-progress/spec.md) records is where the voice got to, not where the reading stopped, because the page followed the voice

#### Scenario: Something else takes the audio
- **WHEN** a phone call, another app, or a spoken direction takes the audio while read-aloud is playing
- **THEN** the voice stops, and when the audio comes back and the platform says playback may resume, it carries on by itself
- **AND** a pause the reader made themselves is never undone this way, however the interruption ends
- **AND** audio taken for good stops the session rather than leaving it paused for ever

#### Scenario: A publication with nothing to say
- **WHEN** a publication carries no text that can be extracted
- **THEN** the read-aloud control is absent rather than present and refusing
