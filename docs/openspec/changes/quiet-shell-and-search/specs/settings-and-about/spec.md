## ADDED Requirements

### Requirement: What changed in this version

The app SHALL tell a reader what changed, once, after it has been updated, and SHALL
never let that get in the way of reading.

A reading app is opened to read. Everything below follows from that: the notice is
shown once per version, it is dismissed by one action, it never appears on a first
ever launch, and it is reachable afterwards for somebody who dismissed it too fast.

#### Scenario: After an update
- **WHEN** a reader opens the app for the first time after it has been updated
- **THEN** a screen names the version and lists what changed in it, in the reader's own language
- **AND** one action dismisses it, and it is not shown again for that version

#### Scenario: A first ever launch
- **WHEN** a reader opens the app for the first time ever
- **THEN** the screen does not appear, because somebody who has never used the app has nothing to catch up on
- **AND** the version is recorded as seen, so the next update is the first thing they are told about

#### Scenario: Nothing worth saying
- **WHEN** a version ships with nothing a reader would notice
- **THEN** no screen appears
- **AND** the version is still recorded as seen, so the entry is not shown late alongside the next one

#### Scenario: Reading it again
- **WHEN** a reader wants to see what changed after dismissing the screen
- **THEN** it is reachable from the About screen, along with the entries for earlier versions
- **AND** reaching it that way does not change what the app considers seen

#### Scenario: An update installed while offline
- **WHEN** the app is opened after an update with no network
- **THEN** the screen appears in full, because what changed ships with the app and is never fetched

#### Scenario: At the largest text size
- **WHEN** the screen is shown at the largest accessibility text size
- **THEN** every entry's heading and sentence are readable in full, the screen scrolls if it must, and the dismissing action stays reachable without scrolling past the content
