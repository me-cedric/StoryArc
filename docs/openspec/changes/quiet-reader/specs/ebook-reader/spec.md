## MODIFIED Requirements

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
