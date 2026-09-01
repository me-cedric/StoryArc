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
- **THEN** the stored choice is re-applied if the platform still honours it, and the default is used if it does not
- **AND** what the chooser shows as current is what was actually applied, not what was stored

#### Scenario: The platform stops honouring it
- **WHEN** the platform or launcher no longer supports changing the icon
- **THEN** the app falls back to the icon it ships with and the chooser says the platform is not offering the choice
- **AND** the stored preference is kept rather than erased, so a launcher that supports it again restores what the reader picked
