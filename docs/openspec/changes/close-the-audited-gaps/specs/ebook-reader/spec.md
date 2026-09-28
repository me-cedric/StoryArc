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

#### Scenario: Typeface, weight and margins apply under publisher styles
- **WHEN** publisher styles are enabled, per [`reading-themes`](../reading-themes/spec.md) "Theme presets" Original
- **THEN** the chosen typeface, bold weight, margins and font size still apply over the publisher's own styling
- **AND** margins are shown rather than hidden while publisher styles are on

#### Scenario: An axis is inert while publisher styles are on
- **WHEN** line spacing, character spacing, word spacing, paragraph spacing, text alignment or hyphenation is shown while publisher styles are enabled
- **THEN** the control is marked unavailable with a one-line reason and a single action to disable publisher styles
- **AND** it is never shown as an active control that silently does nothing
- **AND** hyphenation stays in this list even after typeface, weight and margins move out of it, because the platform's publisher-style rendering exposes no hyphenation override to apply

#### Scenario: Fixed-layout EPUB
- **WHEN** a fixed-layout EPUB is opened
- **THEN** it renders paginated at its intended aspect ratio with the zoom and spread behaviour of [`comic-reader`](../comic-reader/spec.md), and typography controls are hidden rather than shown disabled
- **AND** background colour, brightness and page transition remain available, because they apply to the container rather than the text
