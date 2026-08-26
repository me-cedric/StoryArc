# settings-and-about Specification

## Purpose

Settings, and the About screen that tells people who made this and that it costs
nothing.

## Requirements

### Requirement: Appearance

The app SHALL offer System, Light, and Dark appearance, defaulting to System.

#### Scenario: Choosing appearance
- **WHEN** a user selects an appearance
- **THEN** it applies immediately across the whole app without a restart, and persists

#### Scenario: Following the system
- **WHEN** appearance is System and the device switches theme
- **THEN** the app follows, including while it is in the background

#### Scenario: Reader theme is separate
- **WHEN** a user changes app appearance
- **THEN** the reading theme is not overridden, because a dark app chrome with a paper-white page is a legitimate preference

### Requirement: Settings organisation

Settings SHALL be grouped so that a person can find one without reading all of them.

#### Scenario: Structure
- **WHEN** a user opens settings
- **THEN** they see Sources, Appearance, Reading, Downloads and storage, Language, Privacy, and About
- **AND** each group's summary row states its current value, so a setting can be checked without entering the group

#### Scenario: Searching settings
- **WHEN** a user searches settings
- **THEN** matching settings are listed with their group path, and selecting one navigates there and highlights it

#### Scenario: Reading defaults
- **WHEN** a user changes a reading default
- **THEN** it applies to publications opened from then on and does not overwrite a per-series choice already made

#### Scenario: Resetting
- **WHEN** a user resets settings to defaults
- **THEN** the app confirms and states explicitly that sources, downloads, and reading progress are not affected

### Requirement: Privacy

The app SHALL make its privacy posture verifiable rather than merely stated.

#### Scenario: Privacy screen
- **WHEN** a user opens the privacy section
- **THEN** it states that StoryArc has no account, no backend, no analytics, and no crash reporting, and that data leaves the device only to the sources the user configured

#### Scenario: Clearing data
- **WHEN** a user clears data
- **THEN** cache, reading history, and downloads are individually clearable, each stating what it removes and how much space it frees

#### Scenario: Exporting a diagnostic
- **WHEN** a user exports diagnostics to file a bug
- **THEN** the export is shown in full before it can be shared, and every credential, token, and server hostname is redacted
- **AND** the export carries no free text the user wrote, so a name they chose cannot carry a hostname past the redaction

### Requirement: About

The app SHALL include an About screen identifying the author and stating that
the app is free.

#### Scenario: About contents
- **WHEN** a user opens About
- **THEN** the screen shows the app version and build, the author "Cédric Meyer", a link to <https://github.com/me-cedric>, a link to the StoryArc repository, and the licence

#### Scenario: Support link
- **WHEN** a user opens About
- **THEN** it states that StoryArc is completely free and open source with no paid tier and no advertising, and offers an optional link to <https://ko-fi.com/mecedric>
- **AND** the support link is never presented as a prompt, an interstitial, or a nag — it appears only on this screen

#### Scenario: Acknowledgements
- **WHEN** a user opens acknowledgements
- **THEN** every third-party library is listed with its licence text

#### Scenario: Reporting a problem
- **WHEN** a user chooses to report a problem
- **THEN** the app opens the repository's issue tracker with the app version, platform version, and device class pre-filled, and no personal data
