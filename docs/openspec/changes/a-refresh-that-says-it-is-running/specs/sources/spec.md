## ADDED Requirements

### Requirement: Refresh visibility

The app SHALL state that a source refresh is running, and SHALL state when one
last succeeded, wherever a reader can see the result of it. One refresh SHALL be
stated once: a surface whose own gesture already draws an indicator SHALL NOT
draw a second one.

#### Scenario: A refresh nobody asked for

- **WHEN** the app re-fetches the catalogue without the user asking — on the library appearing, on a source being added, on the retry schedule, on connectivity being regained, or on the app returning to the foreground
- **THEN** the library states that a refresh is running, in the same single unobtrusive place that states that content is cached
- **AND** states it without moving, hiding or dimming any publication already on the shelf
- **AND** stops stating it when the refresh ends, whether it succeeded or not

#### Scenario: A refresh the user asked for

- **WHEN** a user pulls to refresh
- **THEN** the platform's own pull indicator runs for as long as the refresh runs, including a refresh that asks only a remote source and walks no folder
- **AND** no second indicator is drawn for that refresh

#### Scenario: A refresh that finished

- **WHEN** a source answers a refresh
- **THEN** the moment it answered is recorded as that source's last successful sync
- **AND** the source's detail screen states that moment, and restates it after each later refresh
- **AND** the library states when the sources were last refreshed, as the quietest of the things its indicator has to say

#### Scenario: A refresh that failed

- **WHEN** a refresh ends with a source unreachable or unauthorized
- **THEN** the app does not record a successful sync for that source
- **AND** the source keeps the moment of its last successful sync, so a reader can tell a source that has never answered from one that answered yesterday

#### Scenario: A refresh of one source from its own screen

- **WHEN** a user refreshes one source from that source's detail screen
- **THEN** the screen states that the source is being asked, for as long as it is being asked
- **AND** states the outcome as that source's state and last successful sync, rather than as a message that disappears

#### Scenario: Nothing to say

- **WHEN** no refresh is running and no source has ever answered
- **THEN** the library draws no refresh indicator at all
