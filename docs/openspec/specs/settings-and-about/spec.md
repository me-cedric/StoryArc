# settings-and-about Specification

## Purpose

Settings, and the About screen that tells people who made this and that it costs
nothing.

## Requirements

### Requirement: Appearance

The app SHALL offer System, Light, Dark and OLED Dark appearances, defaulting to
System.

| Option | What it is |
| --- | --- |
| **System** | Follows the device. The default. |
| **Light** | Warm paper neutrals. |
| **Dark** | Warm ink neutrals. |
| **OLED Dark** | True black surfaces, for OLED panels where black draws no power. |

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

#### Scenario: Reader theme is separate
- **WHEN** a user changes app appearance
- **THEN** the reading theme is not overridden, because a dark app chrome with a paper-white page is a legitimate preference
- **AND** a single opt-in setting links them for users who want that instead

### Requirement: Choosing the app icon

The app SHALL let a reader choose its icon from a fixed set the app ships, and SHALL be
honest about what the platform can and cannot do with that choice.

The set is faces of one mark, not different marks: a reader picking a lighter tile is still
holding StoryArc. Anything that would make the app unrecognisable on a home screen is not an
option here.

#### Scenario: Choosing one
- **WHEN** a reader opens the icon chooser and picks a face
- **THEN** each option is shown as the icon it actually is, at the size a home screen draws it, with the current one marked
- **AND** the choice persists across launches, and across an appearance change — an icon is not a theme
- **AND** where the system draws its own tinted form of the icon rather than the app's art — Android's themed icons, which flatten every face to the one monochrome layer — what the chooser marks is the face that was picked, which is what returns when the system stops tinting, rather than a promise about what the launcher is drawing this minute

#### Scenario: What the platform does with it
- **WHEN** a reader picks an icon on iOS
- **THEN** it changes there and then, and the app does not present a system alert it did not ask for
- **AND** on Android the choice is applied and the reader is told it appears the next time the launcher draws its list, because that platform offers no way to change it in place

#### Scenario: Going back to the default
- **WHEN** a reader chooses the default face
- **THEN** the app returns to the icon it ships with, by the same route as any other choice
- **AND** the default is marked as the default, so a reader can find it without remembering which one it was

#### Scenario: Where it lives
- **WHEN** a reader looks for it
- **THEN** it sits beside Appearance, because both answer "what does the app look like", and it is reachable by the same search that finds every other setting

#### Scenario: The platform refuses
- **WHEN** the platform declines the change — an unsupported device, a launcher that does not honour it, an error from the system
- **THEN** the app says the icon could not be changed, and names which one is still in use where one is
- **AND** where no icon is in use at all — reachable on Android, where the aliases can all be disabled from outside the app, and structurally unreachable on iOS, where the absence of an alternate icon *is* the default — it says the change was refused without naming a face, because there is none to name
- **AND** it does not retry silently, because an icon that changes minutes later with no action is indistinguishable from a bug

#### Scenario: At the largest text size
- **WHEN** the chooser is shown at the largest accessibility text size
- **THEN** every option's name is readable in full and its tile is still large enough to tell the faces apart, the list scrolling if it must

#### Scenario: Announced without sight
- **WHEN** a screen reader reaches an option
- **THEN** it is announced by name and by whether it is the one in use, and never as an unlabelled image
- **AND** the tile itself is decorative to assistive technology, because the name is what identifies it

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
### Requirement: What changed in this version

The app SHALL tell a reader what changed, once, after it has been updated, and SHALL
never let that get in the way of reading.

A reading app is opened to read. Everything below follows from that: the notice is
shown once per version, it is dismissed by one action, it never appears on a first
ever launch, and it is reachable afterwards for somebody who dismissed it too fast.

#### Scenario: After an update
- **WHEN** a reader opens the app for the first time after it has been updated
- **THEN** a screen names the version and lists what changed in it, in the reader's own language
- **AND** one action dismisses it, and it is not shown again for that version

#### Scenario: A first ever launch
- **WHEN** a reader opens the app for the first time ever
- **THEN** the screen does not appear, because somebody who has never used the app has nothing to catch up on
- **AND** the version is recorded as seen, so the next update is the first thing they are told about

#### Scenario: Nothing worth saying
- **WHEN** a version ships with nothing a reader would notice
- **THEN** no screen appears
- **AND** the version is still recorded as seen, so the entry is not shown late alongside the next one

#### Scenario: Reading it again
- **WHEN** a reader wants to see what changed after dismissing the screen
- **THEN** it is reachable from the About screen, along with the entries for earlier versions
- **AND** reaching it that way does not change what the app considers seen

#### Scenario: An update installed while offline
- **WHEN** the app is opened after an update with no network
- **THEN** the screen appears in full, because what changed ships with the app and is never fetched

#### Scenario: At the largest text size
- **WHEN** the screen is shown at the largest accessibility text size
- **THEN** every entry's heading and sentence are readable in full, the screen scrolls if it must, and the dismissing action stays reachable without scrolling past the content

