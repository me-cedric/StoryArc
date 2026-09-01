## ADDED Requirements

### Requirement: What could not be opened

The library SHALL say **which** publications it could not open, not how many, and SHALL let a
reader reach the reason.

`publication-formats` words every refusal precisely — a solid RAR4 says it uses solid
compression, a CB7 names 7-Zip, a locked audiobook names its store's content protection — and
the library currently aggregates all of that into a count. The count is the one form of the
message that helps nobody.

#### Scenario: One publication could not be opened
- **WHEN** a scan or an import finds exactly one publication it cannot open
- **THEN** the notice names that publication and states the reason in the words `publication-formats` gives for it
- **AND** it offers a way to act on it — reaching the file, or dismissing it from the list

#### Scenario: Several could not be opened
- **WHEN** more than one cannot be opened
- **THEN** the notice states how many and leads to a list naming each with its own reason
- **AND** the reasons are not merged: two files that failed differently say different things

#### Scenario: The notice is not on a timer
- **WHEN** the notice is shown
- **THEN** it stays until the reader dismisses it or resolves it
- **AND** it does not float over the shelf's content in a way that obscures a cover, because a message about a durable problem that removes itself is a message designed to be missed

#### Scenario: Reaching it later
- **WHEN** a reader dismisses the notice
- **THEN** the list remains reachable from the library, so a reader who dismissed it in the middle of something can come back to it
- **AND** the count is not shown again for the same publications unless the set changes

#### Scenario: A publication that later opens
- **WHEN** a publication that had failed is opened successfully — it was re-downloaded, or a share came back
- **THEN** it leaves the list without being dismissed by hand
- **AND** the notice disappears when the list empties

#### Scenario: Announced without sight
- **WHEN** a screen reader reaches the notice
- **THEN** it is announced once, naming the publication where there is one and the count where there are several, and it does not steal focus from the shelf
- **AND** the way to the list is a control with a name, not the whole notice

## MODIFIED Requirements

### Requirement: Presentation

The app SHALL offer a cover grid and a compact list, and SHALL adapt density to
the display.

The controls that change what the shelf shows SHALL be grouped rather than laid out as a row
of similar icons. A reader who cannot tell two adjacent controls apart has as many controls as
they can name.

> This adds the grouping rule. The three scenarios below are carried unchanged, because a
> MODIFIED requirement replaces the whole block.

#### Scenario: Switching layout
- **WHEN** a user switches between grid and list
- **THEN** the choice persists per scope, so a dense list for one library does not force it everywhere

#### Scenario: Adaptive columns
- **WHEN** the app is shown on a phone, a tablet, a foldable in either posture, or an iPad in Split View
- **THEN** the number of grid columns follows the available width, and cover size stays within the readable range defined in the design tokens

#### Scenario: Progress on covers
- **WHEN** a publication is partially read
- **THEN** its cover carries an unobtrusive progress indicator
- **AND** a fully read publication is distinguishable at a glance without a label covering the artwork

#### Scenario: The controls that change the view are grouped
- **WHEN** the library's own controls are shown
- **THEN** the choices — what is shown, how it is grouped, how it is sorted, what is filtered out — are reached through named menus rather than as separate unlabelled buttons
- **AND** a control that changes *mode* rather than presenting a choice may stand on its own, because entering selection is not the same kind of act as picking a sort

#### Scenario: A control that stands alone carries a name
- **WHEN** a control is not inside a menu
- **THEN** it is identifiable without being pressed — by a label, or by a symbol whose meaning the platform already establishes
- **AND** every one of them names itself to assistive technology whatever it draws

#### Scenario: An ordering says that it is an ordering
- **WHEN** the current sort is shown on a control
- **THEN** it reads as an ordering rather than as a value — a reader seeing the field name alone cannot tell a sort from a filter
- **AND** the same holds for grouping, which is neither
