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

### Requirement: Search

The app SHALL provide search across titles, series, authors, publishers, tags
and genres, using the server's own search where a source provides one, and SHALL
group results by what the match is rather than by which source answered.

Search SHALL say what it is about to search, and SHALL let a reader narrow it to
what can be read with no network.

> Where search is *reached* from, and what its screen opens onto before a query is
> typed, belong to [`navigation-shell`](../navigation-shell/spec.md). This
> requirement owns what searching *does*.
>
> **The sentence and this note are carried from `quiet-shell-and-search`, not written
> here**, along with the two scenarios below — same reason, same mechanism. A MODIFIED
> requirement replaces the whole block, so a delta that omits them drops them on archive.
> Added 2026-09-01, after the same class of omission was found and fixed in this change's
> `navigation-shell` delta and a re-verification asked whether the sibling capability had
> been checked too. It had not.

#### Scenario: Typing a query
- **WHEN** a reader types in the search field
- **THEN** results update as they type, debounced, without a submit action
- **AND** results are grouped by match kind — series, publication, person, tag

#### Scenario: Mixed local and server search
- **WHEN** a query spans a server source and a local folder
- **THEN** locally held results render immediately and remote results fill in as they arrive, merged into the same ranked groups
- **AND** each result names the library that supplied it, but only where more than one place could have answered — what the device itself matched counting as one place, and each library asked as another — because where only one place could answer, every row would carry the same words
- **AND** two libraries that both hold the same publication produce two results and never one: a duplicate is folded only where the same library answered twice
- **AND** a late answer only ever adds, so no result is removed, replaced or reordered against another: a result can be pushed down by rows arriving above it, and never moves up, never past another result, and never under a different heading

#### Scenario: A source is slow or cannot answer
- **WHEN** a source is slow, or fails to answer a query
- **THEN** the results already shown stay usable and are never replaced by an error
- **AND** the source that could not answer is named once, quietly, with a way to try it again

#### Scenario: No results
- **WHEN** a query matches nothing
- **THEN** the empty state names what was searched and offers to widen the scope to all sources if the search was scoped

> **This scenario's wording is `quiet-shell-and-search`'s, carried here on 2026-09-01.** It
> used to offer "to clear any active filters that could be hiding a match", which was written
> before search had a scope a reader could set — so the clause had nothing to act on. Now that
> narrowing to what is on the device is a state, widening out of it is the useful offer, and
> clearing filters is `Filtering`'s own business. The old wording is recorded rather than
> replaced silently, because the two are easy to mistake for each other.

#### Scenario: Recent searches
- **WHEN** a reader opens search
- **THEN** recent queries are offered, and can be cleared

> **The scenarios below arrived from a sibling change and are carried, not written
> here.** A MODIFIED requirement replaces the whole block, so a delta written before
> that change synced would drop them on archive. `openspec validate` caught it.

#### Scenario: The scope is stated, and can be narrowed
- **WHEN** the search screen is open
- **THEN** it states whether it is searching everything or only what is on the device
- **AND** a user can narrow it to what is on the device, and widen it again, without leaving the screen
- **AND** the choice persists until changed


#### Scenario: Searching with every source unreachable
- **WHEN** a query is typed while no configured source can be reached
- **THEN** results held on the device appear and are usable, and the screen names the sources it could not ask rather than reporting no results
- **AND** narrowing to what is on the device removes that notice, because nothing is then being waited for

### Requirement: Filtering

The app SHALL filter by read state, format, language, genre, tag, publisher,
publication status, year range, and by the library a publication came from —
availability being the separate primary axis described under *Unified library*.

#### Scenario: Combining filters
- **WHEN** a reader applies several filters
- **THEN** they combine with AND, the active count is visible on the filter control, and a single action clears them all

#### Scenario: Filtering to one library
- **WHEN** a reader filters to a single configured library by name
- **THEN** only its publications are shown, and the filter is cleared like any other
- **AND** it does not change what search covers
- **AND** it does not survive as a mode: clearing all filters restores the whole library

#### Scenario: Filter persistence
- **WHEN** a reader leaves the library and returns
- **THEN** active filters are still applied
- **AND** the app never silently returns a filtered view that looks like an empty library — the empty state says filters are active and offers to clear them

#### Scenario: Filtering offline
- **WHEN** a reader wants only what can be read with no network
- **THEN** it is the library's primary axis rather than one filter among the others, as *Unified library* describes, and it is reachable without opening the filter sheet
- **AND** applying it shows only publications readable with no network, regardless of source state
- **AND** it combines with the other filters rather than replacing them

#### Scenario: Filtering while a source is unreachable
- **WHEN** filters are applied while a source cannot be reached
- **THEN** its publications are still filtered and still listed, dimmed
- **AND** no filter result changes because a source went down

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
- **AND** the division is drawn in whichever layout the reader chose, because this describes the library and not the grid
- **AND** a division that would average fewer than one row per column is not drawn, because its headings then cost more space than the rows they introduce

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

## REMOVED Requirements

### Requirement: Continue reading

Moved whole to [`home-screen`](../home-screen/spec.md), and split in two on the
way.

It was specified as a row *inside the library view*, which is why both apps hide
it the moment a search or a selection is active — the app withdraws its only
editorial surface exactly when the reader is looking hardest. It becomes the lead
of a destination of its own instead.

The split is the substantive part: *Keep reading* answers "where did I stop", and
*Up next* answers "what is the next unread issue of a series I started". The
"Next in series" scenario that used to live here becomes the *Up next*
requirement; the end-of-reader offer it also described stays a reader behaviour
and is unaffected.
