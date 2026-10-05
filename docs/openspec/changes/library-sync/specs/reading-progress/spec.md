## MODIFIED Requirements

### Requirement: Conflict resolution

The app SHALL resolve conflicting progress predictably and SHALL NOT silently
move a user backwards. It SHALL record what was last synchronised, because every
clause below asks whether a side changed "since the last sync" and nothing can
answer that without it.

#### Scenario: The last-synchronised position is recorded
- **WHEN** a position is synchronised, in either direction, with a server or with a sync document
- **THEN** the app records that position as the one last synchronised for that publication
- **AND** it does so in the path production uses, not only in a test, because a watermark nothing writes makes every clause below decide on an absent value

#### Scenario: A device that has never synchronised
- **WHEN** progress is reconciled on a device that holds no last-synchronised position for that publication
- **THEN** the absence is treated as "nothing is known about the other side", never as proof that the local side changed
- **AND** the further position still wins, so a first sync onto a new device does not announce a conflict that did not happen

#### Scenario: Remote is further ahead
- **WHEN** the remote position is ahead of the local one and the local record has not changed since the last sync
- **THEN** the remote position is adopted silently

#### Scenario: Both changed since the last sync
- **WHEN** both the local and the remote position changed since the last successful sync
- **THEN** the app adopts the further position, and tells the user once, naming both positions and offering to use the other one

#### Scenario: Remote is behind
- **WHEN** the remote position is behind the local one
- **THEN** the local position is kept and pushed to the server

#### Scenario: Conflicting finished state
- **WHEN** one side reports finished and the other reports partial
- **THEN** finished wins, because unmarking a finished publication is a deliberate act and losing it is not
