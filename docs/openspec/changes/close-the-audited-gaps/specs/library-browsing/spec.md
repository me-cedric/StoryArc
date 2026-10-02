## ADDED Requirements

### Requirement: A publication's actions wherever it is drawn

Every place that draws a publication SHALL offer the same set of actions on it, through
the platform's own gesture for secondary actions: a long press with a menu on Android,
and a context menu on iOS.

#### Scenario: The same actions in every place
- **WHEN** a reader long-presses a publication on Android, or opens its context menu on iOS, in the library grid or list, on the home surface, in search results, on a shelf, on a collection or reading-list page, or in a server's own browser
- **THEN** the same actions are offered in every one of those places: open, mark as read or mark as unread, start from the beginning, add to a shelf, download or remove the download, and show the publication's details
- **AND** on a shelf, a collection or a reading list the reader owns, the menu also offers to remove the publication from that shelf

#### Scenario: Marking a server publication
- **WHEN** a reader marks a publication from a server as read or unread from that menu
- **THEN** the local state changes at once, and the change is sent to the server, or held and sent when the server is reachable again
- **AND** a server that refuses the change states the refusal on the screen where the reader made it

#### Scenario: An action that does not apply
- **WHEN** an action cannot apply to a publication, such as removing a download that does not exist
- **THEN** the menu does not offer that action, rather than offering it disabled

### Requirement: The finished mark

A publication the reader has finished SHALL carry a mark on its cover that a reader
sees at a glance.

#### Scenario: Seeing what is finished
- **WHEN** the library, the home surface, a shelf or search draws a finished publication
- **THEN** its cover carries a finished mark that is legible on a light cover and on a dark cover, in both appearances and at the largest text size
- **AND** the mark follows each platform's own form for a status badge
- **AND** VoiceOver and TalkBack announce the publication as finished

## MODIFIED Requirements

### Requirement: Filtering

The app SHALL filter by read state, format, language, genre, tag, publisher,
publication status, year range, and by the library a publication came from —
availability being the separate primary axis described under *Unified library*.

> **This block is carried from `one-library-three-destinations`, which also holds this
> requirement, and the two closing scenarios below are merged into both, word for word.**
> A MODIFIED requirement replaces the whole block on archive, so two changes holding
> disjoint blocks on one requirement means whichever syncs second deletes the other's
> scenarios — `pnpm delta:drop` refused exactly that pair until this merge. Add decision
> D36's status-filter scenarios here and there, never into one alone.

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

#### Scenario: Filtering by a source's own publication status
- **WHEN** a source reports a publication status for a series — Kavita's `publicationStatus`, among the sources this app reads
- **THEN** the status is carried onto the row and offered as one status group in the filter menu
- **AND** the group states that it covers only the series whose source reports a status

#### Scenario: Setting a status by hand where a source reports none
- **WHEN** a series' source reports no publication status at all — a folder or a share carries no such field
- **THEN** a reader may set a status for that series by hand, and the filter narrows to it the same way it narrows to a reported one
- **AND** a status a source reports is not editable by the reader — only a series with no reported status takes one set by hand
