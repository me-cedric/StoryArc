# library-browsing Specification

## Purpose

Finding something to read. One library view over every configured source, with
search, filtering, sorting and grouping that behave the same regardless of where
a publication lives — and that respect a curated order when one exists.

## Requirements

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

### Requirement: Search

The app SHALL provide search across titles, series, authors, publishers, tags
and genres, using the server's own search where a source provides one.

Search SHALL say what it is about to search, and SHALL let a reader narrow it to
what can be read with no network.

> Where search is *reached* from, and what its screen opens onto before a query is
> typed, belong to [`navigation-shell`](../navigation-shell/spec.md). This
> requirement owns what searching *does*.

#### Scenario: The scope is stated, and can be narrowed
- **WHEN** the search screen is open
- **THEN** it states whether it is searching everything or only what is on the device
- **AND** a user can narrow it to what is on the device, and widen it again, without leaving the screen
- **AND** the choice persists until changed

#### Scenario: Searching with every source unreachable
- **WHEN** a query is typed while no configured source can be reached
- **THEN** results held on the device appear and are usable, and the screen names the sources it could not ask rather than reporting no results
- **AND** narrowing to what is on the device removes that notice, because nothing is then being waited for

#### Scenario: Typing a query
- **WHEN** a user types in the search field
- **THEN** results update as they type, debounced, without a submit action
- **AND** results are grouped by match kind — series, publication, person, tag

#### Scenario: Mixed local and server search
- **WHEN** a query spans a Kavita source and a local folder
- **THEN** server results and local results are merged into one ranked list, each labelled with its source

#### Scenario: No results
- **WHEN** a query matches nothing
- **THEN** the empty state names what was searched and offers to widen the scope to all sources if the search was scoped

#### Scenario: Recent searches
- **WHEN** a user opens search
- **THEN** recent queries are offered, and can be cleared

### Requirement: Filtering

The app SHALL filter by read state, download state, format, source, language,
genre, tag, publisher, publication status, and year range.

#### Scenario: Combining filters
- **WHEN** a user applies several filters
- **THEN** they combine with AND, the active count is visible on the filter control, and a single action clears them all

#### Scenario: Filter persistence
- **WHEN** a user leaves the library and returns
- **THEN** active filters are still applied
- **AND** the app never silently returns a filtered view that looks like an empty library — the empty state says filters are active and offers to clear them

#### Scenario: Filtering offline
- **WHEN** a user filters to "Downloaded"
- **THEN** only publications readable without a network are shown, regardless of source state

### Requirement: Sorting

The app SHALL sort by title, series, date added, date released, last read,
progress, and file size, ascending or descending — and SHALL preserve a curated
order where one exists.

#### Scenario: Default order in a reading list
- **WHEN** a user opens a reading list that carries an explicit order
- **THEN** the default sort is that curated order, labelled as such — not alphabetical

#### Scenario: Overriding a curated order
- **WHEN** a user sorts a curated list by another field
- **THEN** the app applies it for that session and offers a one-tap return to the curated order
- **AND** the curated order itself is not modified

#### Scenario: Alphabetical sorting across languages
- **WHEN** titles are sorted alphabetically
- **THEN** the comparison uses the device's locale collation, so accented and non-Latin titles sort correctly
- **AND** leading articles in the user's interface language are ignored

#### Scenario: Sorting a series
- **WHEN** a series is opened
- **THEN** its contents default to volume and chapter order, not filename order

### Requirement: What could not be opened

The library SHALL say **which** publications it could not open, not how many, and SHALL let a
reader reach the reason.

`publication-formats` words every refusal precisely — a solid RAR4 says it uses solid
compression, a CB7 names 7-Zip, a locked audiobook names its store's content protection — and
the library currently aggregates all of that into a count. The count is the one form of the
message that helps nobody.

#### Scenario: One publication could not be opened
- **WHEN** a scan finds exactly one publication it cannot open
- **THEN** the notice names that publication and states the reason in the words `publication-formats` gives for it
- **AND** the notice can be dismissed, and the list it summarises stays reachable afterwards

> **This said "a scan or an import", and the import half was never built.** On both platforms
> an import that cannot be indexed returns silently — iOS's `LibraryImports` and Android's
> `LibraryViewModel.indexImport` each drop the failure and neither touches the skipped list —
> so a reader who imports one unreadable file gets a transient alert naming the file and no
> reason, and nothing in the notice. No task in §1 ever mentioned imports. Narrowed to what was
> built rather than left promising what was not, and recorded here so the gap survives the
> archive: giving imports the same treatment belongs with whichever change owns the import
> path, and it is not free — the scan's settle **replaces** the list, which is what makes a
> fixed publication leave it, so an import adding one entry needs an operation the scan does
> not have.
>
> The second clause lost "reaching the file" for the same reason: no reveal, share or
> open-in-Files exists on either platform, and *Dismiss* acknowledges the whole notice rather
> than removing an entry — which §1.6 chose deliberately, so the clause now says what dismissal
> actually does.

#### Scenario: Several could not be opened
- **WHEN** more than one cannot be opened
- **THEN** the notice states how many and leads to a list naming each with its own reason
- **AND** the reasons are not merged: two files that failed differently say different things

#### Scenario: The notice is not on a timer
- **WHEN** the notice is shown
- **THEN** it stays until the reader dismisses it or resolves it
- **AND** it does not float over the shelf's content in a way that obscures a cover, because a message about a durable problem that removes itself is a message designed to be missed

#### Scenario: Reaching it later
- **WHEN** a reader dismisses the notice
- **THEN** the list remains reachable from the library, so a reader who dismissed it in the middle of something can come back to it
- **AND** the count is not shown again for the same publications unless the set changes

#### Scenario: A publication that later opens
- **WHEN** a publication that had failed is opened successfully — it was re-downloaded, or a share came back
- **THEN** it leaves the list without being dismissed by hand
- **AND** the notice disappears when the list empties

#### Scenario: Announced without sight
- **WHEN** a screen reader reaches the notice
- **THEN** it is announced once, naming the publication where there is one and the count where there are several, and it does not steal focus from the shelf
- **AND** the way to the list is a control with a name, not the whole notice

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

### Requirement: Continue reading

The app SHALL surface in-progress publications first.

#### Scenario: Home view
- **WHEN** a user opens the app with in-progress publications
- **THEN** a "Continue reading" row appears first, ordered by most recently read
- **AND** it is absent, rather than shown empty, when nothing is in progress

#### Scenario: Next in series
- **WHEN** a user finishes a volume that has a successor in the same series
- **THEN** the next volume is offered immediately, both at the end of the reader and in the continue row

## Open Questions

- **Publication status has no source.** Neither `ComicInfo.xml` nor an EPUB
  package document states whether a series is ongoing, on hiatus, completed or
  cancelled; a Kavita series does. The filter is therefore unbuildable over a
  local library, and would narrow to nothing for every publication a folder or a
  share supplies. To be resolved when a server's publications join the unified
  library: either the filter is scoped to the sources that report a status and
  says so, or the app records a status a reader sets by hand. It will not be
  inferred from a file that does not carry one.
- **Download state waits on the library knowing what is downloaded.** The record
  of downloaded files belongs to `offline-downloads`, and the library is
  assembled from a scan that never consults it. To be resolved with the
  "Filtering offline" scenario above, which is what it is for.
- **Source is the scope selector, not a filter group.** "Scoping to one source"
  in *Unified library* already describes it, and it behaves differently from a
  filter: it narrows search as well, and it persists on its own. Building it
  twice would give a reader two controls that disagree.
