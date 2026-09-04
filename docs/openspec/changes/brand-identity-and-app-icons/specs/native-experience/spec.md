## MODIFIED Requirements

### Requirement: Dynamic colour

The app SHALL adopt each platform's dynamic-colour behaviour.

> Only *Chrome accent* changes: it gains the sentence that the brand accent is one colour and
> that the pink-to-violet arc belongs to the identity rather than to chrome. The other two
> scenarios are carried unchanged, because a MODIFIED requirement replaces the whole block.

#### Scenario: Android dynamic colour
- **WHEN** the Android app runs on a device with Material You dynamic colour
- **THEN** the app's scheme derives from the user's wallpaper by default, with a setting to use the StoryArc palette instead

#### Scenario: Cover-derived accent
- **WHEN** a publication detail screen or the reader is shown
- **THEN** accent and background tinting derive from the publication's cover art
- **AND** the derived colour is adjusted until it meets the contrast floor in the design tokens, rather than being used raw

#### Scenario: Chrome accent
- **WHEN** a surface has no publication context — settings, source management, the empty library
- **THEN** it uses the StoryArc brand accent, not a cover-derived one
- **AND** that accent is a single colour: the brand's pink-to-violet arc belongs to the mark, the app icon and brand surfaces, and chrome that gradients fights the direction the palette is built on

## ADDED Requirements

### Requirement: The icon a reader chose

A chosen app icon SHALL survive everything short of the platform withdrawing the ability, and
the app SHALL never claim an icon is in use that the launcher is not drawing.

#### Scenario: Surviving a reinstall or a restore
- **WHEN** the app is restored from a platform backup, or reinstalled on a device where a non-default icon had been chosen
- **THEN** the icon the platform is drawing is the icon the chooser shows as current, whatever the restore left behind
- **AND** the default is shown as current when the platform is drawing the default

#### Scenario: The platform refuses the change
- **WHEN** the platform declines to change the icon, at the moment a reader picks one
- **THEN** the chooser says so, naming the icon that is still in use, and does not show the picked one as current
- **AND** the refusal is not retried unprompted, so a reader who cannot have a face is told once rather than on every visit

#### Scenario: The platform is the only record
- **WHEN** the app needs to know which icon is in use
- **THEN** it asks the platform rather than a preference of its own, so there is no second record that can disagree
- **AND** nothing about the choice is written to preferences, a backup, a log or a diagnostic
