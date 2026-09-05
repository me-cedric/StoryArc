## ADDED Requirements

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
