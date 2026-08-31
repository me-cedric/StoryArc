# reading-themes Specification

## Purpose

The theme model both readers share. A theme is a named bundle of typographic and
colour choices that a reader can adopt in one tap, and then deviate from on any
single axis. This capability owns the presets, the axes, the custom-colour path,
and how a reading theme relates to the app's own appearance — deliberately
loosely, because a dark app chrome around a paper-white page is a legitimate
preference rather than a mistake.

Presentation of the controls lives in
[`ebook-reader`](../ebook-reader/spec.md); the platform look of the sheet lives
in [`native-experience`](../native-experience/spec.md).

## Requirements

### Requirement: Theme presets

The app SHALL offer six named reading-theme presets, each setting a background
colour, a text colour, a typeface, and a spacing character.

| Preset | Character |
| --- | --- |
| **Original** | The publication as its publisher styled it. Publisher styles on; StoryArc overrides nothing but size. |
| **Quiet** | Low-contrast dark. Soft off-white text on deep neutral, tightened spacing. |
| **Paper** | Neutral light. Book-stock white, serif, comfortable default spacing. |
| **Bold** | High contrast, heavier weight, wider spacing. For low vision without leaving the aesthetic. |
| **Calm** | Warm dim. Cream-on-brown, generous line height. Long evening sessions. |
| **Focus** | Narrow measure, high contrast, minimal decoration. Fewest words per line. |

A preset a reader has deviated from SHALL be restorable **by name**, to the values
this table describes, without touching any other preset or any other setting.

#### Scenario: Applying a preset
- **WHEN** a user taps a preset
- **THEN** every axis the preset defines is applied at once and the change is visible immediately in the reader behind the sheet
- **AND** the preset is remembered for the series, per the per-series rule in [`ebook-reader`](../ebook-reader/spec.md)

#### Scenario: Original respects the publisher
- **WHEN** a user selects Original
- **THEN** publisher styles remain enabled and StoryArc overrides no typographic axis except font size
- **AND** the axes that require publisher styles to be off are shown as unavailable with a one-line explanation, not hidden and not shown as dead controls

#### Scenario: Deviating from a preset
- **WHEN** a user changes any axis while a preset is active
- **THEN** the preset stays selected and is marked as modified
- **AND** a single action restores the preset's own values

#### Scenario: The reset names what it restores
- **WHEN** a modified preset is reset
- **THEN** the action names that preset — the reader who modified Calm is offered Calm back, not an unnamed default
- **AND** every axis returns to that preset's published value, including any the reader never touched
- **AND** the other five presets, the custom colour slot, the per-series memory and the global default are unchanged, because a reset is not a factory reset

#### Scenario: Resetting the preset that is already unmodified
- **WHEN** a reset is offered for a preset nothing has deviated from
- **THEN** the action is absent rather than present and doing nothing, because a control that never changes anything teaches a reader to distrust the ones that do

#### Scenario: Reset does not disturb the reading position
- **WHEN** a preset is reset while a publication is open
- **THEN** the reading position is preserved to the paragraph across the repagination, exactly as a type-size change is
- **AND** the change is visible behind the sheet without the sheet being dismissed

#### Scenario: Presets follow the appearance polarity
- **WHEN** the app appearance switches between light and dark
- **THEN** the reading theme does **not** change, because appearance and reading theme are independent settings
- **AND** a user who wants them linked can enable that explicitly in settings

### Requirement: Theme axes

A reading theme SHALL be defined by exactly these axes, and each SHALL be
independently adjustable.

Every axis control SHALL state its current value beside it. A slider is a position
on a track and a reader cannot report, repeat or reason about a position; "line
spacing 1.4" is a value they can.

| Axis | Control | Notes |
| --- | --- | --- |
| Font size | Stepped, smaller/larger | Discrete steps with a visible position indicator, not a free slider |
| Font family | Picker | Bundled families plus the publisher's own and the system face |
| Bold text | Toggle | Raises weight without changing family |
| Line spacing | Slider | |
| Character spacing | Slider | |
| Word spacing | Slider | |
| Paragraph spacing | Slider | |
| Margins | Slider | |
| Text alignment | Picker | Publisher default, left, justified |
| Background colour | Swatches + custom | Paired with a text colour that keeps contrast legal |
| Brightness | Slider | Reader-local screen brightness, independent of the system slider |

#### Scenario: Font size is stepped, not continuous
- **WHEN** a user taps the smaller or larger control
- **THEN** the size moves one step and the step position is shown
- **AND** the step scale spans at least seven steps from smallest to largest

#### Scenario: Every axis states its value
- **WHEN** an axis control is shown
- **THEN** its current value is stated beside it in the reader's own language and units, and updates as the control moves
- **AND** the value is available to assistive technology as part of the control rather than as a separate unlabelled element

#### Scenario: An axis requires publisher styles to be off
- **WHEN** an axis that depends on publisher styles being disabled is displayed while they are enabled
- **THEN** the control is shown unavailable with a one-line reason and a single action that turns publisher styles off
- **AND** turning them off preserves the reading position

#### Scenario: Brightness is reader-local
- **WHEN** a user changes reader brightness
- **THEN** the change applies while the reader is open and is reverted on leaving it
- **AND** the system brightness is not permanently modified

#### Scenario: Resetting an axis
- **WHEN** a user long-presses or double-taps a slider
- **THEN** that axis returns to its preset value

### Requirement: Custom colour

The app SHALL let a user choose a reading background colour beyond the presets,
and SHALL keep the pairing readable.

#### Scenario: Choosing a background
- **WHEN** a user picks a background colour
- **THEN** a text colour is derived that meets at least 7:1 contrast against it, and both are shown in the preview before being applied
- **AND** the user may override the derived text colour, but a pairing below 4.5:1 is refused with the measured ratio stated

#### Scenario: Custom colour and the six presets
- **WHEN** a custom colour is in use
- **THEN** it is stored as a seventh, user-named slot alongside the six presets rather than overwriting one

#### Scenario: Fixed-layout and image content
- **WHEN** a custom background is set and the publication is fixed-layout, a comic, or a scanned PDF
- **THEN** the background applies to the area around the page and not to the page itself, because tinting artwork is not a reading preference

### Requirement: Theme scope and persistence

A reading theme SHALL persist at the level the user would expect and no wider.

#### Scenario: Per-series memory
- **WHEN** a user sets a theme while reading a publication
- **THEN** it applies to every publication in the same series
- **AND** a global default applies to series never opened before

#### Scenario: Separate defaults for reflowable and fixed-layout
- **WHEN** a user sets a theme on a reflowable publication
- **THEN** it does not change the theme used for comics or fixed-layout publications, which have their own default

#### Scenario: Changing the global default
- **WHEN** a user changes reading defaults in settings
- **THEN** it applies to publications opened from then on and does not overwrite a per-series choice already made
