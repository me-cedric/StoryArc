## MODIFIED Requirements

### Requirement: Unified library

The app SHALL present a single library spanning every source, in which origin is
invisible, and SHALL narrow it by **availability** — everything, or only what can
be read with no network — as its primary axis. Every configured source SHALL
contribute its publications to that library, whatever kind of source it is, and a
publication SHALL be treated the same in the grid whether it is a file on the
device or a title on a server.

Narrowing to one source survives as a filter, described under *Filtering*. It is
no longer a scope, because a scope is a mode a reader can be stuck in and it
silently narrowed search as well.

#### Scenario: Default view
- **WHEN** a reader opens the library
- **THEN** publications from every configured source are shown together, ranked, sorted and filtered as one library
- **AND** nothing on the shelf states which source a publication came from

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

#### Scenario: Narrowing to what can be read now
- **WHEN** a reader narrows the library to what is on this device
- **THEN** only publications readable with no network are shown, whatever source they came from
- **AND** the choice persists until changed, and is visible while it is active
- **AND** widening it again restores the full library without re-scanning anything

#### Scenario: Scoping to one source
- **WHEN** a reader wants one source's publications alone
- **THEN** it is offered by name as a filter, described under *Filtering*, and not as a scope the view is in
- **AND** it narrows what the shelf lists and nothing else — search still covers the whole library
- **AND** clearing filters restores the whole library, so there is no state a reader can be left in without noticing

#### Scenario: A publication that is also downloaded
- **WHEN** a publication a source offers has been downloaded to the device
- **THEN** it is one row, not two, and that row is readable with no network

#### Scenario: A publication that cannot be opened right now
- **WHEN** a publication's source is unreachable and it is not on the device
- **THEN** it stays in the library, dimmed, and says plainly that it needs its library to be reachable
- **AND** it is never removed from the shelf, because a library that shrinks when the Wi-Fi drops reads as data loss

#### Scenario: More from a source than the library holds
- **WHEN** a source holds publications the app has no metadata for
- **THEN** they are reachable from search and from an explicit "more from this library" affordance at the foot of the shelf
- **AND** the reader is told the count is partial rather than being shown a number that looks complete
- **AND** they are rendered by the same grid, the same cells and the same publication page as everything else
- **AND** they are never a destination in navigation, per [`navigation-shell`](../navigation-shell/spec.md)
