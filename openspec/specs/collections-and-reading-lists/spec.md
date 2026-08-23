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

### Requirement: Bulk actions

The app SHALL support acting on a whole collection or reading list at once.

#### Scenario: Downloading a collection
- **WHEN** a user downloads an entire collection or reading list
- **THEN** the app states the item count and total size before starting, and queues them per [`offline-downloads`](../offline-downloads/spec.md)

#### Scenario: Marking a list read
- **WHEN** a user marks a collection or list as read
- **THEN** every member's read state is updated, synchronised where the source supports it, and the action is undoable for 10 seconds
