## Purpose

The frame every browse surface draws inside. What the destinations are, how a
reader moves between them, what survives that move, and how search is reached.

This capability exists separately from [`native-experience`](../native-experience/spec.md)
because the two answer different questions. `native-experience` owns *how a
platform's navigation looks and adapts* — system controls, system materials,
system gestures. This owns *what the destinations are and what may become one*,
which is a product decision that must hold identically on both platforms even
where the controls do not resemble each other.

It exists at all because the answer today is "whatever the plumbing produced":
one destination per configured source, so the reader's own navigation names the
transport their books arrived over.

## ADDED Requirements

### Requirement: The destination set

The app SHALL offer exactly three destinations — a home surface, the whole
library, and everything readable on this device — reachable at any time from one
persistent control, and SHALL NOT add, remove or reorder a destination in
response to anything the reader configures.

#### Scenario: Moving between destinations
- **WHEN** a reader chooses a different destination
- **THEN** it appears immediately, and the destination they left keeps its scroll position, its active filters and its selection
- **AND** returning to it is a return rather than a reset

#### Scenario: Each destination remembers where the reader had got to
- **WHEN** a reader descends inside a destination, moves to another destination, and comes back
- **THEN** they arrive where they were, not at that destination's root
- **AND** the platform's own back affordance retraces that destination's own path rather than a single path shared by all three

#### Scenario: Configuring sources never changes the destinations
- **WHEN** a reader adds, renames, reorders or removes a place to read from — however many they have
- **THEN** the three destinations are unchanged
- **AND** no source becomes a destination, and no destination is added to hold them

#### Scenario: Where the app opens
- **WHEN** a reader launches the app normally
- **THEN** it opens on the home surface
- **AND** when the launch names a publication or a destination — a home-screen quick action, a handover, a shortcut — it opens there instead, as [`native-experience`](../native-experience/spec.md) already requires

#### Scenario: Every source is unreachable
- **WHEN** no configured source can be reached
- **THEN** all three destinations remain present and selectable, none is hidden, disabled or marked as failed
- **AND** each shows what it holds locally rather than an error, because an unreachable source is a normal state

### Requirement: Reaching search

Search SHALL be one action away from the home surface and from the library, and
SHALL take over the screen while it is active. Its entry point is
platform-specific, and each platform SHALL use its own system convention rather
than a translation of the other's.

#### Scenario: Reaching search on iOS
- **WHEN** a reader looks for search on iOS
- **THEN** it is offered by the same persistent navigation control as the three destinations, set apart from them rather than listed among them
- **AND** activating it replaces the browse surface with search until the reader dismisses it

#### Scenario: Reaching search on Android
- **WHEN** a reader looks for search on Android
- **THEN** it is a field at the top of the home surface and of the library, not a destination in the navigation control
- **AND** activating it expands over the screen

#### Scenario: What search opens onto
- **WHEN** search is activated and nothing has been typed
- **THEN** it presents recent searches, pinned shelves and what the reader is in the middle of — a page worth being on, not a blank field
- **AND** recent searches can be cleared

#### Scenario: Leaving search
- **WHEN** a reader dismisses search
- **THEN** they return to the destination they were on, with its scroll position and filters intact
- **AND** the query is offered again as a recent search rather than being lost

#### Scenario: Searching with a source unreachable
- **WHEN** search runs while a configured source cannot be reached
- **THEN** local results appear immediately and are usable
- **AND** the unreachable source is named once, in the results, as something that could not answer — not as an error that replaces the results
- **AND** no result and no empty state waits on it

### Requirement: Where a source can be reached

No configured source SHALL be a destination in primary navigation, and origin
SHALL NOT appear anywhere on the browse path except on a publication's own page
and in settings.

#### Scenario: Narrowing to one source
- **WHEN** a reader wants only one source's publications
- **THEN** it is offered by name as one filter among the others, applied and cleared the way every other filter is
- **AND** it does not change what search covers, and it does not persist as a mode the reader can be stuck in

#### Scenario: Adding a source
- **WHEN** a reader adds a second, a fifth or a ninth place to read from
- **THEN** primary navigation is unchanged, and that source's publications join the one library
- **AND** nothing above the library's contents lists the configured sources

#### Scenario: Reaching a source's configuration
- **WHEN** a reader wants a source's connection, credentials, certificate, scan state or cached contents
- **THEN** it is in settings, on the screen that owns connected libraries
- **AND** none of it — including connection state indicators — appears on the home surface, the library or the on-device destination

#### Scenario: A source stops being reachable
- **WHEN** a source becomes unreachable while the reader is browsing
- **THEN** navigation does not change, and its publications stay listed and dimmed rather than disappearing
- **AND** one recovery affordance is offered where the affected publications are, with the diagnostics in settings

### Requirement: The destination set on a large screen

On a large screen the three destinations SHALL become the platform's own
wide-window navigation without becoming a different set, and any secondary
entries it reveals SHALL be library sections and shelves.

#### Scenario: A wide window
- **WHEN** the app is shown in a wide window on either platform
- **THEN** the same three destinations are present, in the same order, in whatever wide-window navigation the platform provides
- **AND** any secondary entries are sections of the library and the reader's shelves, with pinned shelves first
- **AND** no entry, primary or secondary, is a configured source

#### Scenario: Resizing back down
- **WHEN** the window narrows again, or the device is rotated
- **THEN** the navigation returns to its compact form without losing the current destination, its scroll position or its filters

#### Scenario: More shelves than the navigation can show
- **WHEN** a reader has more shelves than the secondary entries can list
- **THEN** the overflow is reachable within the navigation itself
- **AND** the three destinations are never displaced or pushed out of reach by them

### Requirement: Chrome that gets out of the way

The persistent navigation control SHALL recede as content scrolls and return
without being summoned, and SHALL never leave the reader unable to reach it.

#### Scenario: Scrolling through covers
- **WHEN** a reader scrolls down through a long grid or shelf
- **THEN** the navigation control recedes so the artwork has the screen
- **AND** scrolling back up returns it immediately

#### Scenario: The control can always be recovered
- **WHEN** the navigation control has receded
- **THEN** a single gesture the platform already teaches brings it back
- **AND** there is no state in which the reader can reach neither the navigation control nor the destination they came from

#### Scenario: Reduced motion
- **WHEN** the system asks for reduced motion
- **THEN** the control still recedes and returns, without the animation
- **AND** nothing becomes unreachable as a result
