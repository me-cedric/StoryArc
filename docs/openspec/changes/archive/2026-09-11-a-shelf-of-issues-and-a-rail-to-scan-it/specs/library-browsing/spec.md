## MODIFIED Requirements

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

> **The series-or-issues choice and the index are carried into every sibling delta that
> holds this requirement, word for word.** A MODIFIED requirement replaces the whole block,
> so `every-source-is-the-library`, `one-library-three-destinations` and
> `a-shelf-of-issues-and-a-rail-to-scan-it` all hold one identical Presentation block and the
> order they sync in cannot matter. `pnpm delta:drop` reports nothing while they agree, and
> reports the pair the moment one of them drifts. Merge into all three, never into one.

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
- **WHEN** publications in the library belong to a series, and the shelf is grouped by series
- **THEN** the library lists that series once, as a single cell carrying the series' own artwork and how many publications it holds
- **AND** the issues inside it are not listed beside it, whatever source they came from
- **AND** a publication that belongs to no series is a row of its own, as it always was
- **AND** the grid and the compact list answer this the same way, so a row that stands for a series opens the series in either layout

#### Scenario: A shelf of issues
- **WHEN** a reader asks the shelf for issues instead of series
- **THEN** every publication is one cell, the ones a series held included, and no cell stands for a group
- **AND** the sort, the filters, the availability axis and the layout are unchanged by the choice
- **AND** the sections and the index follow the cells that are drawn, because they are cut from the same list

#### Scenario: The choice between series and issues
- **WHEN** the reader looks for the control that makes that choice
- **THEN** it is a named choice inside the menu that holds the other view choices, and it states which of the two the shelf is showing
- **AND** it reads as a grouping rather than as a sort or a filter
- **AND** the choice persists across visits, so a reader who asked for issues is not given series again on the next launch
- **AND** series is the answer a reader who has never chosen gets

#### Scenario: Opening a series
- **WHEN** a reader opens a series
- **THEN** its publications are listed in their own order, each openable, each carrying the marks a cover carries in the grid
- **AND** one gesture returns to the library, at the place the reader left it

#### Scenario: Sectioning a long library
- **WHEN** the library holds more rows than a reader can scan
- **THEN** it is divided by the active sort key, with headings that stay visible while their section is on screen
- **AND** the sections follow the sort rather than replacing it
- **AND** a series is one row for this purpose, because it is one row everywhere else

#### Scenario: An index down the side of a long shelf
- **WHEN** the shelf holds more rows than a reader can scan and is sorted by title or by series
- **THEN** an index runs down its trailing edge, holding one entry for each letter the shelf actually files a row under, in the shelf's own order
- **AND** choosing an entry moves the shelf to the first row filed under that letter
- **AND** a row filed under no letter is offered as one entry reading `#`, so nothing on the shelf is unreachable from the index

#### Scenario: A sort no letter describes
- **WHEN** the shelf is sorted by last read, by progress, by year, by date added, or by size on this device
- **THEN** no index is drawn, because none of those orders files a row under a letter
- **AND** it is absent rather than drawn and inert: a control that refuses every touch still takes a strip of artwork and still has to be stepped over by a screen reader
- **AND** the index returns unchanged when the reader sorts by title or by series again

#### Scenario: The index without sight
- **WHEN** a screen reader reaches the index
- **THEN** it is announced as one named group, and each entry is announced as the letter it moves to
- **AND** every entry can be reached and operated without sight, and choosing one announces where the shelf has moved to

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

