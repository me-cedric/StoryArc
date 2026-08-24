## MODIFIED Requirements

### Requirement: Adaptive layout

The app SHALL adapt to every form factor its platform runs on, following the
platform's own reading-app conventions rather than scaling one layout.

#### Scenario: Tablet and large screens
- **WHEN** the app runs on an iPad or an Android tablet
- **THEN** it uses a multi-column layout with a persistent sidebar, not a stretched phone layout
- **AND** the sidebar carries the library's sections and collections, with the content area showing the continue row and the cover grid — the structure a reader on that platform already knows

#### Scenario: Split View, Slide Over and multi-window
- **WHEN** the app is resized on iPad or in Android multi-window
- **THEN** the layout reflows continuously and reading position is preserved through the resize
- **AND** the sidebar collapses to an overlay below the layout's regular width rather than being truncated

#### Scenario: Foldables
- **WHEN** an Android foldable is unfolded, folded, or half-opened
- **THEN** the layout follows the posture, and the reader avoids placing a page's focal area across the hinge

#### Scenario: Orientation
- **WHEN** the device rotates
- **THEN** the reader keeps the current page and the library keeps its scroll position

#### Scenario: Theme sheet on a large screen
- **WHEN** the theme sheet is opened on a tablet
- **THEN** it presents as a popover anchored to its control rather than a full-width sheet, and the reader stays visible beside it
- **AND** the live preview remains large enough to judge a spacing change

## ADDED Requirements

### Requirement: Reader chrome material

Reader chrome SHALL use each platform's own floating-surface material, and each
SHALL declare its opaque fallback.

#### Scenario: iOS reader chrome
- **WHEN** the iOS reader shows its bars or the theme sheet
- **THEN** they float over the page on Liquid Glass, grouped so overlapping glass shapes morph as one
- **AND** the glass is left untinted so it picks up the page beneath it
- **AND** the page is never resized or shifted when chrome appears

#### Scenario: Android reader chrome
- **WHEN** the Android reader shows its bars or the theme sheet
- **THEN** they use Material 3 Expressive surfaces at the appropriate tonal elevation, and the sheet is a modal bottom sheet that respects the Expressive motion scheme during drag
- **AND** the sheet is composed of Material components rather than a translation of the iOS sheet — tonal cards for presets, Material sliders for the axes

#### Scenario: Reduced transparency
- **WHEN** Reduce Transparency or its Android equivalent is on
- **THEN** every translucent chrome surface is replaced by its declared opaque fill and borders are strengthened

#### Scenario: The preset grid on both platforms
- **WHEN** the six presets are shown
- **THEN** each is a tappable card previewing its own background and typeface, laid out in a grid of three by two
- **AND** the card's own colours are used for its preview, so the grid reads as six samples rather than six labels

### Requirement: Theme sheet reachability

Changing how the page looks SHALL never cost the reader their place.

#### Scenario: Opening the sheet
- **WHEN** a user opens the theme sheet from reader chrome
- **THEN** the current page stays visible behind it and the reading position is unchanged
- **AND** the sheet is dismissible by drag, by a close control, and by tapping outside it

#### Scenario: Applying a change with the sheet open
- **WHEN** a user changes any axis while the sheet is open
- **THEN** the page behind the sheet updates immediately, so the effect is visible on real content and not only in the preview
- **AND** the reading position is preserved to the paragraph across a reflow
