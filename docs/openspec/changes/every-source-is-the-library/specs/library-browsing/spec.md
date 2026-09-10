## MODIFIED Requirements

### Requirement: Unified library

The app SHALL present a single library spanning every source, and SHALL let the
user narrow it to one source. Every configured source SHALL contribute its
publications to that library, whatever kind of source it is, and a publication
SHALL be treated the same in the grid whether it is a file on the device or a
title on a server.

#### Scenario: Default view
- **WHEN** a user opens the library
- **THEN** publications from every connected source are shown together
- **AND** each shows its source only when more than one source is configured

#### Scenario: Every kind of source contributes
- **WHEN** a source is configured, of any kind the app supports
- **THEN** its publications appear in the library and are ranked, sorted and filtered with every other source's
- **AND** a publication that is not on the device is a row like any other, distinguished by what it can do rather than by where it sits

#### Scenario: Browsing a source is a second way in
- **WHEN** a source has a structure of its own — libraries, series, catalogue feeds, folders
- **THEN** walking that structure stays available
- **AND** it is never the only way to reach that source's publications

#### Scenario: A source that has never been reached
- **WHEN** a source has been configured and never answered
- **THEN** the library says that source has not been read yet, names it, and offers to try again
- **AND** the rest of the library is complete and usable while it says so

#### Scenario: Scoping to one source
- **WHEN** a user selects a single source
- **THEN** the view, its search, and its filters apply to that source alone
- **AND** the scope persists until changed

#### Scenario: More from a source than the library holds
- **WHEN** a source holds more publications than the app has read
- **THEN** what has been read is in the grid, and the rest is reachable from search and from an explicit way in to that source
- **AND** the reader is told the count is partial rather than being shown a number that looks complete
- **AND** what is reachable that way is rendered by the same cells and opens the same publication page

#### Scenario: A publication that is also downloaded
- **WHEN** a publication a source offers has been downloaded to the device
- **THEN** it is one row, not two, and that row is readable with no network

#### Scenario: A source that cannot be reached now
- **WHEN** a source is unreachable and its publications are not on the device
- **THEN** they stay in the library, dimmed, and say plainly that they need their source to be reachable
- **AND** they are never removed from the shelf, because a library that shrinks when the Wi-Fi drops reads as data loss
