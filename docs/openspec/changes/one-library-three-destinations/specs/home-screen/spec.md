## Purpose

The reading room. The surface a reader lands on, built from what they are in the
middle of rather than from everything they own.

A comics library has no editors, so the app generates its own editorial: a small
number of shelves assembled from reading history and curation the reader already
made. It is deliberately never exhaustive — that is what the library destination
is for — and it is deliberately assembled from local data alone, so it is the one
surface that is identical whether every server is up or every server is down.

This capability takes over the "Continue reading" requirement that
[`library-browsing`](../library-browsing/spec.md) used to carry, and splits it in
two, because *where you stopped* and *what to start next* are two questions and
answering them with one row answers neither.

## ADDED Requirements

### Requirement: Keep reading

The home surface SHALL lead with the publications the reader is part-way
through, most recently read first, and SHALL make resuming one a single action.

#### Scenario: Resuming
- **WHEN** a reader chooses a publication from Keep reading
- **THEN** it opens at the position [`reading-progress`](../reading-progress/spec.md) recorded, without an intermediate screen
- **AND** how much is left is stated in the reader's own terms — pages or time remaining — rather than as a percentage alone

#### Scenario: Order
- **WHEN** Keep reading is shown
- **THEN** publications are ordered by when they were last read, most recent first
- **AND** finishing one removes it from Keep reading without removing it from the library

#### Scenario: Nothing in progress
- **WHEN** the reader has nothing part-way through
- **THEN** Keep reading is absent rather than shown empty

#### Scenario: A publication in progress is not currently readable
- **WHEN** a publication in Keep reading is not downloaded and its source cannot be reached
- **THEN** it stays in Keep reading, dimmed, saying plainly that it cannot be opened right now
- **AND** it is never dropped from the row, because a row that shrinks with the Wi-Fi reads as lost reading

### Requirement: Up next

The home surface SHALL offer the next unread issue of each series the reader has
started, as a shelf separate from Keep reading.

#### Scenario: The next issue of a started series
- **WHEN** a reader has finished an issue of a series and the library holds a later one they have not read
- **THEN** that issue appears in Up next
- **AND** it does not appear in Keep reading, because nothing in it has been read

#### Scenario: Not the same thing as resuming
- **WHEN** a reader has both a part-read issue and an unread later issue of the same series
- **THEN** the part-read one is in Keep reading and the later one is not in Up next until the part-read one is finished
- **AND** the two shelves never offer the same publication at the same time

#### Scenario: Finishing an issue in the reader
- **WHEN** a reader finishes an issue that has a successor in the same series
- **THEN** the successor is offered at the end of the reader as well as in Up next, so the reader does not have to leave the book to carry on with the series
- **AND** the two offers name the same issue

#### Scenario: A series with nothing after it
- **WHEN** every issue of a started series has been read
- **THEN** that series contributes nothing to Up next, silently
- **AND** Up next is absent rather than empty when no started series has a next issue

#### Scenario: The next issue lives on a source that is down
- **WHEN** the next unread issue belongs to a source that cannot be reached
- **THEN** it is still offered, dimmed, with what it needs stated plainly
- **AND** choosing it offers to download it when the source returns rather than failing silently

### Requirement: The rest of the home surface

Below the two lead shelves, the home surface SHALL offer recently added
publications, the reader's pinned shelves, and what they have finished — and
nothing that requires a server to assemble.

#### Scenario: Recently added
- **WHEN** publications have been added since the reader last looked
- **THEN** they appear as a shelf, newest first, leading to the library filtered the same way

#### Scenario: Pinned shelves
- **WHEN** a reader has pinned a collection or a reading list
- **THEN** it appears on the home surface as a shelf of its own, ahead of the unpinned ones
- **AND** unpinning it removes the shelf without altering the collection or the list

#### Scenario: Finished
- **WHEN** a reader has finished publications
- **THEN** they are offered last on the surface, grouped by when they were finished
- **AND** the section is absent when nothing has been finished

#### Scenario: Every shelf leads somewhere exhaustive
- **WHEN** a shelf holds more than it can show
- **THEN** its heading leads to the full list in the library, filtered to match the shelf
- **AND** no shelf silently truncates without offering the rest

#### Scenario: A shelf that would be empty
- **WHEN** a section has nothing to show
- **THEN** it is absent, not rendered empty with a placeholder

### Requirement: The home surface never waits on a source

The home surface SHALL be assembled from locally held reading history, local
metadata and local curation alone, and SHALL NOT block on any source.

#### Scenario: Opening the app with every source down
- **WHEN** a reader opens the app in airplane mode, or with every configured source unreachable
- **THEN** the home surface renders complete and immediately, with the same shelves in the same order as when the sources are up
- **AND** what is not readable right now is dimmed rather than removed

#### Scenario: A slow source
- **WHEN** a source is reachable but slow to answer
- **THEN** nothing on the home surface waits for it, and no shelf appears, reorders or grows once it does answer
- **AND** the reader is never shown a fragment of their reading history that later changes under them

#### Scenario: Progress recorded on another device
- **WHEN** a source holds reading positions from another device
- **THEN** the home surface still renders from local history first, and adopts the merged position under the rules in [`reading-progress`](../reading-progress/spec.md) when the merge completes
- **AND** the merge never empties a shelf that was populated a moment earlier

### Requirement: The home surface when there is little to show

The home surface SHALL degrade by changing shape rather than by showing empty
containers, and SHALL be the app's first-run surface.

#### Scenario: A few things in progress
- **WHEN** the reader has fewer in-progress publications than a carousel needs to make sense
- **THEN** Keep reading presents as a single large card rather than as a carousel of one

#### Scenario: A library with nothing in it
- **WHEN** the reader has no publications at all
- **THEN** the home surface is itself the empty state defined in [`sources`](../sources/spec.md) — one sentence, one action that opens a comic, one plain secondary that leads to connecting a library
- **AND** the library destination is not offered as a wall of nothing

#### Scenario: A library with publications but no history
- **WHEN** the reader owns publications but has read none of them
- **THEN** Keep reading and Up next are absent, and recently added leads the surface
- **AND** the surface is never a stack of empty headings
