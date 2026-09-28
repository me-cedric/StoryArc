## MODIFIED Requirements

### Requirement: Storage management

The app SHALL make downloaded storage visible and controllable.

#### Scenario: Storage view
- **WHEN** a user opens storage settings
- **THEN** total space used is shown, broken down by source and by the largest publications, alongside the cover cache size
- **AND** each row can be removed individually

#### Scenario: Storage limit
- **WHEN** a user sets a maximum download size
- **THEN** the app stops downloading when the limit is reached and offers to remove finished publications to make room

#### Scenario: Automatic cleanup
- **WHEN** the "remove downloads after finishing" setting is on and a user finishes a publication
- **THEN** its download is removed when the reader closes, its progress is kept, and the removal is undoable for 10 seconds
- **AND** a "Keep" action offered on the reader's own end screen, per [`comic-reader`](../comic-reader/spec.md) "Reaching the end", exempts that publication from this removal

#### Scenario: Device storage is low
- **WHEN** the device reports low storage
- **THEN** the app pauses downloads, evicts the cover cache before any downloaded publication, and never deletes a download without asking

#### Scenario: Backup exclusion
- **WHEN** downloaded publications are written to disk
- **THEN** they are excluded from device backups, because they are re-downloadable and would otherwise dominate a backup
