## MODIFIED Requirements

### Requirement: Reflowable rendering

The app SHALL render reflowable EPUB 2 and EPUB 3 publications with
user-controlled typography, exposing every axis defined in
[`reading-themes`](../reading-themes/spec.md) through a single sheet reachable
without leaving the page.

#### Scenario: Typography controls
- **WHEN** a user opens the theme sheet
- **THEN** font size, font family, bold text, line spacing, character spacing, word spacing, paragraph spacing, margins, text alignment, background colour and brightness are all adjustable
- **AND** each change is reflected in the page behind the sheet as it is made
- **AND** a live preview showing a chapter title and body text reflects each change as it is made

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

> **The paragraph above is carried from `quiet-reader`, not written here.** It reached the
> main spec when that change synced and was archived on 2026-09-01; this delta was written
> before that and did not have it. A MODIFIED requirement replaces the whole block, so
> archiving this change would have deleted the two-level rule from the contract — including
> the clause that a reader wanting a preset must not pass an axis to reach it, which is the
> whole point of the split.
>
> Found by `pnpm delta:drop`, on that gate's first real run. `openspec validate` passes this
> file either way: it checks the delta's own shape, never what the delta would displace.

#### Scenario: Theme choice
- **WHEN** a user picks a reading theme
- **THEN** Original, Quiet, Paper, Bold, Calm and Focus are available, each meeting WCAG AAA contrast for body text
- **AND** brightness is adjustable within the reader without leaving it

#### Scenario: Theme follows appearance
- **WHEN** the reader has turned on the setting that links app appearance to reading theme, and the system switches to dark while a publication is open
- **THEN** the reading theme switches, then and there rather than at the next open, between the light and dark reading themes the reader chose as their pair, not to an arbitrary default
- **AND** with that setting off the reading theme is untouched, per [`reading-themes`](../reading-themes/spec.md)

#### Scenario: Themes are named, not numbered
- **WHEN** the preset grid is shown
- **THEN** each preset is rendered as its own swatch, showing its name and a specimen of real letterforms in its own background, text colour, face and weight — the letters "Aa" and its name
- **AND** the active preset is visibly selected, and a preset deviated from is marked as modified rather than silently shown as active

> **The scenarios below arrived from a sibling change and are carried, not written
> here.** A MODIFIED requirement replaces the whole block, so a delta written before
> that change synced would drop them on archive. `openspec validate` caught it.

#### Scenario: The theme surface opens on the presets
- **WHEN** a user opens reading themes from the reader's menu
- **THEN** the six preset swatches are what is shown, with no axis control among them
- **AND** one action, given equal prominence to the grid, opens the axes
- **AND** picking a preset applies it and leaves the surface, because that was the whole errand


#### Scenario: The axes, over the reader's own text
- **WHEN** a user opens the axes
- **THEN** they appear on a surface of their own, over a specimen of the publication's own text in the active theme, which updates as an axis changes
- **AND** every axis states its current value in words or numbers beside its control, rather than as an unlabelled position on a track
- **AND** the axes offered are exactly those in [`reading-themes`](../reading-themes/spec.md), with none added and none dropped


#### Scenario: Getting back to the preset
- **WHEN** a preset has been modified and the reader wants it back
- **THEN** the axes surface offers a reset that names the preset it restores
- **AND** it is described in [`reading-themes`](../reading-themes/spec.md), which owns what resetting means


#### Scenario: Both levels at the largest text size
- **WHEN** either surface is shown at the largest accessibility text size
- **THEN** every preset name, axis label and value is readable in full, the surface scrolls if it must, and the action that opens the axes stays reachable
- **AND** no label is truncated to fit its value beside it

