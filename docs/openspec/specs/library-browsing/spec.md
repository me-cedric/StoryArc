# library-browsing Specification

## Purpose

Finding something to read. One library view over every configured source, with
search, filtering, sorting and grouping that behave the same regardless of where
a publication lives — and that respect a curated order when one exists.

## Requirements

### Requirement: Unified library

The app SHALL present a single library spanning every source, and SHALL let the
user narrow it to one source.

#### Scenario: Default view
- **WHEN** a user opens the library
- **THEN** publications from every connected source are shown together
- **AND** each shows its source only when more than one source is configured

#### Scenario: Scoping to one source
- **WHEN** a user selects a single source
- **THEN** the view, its search, and its filters apply to that source alone
- **AND** the scope persists until changed

### Requirement: Search

The app SHALL provide search across titles, series, authors, publishers, tags
and genres, using the server's own search where a source provides one.

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

### Requirement: Presentation

The app SHALL offer a cover grid and a compact list, and SHALL adapt density to
the display.

#### Scenario: Switching layout
- **WHEN** a user switches between grid and list
- **THEN** the choice persists per scope, so a dense list for one library does not force it everywhere

#### Scenario: Adaptive columns
- **WHEN** the app is shown on a phone, a tablet, a foldable in either posture, or an iPad in Split View
- **THEN** the number of grid columns follows the available width, and cover size stays within the readable range defined in the design tokens

#### Scenario: Progress on covers
- **WHEN** a publication is partially read
- **THEN** its cover carries an unobtrusive progress indicator
- **AND** a fully read publication is distinguishable at a glance without a label covering the artwork

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
