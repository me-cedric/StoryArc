# native-experience Specification

## Purpose

The requirement that StoryArc feels like it shipped with the operating system.
This is the capability that says *no* — no shared UI layer, no invented
navigation, no custom control where a system one exists. It also owns
accessibility, because an app that ignores Dynamic Type or TalkBack is not
native no matter what it looks like.

## Requirements

### Requirement: Platform-native interface

Each app's interface SHALL be built with its own platform's native toolkit and
SHALL follow that platform's current design language.

#### Scenario: iOS interface
- **WHEN** the iOS app renders any screen
- **THEN** it is SwiftUI using system navigation, system controls and system materials
- **AND** floating chrome uses Liquid Glass, with scroll edge effects at content boundaries and an opaque fallback declared for Reduce Transparency

#### Scenario: Android interface
- **WHEN** the Android app renders any screen
- **THEN** it is Jetpack Compose using Material 3 Expressive components, shapes, motion and elevation
- **AND** it draws edge to edge and handles window insets rather than avoiding them

#### Scenario: No cross-platform UI
- **WHEN** any interface code is written
- **THEN** it lives in exactly one platform's codebase
- **AND** no web view, cross-platform toolkit, or shared UI abstraction renders any part of the interface other than reflowable EPUB content, which is HTML by definition

#### Scenario: System integration
- **WHEN** the platform offers a system affordance the app needs
- **THEN** the system one is used — share sheet, document picker, context menu, haptics, quick actions, widgets, Handoff on iOS, and predictive back on Android

#### Scenario: Home-screen quick actions
- **WHEN** the app icon is held down
- **THEN** the menu offers the publication in progress, named, followed by the library, followed by downloads once anything has been downloaded
- **AND** the entries survive the app being killed, because the system stores them rather than the app
- **AND** choosing the library lands on the shelf rather than on wherever the app was last left
- **AND** every entry is localised in each supported language

#### Scenario: Continuity
- **WHEN** a publication is being read
- **THEN** iOS publishes it as a user activity, so the reader's other devices offer to continue it and the publication appears in Spotlight
- **AND** Android reports the same publication to the launcher as a used shortcut, so the launcher and the Assistant can surface it
- **AND** neither platform carries the reading position between devices, because there is no backend to carry it

#### Scenario: A publication a continuity handover names is no longer there
- **WHEN** a quick action or a handover names a publication the library cannot place
- **THEN** the app lands on the library rather than on an error, and the entry is replaced the next time the menu is published

### Requirement: Dynamic colour

The app SHALL adopt each platform's dynamic-colour behaviour.

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

#### Scenario: Theme sheet on a large screen
- **WHEN** the theme sheet is opened on a tablet
- **THEN** it presents as a popover anchored to its control rather than a full-width sheet, and the reader stays visible beside it

#### Scenario: Foldables
- **WHEN** an Android foldable is unfolded, folded, or half-opened
- **THEN** the layout follows the posture, and the reader avoids placing a page's focal area across the hinge

#### Scenario: Orientation
- **WHEN** the device rotates
- **THEN** the reader keeps the current page and the library keeps its scroll position

### Requirement: Reader chrome material

Reader chrome SHALL use each platform's own floating-surface material, and each
SHALL declare its opaque fallback. What that fallback is, and when it replaces
the material, is the *Contrast and transparency* scenario below.

#### Scenario: iOS reader chrome
- **WHEN** the iOS reader shows its bars or the theme sheet
- **THEN** they float over the page on Liquid Glass, grouped so overlapping glass shapes morph as one
- **AND** the glass is left untinted so it picks up the page beneath it
- **AND** the page is never resized or shifted when chrome appears

#### Scenario: Android reader chrome
- **WHEN** the Android reader shows its bars or the theme sheet
- **THEN** they use Material 3 Expressive surfaces at the appropriate tonal elevation, and the sheet is a modal bottom sheet that respects the Expressive motion scheme during drag
- **AND** the sheet is composed of Material components rather than a translation of the iOS sheet — tonal cards for presets, Material sliders for the axes

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

### Requirement: Accessibility

The app SHALL be usable by someone who cannot see it, cannot see it well, or
cannot make precise gestures.

#### Scenario: Screen reader
- **WHEN** VoiceOver or TalkBack is on
- **THEN** every control has a meaningful label, reading order matches visual order, and images that carry meaning have descriptions
- **AND** the reader announces the page number and total on each turn, and offers gestures to turn pages

#### Scenario: Dynamic Type and font scale
- **WHEN** the system text size is raised to its maximum
- **THEN** every screen remains usable with no clipped or overlapping text, and the library falls back to a list layout when covers would leave no room for legible titles

#### Scenario: Contrast and transparency
- **WHEN** Increase Contrast or Reduce Transparency is on
- **THEN** translucent materials are replaced with the opaque fallback declared in the design tokens, and borders are strengthened

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is on
- **THEN** page-curl and parallax are replaced by cross-dissolves, and no purely decorative animation plays

#### Scenario: Touch targets
- **WHEN** any interactive control is rendered
- **THEN** its touch target is at least 44 pt on iOS and 48 dp on Android, including reader chrome controls

#### Scenario: Keyboard and switch control
- **WHEN** an external keyboard or a switch device is used
- **THEN** every screen is fully navigable, focus is always visible, and the reader supports page turns and chrome toggling

#### Scenario: Colour is never the only signal
- **WHEN** state is communicated — downloaded, unread, offline, failed
- **THEN** it is carried by an icon, a label or a shape as well as by colour

### Requirement: Performance and responsiveness

The app SHALL feel immediate.

