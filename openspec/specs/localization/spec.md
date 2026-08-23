# localization Specification

## Purpose

StoryArc ships in English, French, German and Spanish, following the system
language by default. Localisation is not a translation pass at the end; it is a
constraint on how every string, date, number and layout is written.

## Requirements

### Requirement: Supported languages

The app SHALL be fully localised in English, French, German and Spanish.

#### Scenario: Following the system
- **WHEN** the app launches
- **THEN** it uses the first supported language in the device's preferred-language order, falling back to English

#### Scenario: Overriding in the app
- **WHEN** a user picks a language in settings
- **THEN** the whole interface switches immediately without a restart, and the choice persists
- **AND** a "System" option returns to following the device

#### Scenario: Completeness
- **WHEN** the app is built
- **THEN** the build fails if any supported language is missing a key that English defines
- **AND** no user-visible string is hardcoded in a source file

### Requirement: Locale-correct formatting

The app SHALL format everything through platform locale services rather than
composing strings by hand.

#### Scenario: Dates and times
- **WHEN** a date is displayed
- **THEN** it uses the device's locale, calendar and time-zone conventions

#### Scenario: File sizes and counts
- **WHEN** a size or a count is displayed
- **THEN** it uses locale digit grouping and unit conventions

#### Scenario: Plurals
- **WHEN** a string contains a count
- **THEN** it uses the platform's plural rules, so languages with more than two plural forms are correct

#### Scenario: Sorting
- **WHEN** titles are sorted alphabetically
- **THEN** collation follows the interface language, and leading articles in that language are ignored

### Requirement: Layout resilience

The interface SHALL survive translation without truncating or overflowing.

#### Scenario: Long translations
- **WHEN** a German string is materially longer than its English source
- **THEN** the layout grows or wraps, and no label is truncated with an ellipsis in a way that loses meaning

#### Scenario: Pseudo-locale testing
- **WHEN** the app runs under an expanded pseudo-locale
- **THEN** no screen clips, overlaps, or hides a control

#### Scenario: Right-to-left readiness
- **WHEN** the app runs under a right-to-left system language
- **THEN** the interface mirrors correctly, even though no RTL interface language ships in 1.0
- **AND** reading direction inside the reader stays independent of interface direction, because a manga read right-to-left in a left-to-right interface is the normal case

### Requirement: Content language

Publication metadata SHALL be presented in its own language, not translated.

#### Scenario: Publication titles
- **WHEN** a publication's title is in a language other than the interface language
- **THEN** it is displayed as-is and is never machine-translated

#### Scenario: Server-provided labels
- **WHEN** a server provides genre or tag names
- **THEN** they are displayed as the server provides them, and only StoryArc's own interface chrome is translated
