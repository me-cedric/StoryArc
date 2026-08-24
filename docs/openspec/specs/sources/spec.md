# sources Specification

## Purpose

A source is any place StoryArc can read publications from: a device folder, a
network share, an OPDS catalogue, or a Kavita server. This capability owns the
lifecycle every source shares — adding one, storing its credentials, knowing
whether it is reachable, caching what it contains so the library stays browsable
when it is not, and removing it cleanly.

Source-type specifics live in [`local-library`](../local-library/spec.md),
[`network-share`](../network-share/spec.md), [`opds-catalog`](../opds-catalog/spec.md)
and [`kavita-server`](../kavita-server/spec.md).

## Requirements

### Requirement: Source registry

The app SHALL maintain an ordered, persistent registry of configured sources,
each with a user-editable display name, a type, a connection state, and the
timestamp of its last successful sync.

#### Scenario: Adding the first source
- **WHEN** a user opens the app with no source configured
- **THEN** the app presents an empty state naming the four source types with a one-line explanation of each
- **AND** offers to open a local file or folder without configuring anything, so the app is usable in under ten seconds

#### Scenario: Reordering sources
- **WHEN** a user drags a source into a new position in the source list
- **THEN** the new order persists across launches
- **AND** the library's combined view lists titles from higher sources first when two sources hold the same publication

#### Scenario: Renaming a source
- **WHEN** a user edits a source's display name
- **THEN** the new name appears everywhere the source is referenced, including download attributions and error messages

#### Scenario: Removing a source
- **WHEN** a user removes a source
- **THEN** the app states how many downloaded files and how much disk space will be freed before asking for confirmation
- **AND** on confirmation removes the source, its cached metadata, its stored credentials, and its downloads
- **AND** retains local reading progress for those publications for 30 days, so re-adding the same source restores where the user stopped

### Requirement: Credential storage

The app SHALL store every source secret — password, API key, or token — in the
platform secure store, and SHALL NOT write a secret to preferences, logs,
crash reports, backups, or exported diagnostics.

#### Scenario: Storing a secret
- **WHEN** a user saves a source that requires authentication
- **THEN** the secret is written to the iOS Keychain or the Android `EncryptedSharedPreferences`-backed store
- **AND** the registry entry holds only an opaque reference to it

#### Scenario: Secret appears in a diagnostic
- **WHEN** the app writes a log line, an error message, or a diagnostic bundle containing a URL with embedded credentials
- **THEN** the credential portion is redacted before the line leaves memory

#### Scenario: Reading a secret
- **WHEN** the app needs a secret to authenticate a request
- **THEN** it reads it from the secure store at the moment of use and does not retain it beyond the request

### Requirement: Connection state

Every source SHALL report one of four states — `connected`, `connecting`,
`unreachable`, or `unauthorized` — and SHALL surface that state without blocking
the user from browsing what is already cached.

#### Scenario: Source becomes unreachable
- **WHEN** a source fails to respond
- **THEN** the source is marked `unreachable` with a neutral indicator, never a red error badge
- **AND** its cached contents remain browsable
- **AND** titles that are not downloaded are shown dimmed and are not openable

#### Scenario: Credentials rejected
- **WHEN** a source returns an authentication failure
- **THEN** the source is marked `unauthorized`
- **AND** the app offers a single action to re-enter credentials, pre-filled with everything except the secret

#### Scenario: Automatic recovery
- **WHEN** an `unreachable` source becomes reachable again
- **THEN** the app reconnects without user action and updates the state
- **AND** does not present a notification or interrupt reading

#### Scenario: Retry policy
- **WHEN** a source is `unreachable`
- **THEN** the app retries with exponential backoff starting at 5 seconds and capping at 5 minutes
- **AND** retries immediately, once, when the device regains network connectivity or the app returns to the foreground

### Requirement: Metadata cache

The app SHALL cache each source's catalogue — titles, series, covers, and
structural metadata — locally, so the library opens instantly and stays
browsable while offline.

#### Scenario: Opening the library offline
- **WHEN** a user opens the library with every source unreachable
- **THEN** the full cached catalogue is displayed within 500 ms of the library view appearing
- **AND** a single unobtrusive indicator states that content is cached and when it was last refreshed

#### Scenario: Refreshing a source
- **WHEN** a user pulls to refresh, or a source's cache exceeds its staleness window
- **THEN** the app re-fetches the catalogue in the background
- **AND** updates the view incrementally rather than clearing it and re-populating

#### Scenario: Publication disappears from a source
- **WHEN** a refresh shows a publication is no longer present in the source
- **AND** the publication is not downloaded
- **THEN** it is removed from the library view and its reading progress is retained

#### Scenario: Cover caching
- **WHEN** a cover image is fetched
- **THEN** it is stored on disk at display resolution for the device
- **AND** the cover cache is evictable under storage pressure independently of downloaded publications

### Requirement: Source health visibility

The app SHALL provide one screen listing every source with its state, last sync
time, cached item count, and downloaded size.

#### Scenario: Diagnosing a source
- **WHEN** a user opens a source's detail screen
- **THEN** the screen shows the state, the last successful sync, the last error in plain language, the item count, and the bytes downloaded
- **AND** offers actions to test the connection, refresh, clear the cache, remove downloads, and remove the source

## Open Questions

- Should two sources exposing the same publication be de-duplicated into one
  library row with a source picker, or listed separately? Current requirement
  orders by source priority; de-duplication is deferred.
