## MODIFIED Requirements

### Requirement: Metadata cache

The app SHALL cache each source's catalogue — titles, series, covers, and
structural metadata — locally, so the library opens instantly and stays
browsable while offline. This SHALL hold for every kind of source, including a
server's catalogue.

#### Scenario: Opening the library offline
- **WHEN** a user opens the library with every source unreachable
- **THEN** the full cached catalogue is displayed within 500 ms of the library view appearing
- **AND** a single unobtrusive indicator states that content is cached and when it was last refreshed

#### Scenario: Refreshing a source
- **WHEN** a user pulls to refresh, or a source's cache exceeds its staleness window
- **THEN** the app re-fetches the catalogue in the background
- **AND** updates the view incrementally rather than clearing it and re-populating

#### Scenario: What a cached catalogue may not hold
- **WHEN** a source's catalogue is written to disk
- **THEN** no credential is written with it — an address that carries a secret, in a query, in userinfo or in a path, is stored with the secret removed and the secret left in the credential store
- **AND** a stored address that cannot be used without its secret is re-derived when it is needed, rather than kept whole

#### Scenario: A cached catalogue under storage pressure
- **WHEN** the device is short of space
- **THEN** a cached catalogue is evictable independently of downloaded publications and of reading progress
- **AND** evicting it removes rows from the library rather than leaving rows that open nothing, and the source is marked as needing to be read again

#### Scenario: Publication disappears from a source
- **WHEN** a refresh shows a publication is no longer present in the source
- **AND** the publication is not downloaded
- **THEN** it is removed from the library view and its reading progress is retained

#### Scenario: A source that answered nothing
- **WHEN** a refresh fails, or answers with nothing at all
- **THEN** what was cached from that source stays in the library
- **AND** nothing is removed on the strength of an answer the app did not get, because a failed refresh and an emptied source are different things

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

#### Scenario: A source the app has read only part of
- **WHEN** a source holds more publications than the app has read
- **THEN** its detail screen states how many are in the library and that the source holds more, rather than presenting the count as the whole
- **AND** offers to read more of it
