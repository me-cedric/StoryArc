## MODIFIED Requirements

### Requirement: Dynamic colour

The app SHALL adopt each platform's dynamic-colour behaviour, and SHALL keep
wallpaper-derived and cover-derived colour off the surfaces where they would
compete with artwork.

#### Scenario: Android dynamic colour
- **WHEN** the Android app runs on a device with Material You dynamic colour
- **THEN** the app's scheme derives from the user's wallpaper by default, with a setting to use the StoryArc palette instead
- **AND** it applies to chrome — navigation, search, app bars, sheets, dialogs and settings — while the surfaces a reader browses artwork on keep the StoryArc neutrals, because a wallpaper-derived wash across a wall of covers takes away the one thing a reader is telling books apart by

#### Scenario: Cover-derived accent
- **WHEN** a publication's own page is shown, or the reader is open, or the home surface leads with a single publication
- **THEN** accent and background tinting derive from that publication's cover art
- **AND** the derived colour is adjusted until it meets the contrast floor in the design tokens, rather than being used raw
- **AND** it is applied to content surfaces only: floating chrome stays untinted so it picks up whatever is beneath it, and never changes hue as the reader scrolls past covers

#### Scenario: Chrome accent
- **WHEN** a surface has no publication context — settings, source management, the empty library
- **THEN** it uses the StoryArc brand accent, not a cover-derived one
- **AND** that accent is a single colour: the brand's pink-to-violet arc belongs to the mark, the app icon and brand surfaces, and chrome that gradients fights the direction the palette is built on

#### Scenario: A cover that yields no usable colour
- **WHEN** a cover is missing, cannot be decoded, or yields no colour that clears the contrast floor
- **THEN** the surface falls back to the StoryArc brand accent
- **AND** nothing is left unreadable, and no surface is left mid-transition between a derived colour and the fallback

#### Scenario: State colour survives every scheme
- **WHEN** a publication is marked as downloaded, unread, or belonging to a source that cannot be reached
- **THEN** those marks use the fixed status tokens rather than any derived colour
- **AND** they read the same under a wallpaper-derived scheme, a cover-derived wash, and the StoryArc palette
