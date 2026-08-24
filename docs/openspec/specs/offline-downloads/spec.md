# offline-downloads Specification

## Purpose

Taking a library with you. Downloading is the difference between an app that
works on the sofa and one that works on a plane — and the reason not to hammer
someone's NAS for the same 400 MB archive every evening.

## Requirements

### Requirement: Downloading

The app SHALL let a user download any publication from a remote source for
offline reading.

#### Scenario: Downloading one publication
- **WHEN** a user downloads a publication
- **THEN** it is queued, its size is shown, and progress is visible on the publication and in a single downloads view

#### Scenario: Downloading a collection or reading list
- **WHEN** a user downloads a whole collection, reading list, or series
- **THEN** the app states the item count and total size and asks for confirmation before queueing them
- **AND** a partially downloaded group shows how many of its items are complete

#### Scenario: Already downloaded
- **WHEN** a publication is already downloaded
- **THEN** the download action is replaced by a state indicator and a remove-download action, and the app does not re-fetch it

#### Scenario: Reading while downloading
- **WHEN** a user opens a publication that is still downloading
- **THEN** it opens immediately by streaming, and switches to the local copy when the download completes, without interrupting reading

### Requirement: Queue management

The app SHALL give the user control over the download queue.

#### Scenario: Queue controls
- **WHEN** a user opens the downloads view
- **THEN** active, queued, and failed downloads are listed with per-item and global pause, resume, cancel, and reorder

#### Scenario: Resuming after interruption
- **WHEN** a download is interrupted by network loss, app termination, or a device restart
- **THEN** it resumes from where it stopped if the server supports range requests, and restarts otherwise, stating which happened

#### Scenario: Background downloads
- **WHEN** the app is backgrounded with downloads in progress
- **THEN** they continue under the platform's background transfer mechanism as far as the platform allows
- **AND** the app does not claim a download will finish in the background when the platform will suspend it

#### Scenario: Failure
- **WHEN** a download fails
- **THEN** it is retried automatically up to three times with backoff, then marked failed with a plain-language reason and a retry action

#### Scenario: Concurrency
- **WHEN** several downloads are queued
- **THEN** a bounded number run concurrently, and the bound is lowered on a metered connection

### Requirement: Network policy

The app SHALL respect the user's data.

#### Scenario: Wi-Fi only
- **WHEN** the "download over Wi-Fi only" setting is on and the device is on cellular
- **THEN** downloads pause and state that they are waiting for Wi-Fi, and resume automatically when it returns

#### Scenario: Data saver
- **WHEN** the platform's data saver or Low Data Mode is active
- **THEN** the app treats the connection as metered regardless of its own setting

#### Scenario: Overriding once
- **WHEN** a user explicitly downloads a specific publication while on a metered connection
- **THEN** the app confirms with the size and proceeds for that item only

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
- **THEN** its download is removed, its progress is kept, and the removal is undoable for 10 seconds

#### Scenario: Device storage is low
- **WHEN** the device reports low storage
- **THEN** the app pauses downloads, evicts the cover cache before any downloaded publication, and never deletes a download without asking

#### Scenario: Backup exclusion
- **WHEN** downloaded publications are written to disk
- **THEN** they are excluded from device backups, because they are re-downloadable and would otherwise dominate a backup

### Requirement: Offline integrity

A downloaded publication SHALL be readable with no network, indefinitely.

#### Scenario: Reading fully offline
- **WHEN** a user reads a downloaded publication in airplane mode
- **THEN** every page, the cover, and the cached metadata are available with no degradation

#### Scenario: Verifying a download
- **WHEN** a download completes
- **THEN** its integrity is verified before it is marked available offline, and a failed verification re-queues it once
