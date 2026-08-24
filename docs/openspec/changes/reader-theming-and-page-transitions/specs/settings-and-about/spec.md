## MODIFIED Requirements

### Requirement: Appearance

The app SHALL offer System, Light, Dark and OLED Dark appearances, defaulting to
System, plus Natural as a theme that sits alongside them rather than inside the
light/dark polarity.

| Option | What it is |
| --- | --- |
| **System** | Follows the device. The default. |
| **Light** | Warm paper neutrals. |
| **Dark** | Warm ink neutrals. |
| **OLED Dark** | True black surfaces, for OLED panels where black draws no power. |
| **Natural** | A theme rather than an appearance: paper texture and warm accents across reading surfaces. Carries its own light and dark variants. |

#### Scenario: Choosing appearance
- **WHEN** a user selects an appearance
- **THEN** it applies immediately across the whole app without a restart, and persists

#### Scenario: Following the system
- **WHEN** appearance is System and the device switches theme
- **THEN** the app follows, including while it is in the background

#### Scenario: OLED Dark is not the same as Dark
- **WHEN** a user selects OLED Dark
- **THEN** app surfaces become true black
- **AND** the reader surface stays marginally above true black, because pure black smears on OLED during a page turn — the setting is honoured where it helps and explained where it does not

#### Scenario: Natural carries texture
- **WHEN** Natural is selected
- **THEN** reading surfaces gain a subtle paper grain and warm accent treatment
- **AND** the texture is disabled automatically when Reduce Transparency or Increase Contrast is on, because grain lowers effective contrast

#### Scenario: Reader theme is separate
- **WHEN** a user changes app appearance
- **THEN** the reading theme is not overridden, because a dark app chrome with a paper-white page is a legitimate preference
- **AND** a single opt-in setting links them for users who want that instead
