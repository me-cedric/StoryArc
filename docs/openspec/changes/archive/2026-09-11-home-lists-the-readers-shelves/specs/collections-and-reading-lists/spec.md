## ADDED Requirements

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
