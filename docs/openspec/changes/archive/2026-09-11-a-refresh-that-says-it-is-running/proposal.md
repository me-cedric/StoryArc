# A refresh that says it is running

**Platforms: both.** The two implementations are already mirrored. iOS keeps the
notice strip in `LibraryView.swift`'s `safeAreaBar`; Android keeps it in
`LibraryNotices` (`StillBeingRead.kt:84`). Both gain the same line, the same
decision type and the same test.

## Why

The owner reported this: a remote server is added, the data loads in the
background, and pull-to-refresh reloads the remote sources — and nothing on
screen says a refresh is running, or that it finished.

### What is already specified, quoted

`sources` covers part of this already, and the part it covers is built.

**Requirement: Metadata cache** holds two of the four bullets this change needs.

> #### Scenario: Opening the library offline
> - **WHEN** a user opens the library with every source unreachable
> - **THEN** the full cached catalogue is displayed within 500 ms of the library view appearing
> - **AND** a single unobtrusive indicator states that content is cached and when it was last refreshed
>
> #### Scenario: Refreshing a source
> - **WHEN** a user pulls to refresh, or a source's cache exceeds its staleness window
> - **THEN** the app re-fetches the catalogue in the background
> - **AND** updates the view incrementally rather than clearing it and re-populating

**Requirement: Source health visibility** holds the rest.

> The app SHALL provide one screen listing every source with its state, last sync
> time, cached item count, and downloaded size.
>
> #### Scenario: Diagnosing a source
> - **WHEN** a user opens a source's detail screen
> - **THEN** the screen shows the state, the last successful sync, the last error in plain language, the item count, and the bytes downloaded
> - **AND** offers actions to test the connection, refresh, clear the cache, remove downloads, and remove the source

**Requirement: Connection state** adds the fourth occasion.

> #### Scenario: Retry policy
> - **WHEN** a source is `unreachable`
> - **THEN** the app retries with exponential backoff starting at 5 seconds and capping at 5 minutes
> - **AND** retries immediately, once, when the device regains network connectivity or the app returns to the foreground

Three things follow from those quotes, and each of them is already built:

1. **The cached indicator exists.** `CachedNotice.swift` and `CachedNotice.kt`
   draw `library.cached %@` — *"Showing what was here %@. Checking for changes."*
   It appears while the shelf is last session's and leaves when a walk finishes.
2. **A source that has put nothing on the shelf yet is named.**
   `StillBeingReadNotice` states how many libraries are still being read. It was
   written for the silence after a server is added.
3. **A source's detail screen states its state and offers a refresh**, and both
   platforms mark the source `connecting` while that refresh runs, so the
   *Status* row says so.

### The gap, in three parts

**1. A refresh nobody pulled is silent.** The probe that asks every network
source runs on five occasions — the library appearing, a source being added, the
backoff schedule, connectivity regained, and the app returning to the foreground
— and on four of them nothing is drawn. `StillBeingReadNotice` cannot cover them:
it counts a source that is `connecting` **and has put nothing on the shelf**, so a
source that already holds titles refreshes invisibly. The cached line cannot cover
them either: it is `nil` for any shelf that is current.

**2. Completion is never stated, because the timestamp never moves.**
`Source.lastSuccessfulSync` is written in exactly two places on iOS —
`CatalogueConnection.swift:223` and `KavitaConnection.swift:182`, both at the
moment a source is *added* — and in **no place at all** on Android.
`SourceRegistry.marking(_:as:)` carries the old value forward on every probe. So
the source detail screen's *Last sync* row shows the add moment for ever on iOS
and *Never* for ever on Android. A refresh that succeeded is indistinguishable
from one that never ran, on the one screen the requirement points a reader at.

**3. Android's pull indicator follows the folder walk alone.**
`LibraryScreen.kt:495` reads `isRefreshing = scanState is LibraryScanState.Scanning`.
A pull on a shelf narrowed to a server asks no folder, so the spinner retracts as
the finger lifts and the probes run unseen. `ShelfRefresh.kt:34` records this as a
known cost and names the fix: *"What it needs is a signal that tells a pull from
the backoff loop."* iOS does not have this cost, because SwiftUI awaits the
`refreshable` closure.

## What Changes

- **A refresh nobody asked for says so, in the one place the shelf already
  speaks.** One line in the notice strip that already holds the cached line and
  the still-being-read line. It is the only new indicator, and it is not drawn
  when the reader pulled — the platform's own pull spinner is that refresh's
  indicator, and two indicators for one refresh is worse than one.
- **Completion is a timestamp that updates, not a transient message.** A source
  that answers stamps the moment it answered, so the source detail screen's
  *Last sync* row becomes live, and the shelf's strip can state when the
  libraries were last checked. No toast: Android has snackbars and iOS has
  nothing of the kind, and ADR-0001 forbids inventing a shared one.
- **Android's pull spinner follows the network probe as well as the folder
  walk**, so a pull on a server's shelf is not silent.
- **One pure decision owns the whole strip.** Which of the four lines is drawn is
  answered by a type a test can reach, as `ShelfRefresh` already is for what a
  pull re-fetches. The if/else chains in `LibraryView.swift` and `LibraryNotices`
  are replaced by it.
- **Nothing new is drawn on four surfaces**, and design.md says which and why:
  the source detail screen, the catalogue and server browsers, the reader, and
  Settings' source list.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sources`: one new requirement, *Refresh visibility*, stating what a reader
  sees while a refresh runs and what they see when it ends, per occasion. No
  existing requirement is modified — the three quoted above are satisfied by what
  exists, and this one states the behaviour none of them reaches.

## Impact

- `apps/ios/Packages/StoryArcKit/Sources/StoryArcCore`: `SourceRegistry.swift`
  (`marking` stamps the moment a source answered).
- `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature`: new
  `SourceRefresh.swift` (the origin, the notice decision, the two new views),
  `LibraryModel.swift`, `LibrarySourceHealth.swift`, `LibraryView.swift`,
  `Resources/Localizable.xcstrings`.
- `apps/android/core/model`: `SourceRegistry.kt` (the same stamp).
- `apps/android/feature/library`: new `SourceRefresh.kt`, `StillBeingRead.kt`,
  `LibraryScreen.kt`, `LibraryViewModel.kt`, `SourceRetry.kt`, and the four
  `res/values*/strings.xml`.
- `apps/android/app`: `AppDestinations.kt` (the probe lambda carries an origin).

## Non-Goals

- **Per-source scoping of the network probe.** `ShelfRefresh` records that a
  shelf narrowed to one server asks every configured server. That is a separate
  cost with a separate fix, and this change neither widens nor narrows it.
- **A progress count.** The indicator says a refresh is running, not how far
  through it is. A count of sources answered would have to be honest about a
  server that answers in one request and a folder walk that answers in
  thousands, and those are not the same unit.
- **A notification.** `Automatic recovery` forbids one, and this change does not
  add one.
