## MODIFIED Requirements

### Requirement: Reaching search

Search SHALL be one action away from the home surface and from the library, and
SHALL take over the screen while it is active. It SHALL be a place a reader arrives
at, and no control SHALL change shape or position to become it.

Its entry point is platform-specific, and each platform SHALL use its own system
convention rather than a translation of the other's — but on both, the control that
offers search SHALL still be there after search opens, so a reader can see where they
came from.

> **This requirement is rewritten, and the previous text is the reason.** It said iOS
> should offer search "set apart from" the destinations rather than listed among them,
> and that Android's should be "a field at the top … not a destination in the
> navigation control". The iOS half was built as `Tab(role: .search)`, which morphs the
> tab into a field in place — confirmed on a device on 2026-08-31 — and that is the
> shape-changing this now forbids: the bar moves under the reader's thumb and there is
> nowhere to land. Both halves are replaced by an outcome rather than a control, and
> design.md carries each platform's answer with the guidance behind it.

#### Scenario: Search is a destination, not a shape
- **WHEN** a reader looks for search on either platform
- **THEN** it is reachable in one action from the home surface and from the library
- **AND** choosing it opens a screen of its own that takes over the browse surface
- **AND** no existing control becomes the search field in place

#### Scenario: What search opens onto
- **WHEN** search is activated and nothing has been typed
- **THEN** it presents recent searches, and publications the reader already has — at least one in progress, one never opened, and one that is next in a series they have read
- **AND** every suggestion comes from the device or from a source the reader configured, and none is fetched in order to be suggested
- **AND** recent searches can be cleared

#### Scenario: Nothing to suggest
- **WHEN** search opens and the library holds nothing to suggest from
- **THEN** the screen says so in one sentence rather than drawing empty headings
- **AND** it offers the same way of adding a source that the library's own empty state offers

#### Scenario: Leaving search
- **WHEN** a reader dismisses search
- **THEN** they return to the destination they were on, with its scroll position and filters intact
- **AND** the query is offered again as a recent search rather than being lost

#### Scenario: Searching with a source unreachable
- **WHEN** search runs while a configured source cannot be reached
- **THEN** local results appear immediately and are usable
- **AND** the unreachable source is named once, in the results, as something that could not answer — not as an error that replaces the results
- **AND** no result and no empty state waits on it
