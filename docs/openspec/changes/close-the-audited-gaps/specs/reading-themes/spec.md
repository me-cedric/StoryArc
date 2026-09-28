## MODIFIED Requirements

### Requirement: Theme presets

The app SHALL offer six named reading-theme presets, each setting a background
colour, a text colour, a typeface, and a spacing character.

| Preset | Character |
| --- | --- |
| **Original** | The publication as its publisher styled it. Publisher styles on; StoryArc's typeface, weight, margins and font size apply over them — hyphenation cannot, and stays in the unavailable-under-Original notice. |
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
- **THEN** publisher styles remain enabled, and StoryArc's typeface, bold weight, margins and font size still apply over the publisher's own styling
- **AND** the axes the platform cannot honour while publisher styles are on — starting with hyphenation — are shown as unavailable with a one-line explanation, not hidden and not shown as dead controls
- **AND** no axis is shown as a live control that silently changes nothing

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
- **AND** a user who wants them linked can enable that explicitly in settings, per [`settings-and-about`](../settings-and-about/spec.md) "Appearance", which is where the light preset and the dark preset that make up the linked pair are chosen

#### Scenario: Linked appearance resolves from the chosen pair
- **WHEN** the linked setting is on and the app appearance switches between light and dark
- **THEN** the reading theme switches to whichever preset the reader chose for that polarity — Paper for light and Quiet for dark until the reader changes them — not to a fixed default
- **AND** changing either half of the pair takes effect the next time that polarity is in force, without disturbing the other half or any per-series theme
