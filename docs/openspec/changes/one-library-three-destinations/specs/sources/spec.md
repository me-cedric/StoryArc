## MODIFIED Requirements

### Requirement: Source registry

The app SHALL maintain an ordered, persistent registry of configured sources,
each with a user-editable display name, a type, a connection state, and the
timestamp of its last successful sync.

#### Scenario: Adding the first source
- **WHEN** a reader opens the app with nothing configured
- **THEN** they are shown one sentence in plain language, one primary action that opens a comic from the device with nothing to configure first, and one plain secondary action that leads to connecting a library
- **AND** the four source types are named only after that secondary action is taken, where choosing between them is the question being asked
- **AND** the first screen never presents the source types as a list to be understood before the app can be used
- **AND** the surface that names the four is the library destination's own empty state; the home surface's secondary opens a folder directly, because a reader who has not yet seen a shelf has not yet asked the question the four are an answer to
- **AND** a reader who arrives on the home surface can still reach the four in one move, because the library destination is one of the three the navigation control always offers

#### Scenario: Reordering sources
- **WHEN** a reader drags a source into a new position in the source list
- **THEN** the new order persists across launches
- **AND** the library's combined view lists titles from higher sources first when two sources hold the same publication

#### Scenario: Renaming a source
- **WHEN** a reader edits a source's display name
- **THEN** the new name appears everywhere the source is referenced — settings, download attributions, error messages, and the by-library filter
- **AND** it does not appear on the browse path anywhere else, per [`navigation-shell`](../navigation-shell/spec.md)

#### Scenario: Removing a source
- **WHEN** a reader removes a source
- **THEN** the app states how many downloaded files and how much disk space will be freed before asking for confirmation
- **AND** on confirmation removes the source, its cached metadata, its stored credentials, and its downloads
- **AND** retains local reading progress for those publications for 30 days, so re-adding the same source restores where the reader stopped