#### Scenario: Cold launch
- **WHEN** the app is launched cold
- **THEN** the library is interactive within 1.5 seconds on a mid-range device from the last four years

#### Scenario: Scrolling
- **WHEN** a user scrolls a library of 10,000 publications
- **THEN** the frame rate holds at the display's refresh rate, and dropped frames during a scroll are treated as a defect

#### Scenario: No blocking spinners
- **WHEN** content is loading
- **THEN** the app shows the structure it already knows with placeholders, rather than a full-screen spinner

#### Scenario: Memory
- **WHEN** a user reads a large publication for an extended session
- **THEN** memory stays within the platform's budget and the app is not terminated in the background for exceeding it

### Requirement: Visual proof of interface changes

Every change a user can see SHALL be verified against a running app on a real
simulator or emulator, not against a preview.

#### Scenario: Screen change
- **WHEN** a change alters what any screen renders
- **THEN** a screenshot from a booted simulator or emulator is captured at the project's device matrix and compared against the reference

#### Scenario: Preview is not proof
- **WHEN** a change is verified
- **THEN** a SwiftUI `#Preview` or a Compose `@Preview` alone does not satisfy the requirement, because neither exercises real data, real insets, or real system materials

#### Scenario: Both appearances
- **WHEN** a screen changes
- **THEN** it is verified in light and dark appearance, and at the default and the largest text size

### Requirement: The icon a reader chose

A chosen app icon SHALL survive everything short of the platform withdrawing the ability, and
the app SHALL never claim an icon is in use that the launcher is not drawing — except where the
system is drawing a tinted form of the icon itself, which no app is told about and none can
detect.

#### Scenario: Surviving a reinstall or a restore
- **WHEN** the app is restored from a platform backup, or reinstalled on a device where a non-default icon had been chosen
- **THEN** the icon the platform is drawing is the icon the chooser shows as current, whatever the restore left behind
- **AND** the default is shown as current when the platform is drawing the default

#### Scenario: The platform refuses the change
- **WHEN** the platform declines to change the icon, at the moment a reader picks one
- **THEN** the chooser says so, naming the icon that is still in use, and does not show the picked one as current
- **AND** the refusal is not retried unprompted, so a reader who cannot have a face is told once rather than on every visit

#### Scenario: The platform withdraws the ability
- **WHEN** the platform does not offer a choice of app icon on this device at all
- **THEN** the chooser says so before a reader tries, rather than offering five faces and refusing each in turn
- **AND** no face is shown as in use, and nothing is asked of the platform

#### Scenario: The system draws its own tinted icon
- **WHEN** the system replaces the app's icon art with a tinted form of one layer of it, as Android's themed icons do
- **THEN** every face reduces to that one layer's art, and the app neither works around it nor claims otherwise — the layer it ships is real single-colour art, so the mark's internal divisions survive being tinted flat
- **AND** the chosen face is still recorded and unchanged, so it returns as itself when the system stops tinting

#### Scenario: The platform is the only record
- **WHEN** the app needs to know which icon is in use
- **THEN** it asks the platform rather than a preference of its own, so there is no second record that can disagree
- **AND** nothing about the choice is written to preferences, a backup, a log or a diagnostic

### Requirement: Chrome for a mode a reader is in

When the app puts a reader into a mode — selecting several publications is the one that
exists — the chrome for that mode SHALL take the place of the surface it belongs to rather
than stacking on top of it, and SHALL take each platform's own form for a contextual mode.

A mode is temporary and a reader has to be able to leave it. So the way out SHALL be
present and SHALL NOT be one of the mode's own actions, which are inert until something is
picked.

> **This requirement is written after the behaviour, and that is worth saying.** The
> selection chrome shipped as a full-bleed bar stacked above the tab bar, and nothing in the
> specs made that wrong — `collections-and-reading-lists` says a reader may select in bulk,
> and `native-experience` asks for the platform's conventions in general terms. Neither
> reaches the shape. The owner reported it twice before it was fixed, which is what a missing
> requirement costs.

#### Scenario: The mode replaces its surface rather than stacking on it
- **WHEN** a reader is selecting publications
- **THEN** the mode's actions occupy the place the destination's own primary navigation held, and the two are never drawn at once
- **AND** the actions carry the same material and shape as the chrome they replaced, so the surface still reads as one app — though a platform may change its **tone** to mark the mode, where that platform's convention asks a contextual bar to read as a different bar rather than the same one with different buttons

#### Scenario: How many are chosen, and how to leave
- **WHEN** a selection is running
- **THEN** the number chosen is stated where the surface names itself, not inside the row of actions
- **AND** one action leaves the mode, it is not among the actions that operate on the selection, and it is never disabled

#### Scenario: Nothing chosen yet
- **WHEN** the mode has just been entered and nothing is selected
- **THEN** the actions are present and inert rather than absent
- **AND** an inert action is **drawn** inert, so a reader can tell it apart from a live one without pressing it
- **AND** entering or leaving the mode does not move the content under a reader's thumb mid-gesture

#### Scenario: Each platform's own form
- **WHEN** the mode is drawn on each platform
- **THEN** it follows that platform's convention for a contextual mode rather than a translation of the other's
- **AND** where the two therefore differ, each platform's source says which convention it is following

#### Scenario: Every action names itself
- **WHEN** assistive technology reaches an action in the mode
- **THEN** it is announced by name whatever the action draws
- **AND** an action drawn as a glyph alone is one whose meaning the platform already establishes **on this screen** — a mark another control in the same frame already uses for something else is not established here, whatever it means elsewhere
- **AND** where the width will not hold a name, the action moves into a named menu rather than being reduced to a glyph a reader cannot read, so narrowing costs a reader taps and never meaning
