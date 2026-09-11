# collections-and-reading-lists Specification

## Purpose

Two different ideas that most apps conflate. A **collection** is an unordered
grouping — "Image Comics", "To read with my kid". A **reading list** is an
ordered sequence where the order carries meaning — a crossover event read in
publication order, a recommended reading path. StoryArc keeps them distinct
because Kavita does, and because ordering is the entire point of one of them.

## Requirements

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

#### Scenario: Entry no longer available
- **WHEN** an entry's source has removed the publication
- **THEN** the entry remains in the list, marked unavailable, and does not break the ordering or the "next" flow

### Requirement: Server-backed and local objects

The app SHALL present server-defined and locally-defined collections and lists
in the same places, distinguished by a source label rather than segregated into
separate screens.

#### Scenario: Mixed listing
- **WHEN** a user browses collections
- **THEN** local and server collections appear in one list, each labelled with its source

#### Scenario: Editing while the server is unreachable
- **WHEN** a user edits a server-backed list while the server is unreachable
- **THEN** the edit is applied locally, marked pending, and pushed on reconnection
- **AND** the pending state is visible on the list

#### Scenario: Conflicting edit
- **WHEN** a pending local edit conflicts with a change made on the server
- **THEN** the server's version wins for membership and order, the local edit is discarded, and the user is told once what changed

#### Scenario: Converting a local list
- **WHEN** a user wants a local list on a server
- **THEN** the app offers to copy it, and states which entries cannot be included because they do not exist on that server
- **AND** only servers that are reachable and hold reading lists are offered
- **AND** the count, what the chosen server already has, and what it cannot take are all stated before anything is sent
- **AND** an entry the server does not hold is left out rather than uploaded, and the local list keeps it
- **AND** the copy is undoable for 10 seconds, which removes the list from the server again

#### Scenario: Converting a local list while every server is away
- **WHEN** no server is reachable, or none of them holds reading lists
- **THEN** the offer to copy is disabled and says why, rather than failing after the user has confirmed it

### Requirement: Bulk actions

The app SHALL support acting on a whole collection or reading list at once.

#### Scenario: Downloading a collection
- **WHEN** a user downloads an entire collection or reading list
- **THEN** the app states the item count and total size before starting, and queues them per [`offline-downloads`](../offline-downloads/spec.md)

#### Scenario: Marking a list read
- **WHEN** a user marks a collection or list as read
- **THEN** every member's read state is updated, synchronised where the source supports it, and the action is undoable for 10 seconds

### Requirement: Shelves on the home surface

The home surface SHALL list the reader's collections and their reading lists as
two shelves of their own, assembled from locally held curation alone, and each
shelf SHALL lead to the exhaustive list of its kind.

#### Scenario: Collections are listed
- **WHEN** the reader has at least one collection
- **THEN** the home surface offers a Collections shelf naming each of them
- **AND** each is drawn as its own artwork with its name and how much is in it beneath

#### Scenario: Reading lists are a shelf of their own
- **WHEN** the reader has at least one reading list
- **THEN** the home surface offers a Reading lists shelf, separate from Collections
- **AND** the two are never merged into one shelf, because a reading list is ordered and a collection is not
- **AND** a reading list states how far through it the reader is, which a collection has no position in and therefore never states

#### Scenario: One kind with nothing in it
- **WHEN** the reader has collections and no reading lists, or the reverse
- **THEN** only the shelf that holds something is drawn
- **AND** the other is absent rather than drawn empty

#### Scenario: No shelves at all
- **WHEN** the reader has neither a collection nor a reading list
- **THEN** neither shelf is drawn, and the home surface carries no heading for them

#### Scenario: A shelf with no cover of its own
- **WHEN** a collection or a reading list is listed on the home surface
- **THEN** its card is the composite of its first four member covers, or one cover across the card below four, by the same rule the shelves screen follows
- **AND** a shelf whose artwork the device does not hold is drawn as a blank in the shape of a cover, so it still lines up with the shelves beside it
- **AND** it is never drawn as a name with a folder glyph, because a shelf with no artwork is a folder listing

#### Scenario: A shelf that a server defines
- **WHEN** a server has told the app about a collection or a reading list
- **THEN** that shelf is listed on the home surface beside the reader's own, labelled with the name of the source it came from
- **AND** choosing it opens that shelf on its server

#### Scenario: The home surface never asks a server for a shelf
- **WHEN** the home surface is drawn with every source unreachable
- **THEN** it lists exactly the same shelves, in the same order, as when every source is up
- **AND** it asks no source for them, because the list is read from what was written down when a source last answered

#### Scenario: A source is removed
- **WHEN** a source is removed from the app
- **THEN** the shelves it defined stop being listed on the home surface
- **AND** the reader's own collections and reading lists are untouched

#### Scenario: Each shelf leads to the whole of its kind
- **WHEN** the reader chooses a shelf's heading on the home surface
- **THEN** the app opens the screen that lists every collection and every reading list
- **AND** no shelf truncates without offering the rest
