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

### Requirement: Presentation

The app SHALL offer a cover grid and a compact list, SHALL adapt density to the
display, and SHALL let a cover carry at most two marks: how far the reader has
got, and whether it can be read with no network.

The controls that change what the shelf shows SHALL be grouped rather than laid out as a row
of similar icons. A reader who cannot tell two adjacent controls apart has as many controls as
they can name.

> **The grouping rule and the last three scenarios are carried from
> `named-failures-and-quieter-chrome`, which syncs first.** A MODIFIED requirement replaces
> the whole block, so two changes holding disjoint blocks on one requirement means whichever
> syncs second deletes the other's scenarios. `pnpm delta:drop` now refuses that pair unless
> the earlier block is a subset of this one, which is what these additions make true. Do not
> remove them to "keep this delta about the destinations" — that reopens the drop.

> **The two scenarios below keep every clause the main spec already holds.** An earlier
> draft of this delta reworded them and lost two: *Switching layout* dropped "per scope …
> does not force it everywhere", and *Adaptive columns* dropped "an iPad in Split View".
> `pnpm delta:drop` did not see either, because it compares scenarios by **name** — a
> scenario that keeps its name and loses a clause passes the check. Restored 2026-09-05 by
> reading the two blocks against `specs/library-browsing/spec.md` by hand.

#### Scenario: Switching layout
- **WHEN** a reader switches between grid and list
- **THEN** the choice persists per scope, so a dense list for one library does not force it everywhere
- **AND** it persists across visits, so a dense list does not have to be chosen again every time the shelf is opened

#### Scenario: Adaptive columns
- **WHEN** the app is shown on a phone, a tablet, a foldable in either posture, an iPad in Split View, or any other resized window
- **THEN** the number of grid columns follows the available width, and cover size stays within the readable range defined in the design tokens
- **AND** a wide window shows fewer, larger covers rather than the phone's lattice widened

#### Scenario: Cover art is shown whole
- **WHEN** a cover's proportions differ from the cell's
- **THEN** the whole cover is shown, letterboxed onto the recessed surface colour, rather than cropped

#### Scenario: Progress on covers
- **WHEN** a publication is partially read
- **THEN** its cover carries an unobtrusive progress indicator
- **AND** a fully read publication is distinguishable at a glance without a label covering the artwork

#### Scenario: What is on the device
- **WHEN** a publication can be read with no network
- **THEN** its cover carries one small mark saying so, in the colour the design tokens reserve for it
- **AND** no third mark is added to a cover for any reason, and origin is never one of them

#### Scenario: A series is one row
- **WHEN** publications in the library belong to a series
- **THEN** the library lists that series once, as a single cell carrying the series' own artwork and how many publications it holds
- **AND** the issues inside it are not listed beside it, whatever source they came from
- **AND** a publication that belongs to no series is a row of its own, as it always was

#### Scenario: Opening a series
- **WHEN** a reader opens a series
- **THEN** its publications are listed in their own order, each openable, each carrying the marks a cover carries in the grid
- **AND** one gesture returns to the library, at the place the reader left it

#### Scenario: Sectioning a long library
- **WHEN** the library holds more rows than a reader can scan
- **THEN** it is divided by the active sort key, with headings that stay visible while their section is on screen
- **AND** the sections follow the sort rather than replacing it
- **AND** a series is one row for this purpose, because it is one row everywhere else

#### Scenario: A publication that cannot be read now
- **WHEN** a publication is neither on the device nor currently reachable
- **THEN** its cell is dimmed and still selectable, so it can be inspected, downloaded later, or added to a shelf
- **AND** dimming is the only difference — it is not moved, grouped apart, or badged as an error

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

## REMOVED Requirements

