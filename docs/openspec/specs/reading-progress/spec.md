# reading-progress Specification

## Purpose

Never losing someone's place. Progress is recorded locally first — that is the
copy that must always work — and synchronised outward to whichever sources can
hold it. When two devices disagree, the rule for resolving it must be
predictable enough that the user can reason about it.

## Requirements

### Requirement: Local progress store

The app SHALL record reading progress locally for every publication it opens,
independently of whether the source can store progress.

#### Scenario: Progress is recorded
- **WHEN** a user reads a publication
- **THEN** the position is written locally at least every 15 seconds of reading, on every chapter boundary, and whenever the reader is closed or backgrounded

#### Scenario: Position identity
- **WHEN** progress is recorded
- **THEN** it identifies a publication by a stable content identity, so the same file opened from a different path or a different source resolves to the same progress record

#### Scenario: App is terminated unexpectedly
- **WHEN** the app is killed by the system while reading
- **THEN** reopening the publication resumes at most 15 seconds of reading behind where the user stopped

#### Scenario: Finished state
- **WHEN** a user reaches the last page, or manually marks a publication read
- **THEN** it is recorded finished with a completion timestamp
- **AND** reopening a finished publication starts at the beginning while retaining the finished record

### Requirement: Resuming

The app SHALL make returning to where the user stopped the shortest path in the
app, and SHALL keep the two verbs a publication answers to distinct: a **resume
affordance** opens the book at the stored position, and a **cover** leads to that
publication's page, whose primary action continues from the same position.

Both are resuming. The difference is that one is an offer to carry on and the
other is an offer to look first, and a reader who chose to look should not be
dropped into the book.

This requirement SHALL state what each of the two verbs costs the reader in
actions, because the two costs differ and the cheaper one is what "the shortest
path" above means. The counts hold for a publication the app can open now. A
publication whose source is away, whose access is refused, or which must be
downloaded first draws no continue action, so no count applies to it.

#### Scenario: Continue from a resume affordance
- **WHEN** a reader chooses a partially read publication from Keep reading, or from any other affordance that offers to resume it
- **THEN** it opens at the stored position without an intermediate screen
- **AND** nothing between that affordance and the page they stopped on asks them anything
- **AND** the reader takes one action, on both platforms

#### Scenario: Continue from the library
- **WHEN** a reader chooses a partially read publication by its cover — in the library, in a shelf, in search results or in a collection
- **THEN** that publication's page opens, per [`publication-detail`](../publication-detail/spec.md), and its primary action opens the book at the stored position
- **AND** that action states that it will continue rather than start, so the reader knows which of the two will happen before taking it
- **AND** the page is the only thing between the cover and the book: no further screen, prompt or confirmation stands in the way of carrying on
- **AND** the reader takes two actions, on both platforms — the cover, then the primary action — which is one more than a resume affordance costs

#### Scenario: Restart deliberately
- **WHEN** a user wants to start over
- **THEN** a "Start from the beginning" action is available from the publication's own cover in the library — the same long press that offers to file it in a collection — and it clears progress only after confirmation
- **AND** it is offered only on a publication that has progress to clear, and only on one at a time, because a set of publications has no single beginning to return to
- **AND** it is on that menu because the menu is on every cover on every browse surface, so starting over never needs a screen opened first — and it is never a publication page's primary action, which continues from the stored position

### Requirement: Synchronisation

The app SHALL synchronise progress with sources that support it, in both directions.

#### Scenario: Pushing progress
- **WHEN** a user finishes a reading session on a synchronising source
- **THEN** progress is pushed on leaving the reader
- **AND** a failed push is queued and retried on the next successful connection, without an error being shown

#### Scenario: Pulling progress
- **WHEN** a synchronising source refreshes
- **THEN** progress recorded on other devices is merged into the local store

#### Scenario: Source cannot store progress
- **WHEN** a source has no progress mechanism
- **THEN** progress is kept locally only, and the source detail screen states that progress for it does not sync

### Requirement: Conflict resolution

The app SHALL resolve conflicting progress predictably and SHALL NOT silently
move a user backwards.

#### Scenario: Remote is further ahead
- **WHEN** the remote position is ahead of the local one and the local record has not changed since the last sync
- **THEN** the remote position is adopted silently

#### Scenario: Both changed since the last sync
- **WHEN** both the local and the remote position changed since the last successful sync
- **THEN** the app adopts the further position, and tells the user once, naming both positions and offering to use the other one

#### Scenario: Remote is behind
- **WHEN** the remote position is behind the local one
- **THEN** the local position is kept and pushed to the server

#### Scenario: Conflicting finished state
- **WHEN** one side reports finished and the other reports partial
- **THEN** finished wins, because unmarking a finished publication is a deliberate act and losing it is not

### Requirement: Progress across formats and sources

The app SHALL translate progress meaningfully rather than dropping it.

#### Scenario: Same publication from two sources
- **WHEN** a user reads a publication from a local folder and later opens the same publication from a server
- **THEN** the local progress applies, resolved through content identity

#### Scenario: Reflowable position
- **WHEN** progress is stored for a reflowable publication
- **THEN** it is stored as a position within the content, not as a page number, so it survives a typography change or a different device

### Requirement: Privacy of reading history

Reading history SHALL stay on the device and on the user's own servers.

#### Scenario: No third-party transmission
- **WHEN** progress is recorded or synchronised
- **THEN** it is sent only to sources the user configured, and to no analytics, crash-reporting, or third-party service

#### Scenario: Clearing history
- **WHEN** a user clears reading history in settings
- **THEN** every local progress record is deleted after confirmation, and the app states whether server-side progress is affected
