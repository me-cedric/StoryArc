## MODIFIED Requirements

### Requirement: Collections

The app SHALL let a user create, rename, delete, and populate collections, and
SHALL display collections that a server already defines.

#### Scenario: Creating a collection
- **WHEN** a user creates a collection
- **THEN** it is stored locally by default, or on a server if the user chooses one that supports collections
- **AND** the storage location is stated at creation, not discovered later

#### Scenario: Adding to a collection
- **WHEN** a user adds publications to a collection
- **THEN** they can be selected in bulk from the library, and a publication may belong to any number of collections

#### Scenario: Cover for a collection
- **WHEN** a collection has contents
- **THEN** its cover is a composite of its first four member covers unless the user sets a specific one
- **AND** this holds for a collection a server defines exactly as it does for one made on the device

#### Scenario: Cover for a collection whose artwork cannot be fetched
- **WHEN** a member's cover cannot be fetched, because the source is unreachable or has removed it
- **THEN** the composite is built from the members whose covers are available, and a collection with none of them shows the same placeholder a publication with no cover shows
- **AND** the collection is never drawn as an empty frame

#### Scenario: Deleting a collection
- **WHEN** a user deletes a collection
- **THEN** the app confirms and states plainly that the publications themselves are not deleted

### Requirement: Reading lists

The app SHALL let a user create ordered reading lists and SHALL preserve their
order as the meaningful default.

#### Scenario: Ordering a list
- **WHEN** a user reorders entries by dragging
- **THEN** the new order persists and, for a server-backed list, is sent to the server

#### Scenario: Reading through a list
- **WHEN** a user finishes an entry in a reading list
- **THEN** the next entry in list order is offered, regardless of series or source

#### Scenario: Progress through a list
- **WHEN** a reading list is displayed
- **THEN** it shows how many entries are finished and where the user's position is
- **AND** each entry states its own read state — finished, part-read with the position reached, or unread — in the same terms the library uses for a publication
- **AND** this holds for a list a server defines exactly as it does for one made on the device

#### Scenario: An entry whose read state the source does not report
- **WHEN** a source reports no read state for an entry
- **THEN** the entry states nothing rather than an assumed zero, and the list's own count of finished entries excludes it rather than counting it unread

#### Scenario: Cover for a reading list
- **WHEN** a reading list has entries
- **THEN** its cover is a composite of its first four entry covers in list order unless the user sets a specific one
- **AND** this holds for a list a server defines exactly as it does for one made on the device
- **AND** list order is what picks the four, because the order is what a reading list means

#### Scenario: Artwork for an entry
- **WHEN** a reading list is displayed
- **THEN** each entry shows the publication's own cover beside its position in the list
- **AND** the position stays legible without the artwork, so an entry whose cover has not arrived or cannot be fetched keeps its place, its number and its title

#### Scenario: Entry no longer available
- **WHEN** an entry's source has removed the publication
- **THEN** the entry remains in the list, marked unavailable, and does not break the ordering or the "next" flow
