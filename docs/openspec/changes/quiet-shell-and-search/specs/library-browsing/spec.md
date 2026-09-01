## MODIFIED Requirements

### Requirement: Search

The app SHALL provide search across titles, series, authors, publishers, tags
and genres, using the server's own search where a source provides one.

Search SHALL say what it is about to search, and SHALL let a reader narrow it to
what can be read with no network.

> Where search is *reached* from, and what its screen opens onto before a query is
> typed, belong to `navigation-shell`. This requirement owns what searching *does*.
>
> That requirement is carried by
> [`one-library-three-destinations`](../../../one-library-three-destinations/specs/navigation-shell/spec.md),
> which is the change that creates the capability — see §4b of this change's tasks for why
> it moved there rather than staying beside this delta.

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
