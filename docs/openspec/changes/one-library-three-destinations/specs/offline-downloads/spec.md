## ADDED Requirements

### Requirement: Everything on this device

The app SHALL offer, as one of its three destinations, everything that can be
read with no network — not merely the transfer queue — presented with the same
grid, the same cells and the same publication pages as the library.

#### Scenario: What the destination holds
- **WHEN** a reader opens the on-device destination
- **THEN** it shows every publication readable with no network, whatever source it came from and however it got there
- **AND** it is presented as a library rather than as a list of transfers, so a reader before a flight sees what they can read rather than what was fetched

#### Scenario: Sorting and filtering it
- **WHEN** a reader sorts or filters within the on-device destination
- **THEN** the same sorts and filters the library offers apply, minus the availability axis, which this destination already fixes
- **AND** those choices persist for this destination independently of the library's

#### Scenario: Nothing downloaded yet
- **WHEN** nothing is readable offline
- **THEN** the destination says so in one sentence and offers the action that changes it, rather than showing an empty grid
- **AND** the destination is still present and selectable, because a destination that disappears teaches a reader nothing

#### Scenario: Removing a download from here
- **WHEN** a reader removes a download from this destination
- **THEN** the publication leaves this destination and stays in the library, with its reading position kept
- **AND** the removal is undoable for the same window as any other download removal

#### Scenario: Airplane mode
- **WHEN** the device has no network at all
- **THEN** this destination is complete and fully functional, with nothing dimmed and nothing waiting
- **AND** it is reachable directly from the app's launch, with no source consulted on the way

## MODIFIED Requirements

### Requirement: Queue management

The app SHALL give the reader control over the download queue, presented inside
the on-device destination while transfers are in flight and absent when none
are.

#### Scenario: Queue controls
- **WHEN** transfers are in flight or waiting
- **THEN** they appear at the top of the on-device destination, listing active, queued and failed items with per-item and global pause, resume, cancel and reorder
- **AND** when nothing is in flight the queue is absent rather than shown empty, and the destination is just the readable library

#### Scenario: Watching a download without leaving the shelf
- **WHEN** a reader starts a download from the library or from a publication's page
- **THEN** progress is visible where they started it, and they are not moved to another screen
- **AND** the on-device destination indicates that something is in flight without demanding attention

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
