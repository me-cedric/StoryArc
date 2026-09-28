## ADDED Requirements

### Requirement: A publication's actions wherever it is drawn

Every place that draws a publication SHALL offer the same set of actions on it, through
the platform's own gesture for secondary actions: a long press with a menu on Android,
and a context menu on iOS.

#### Scenario: The same actions in every place
- **WHEN** a reader long-presses a publication on Android, or opens its context menu on iOS, in the library grid or list, on the home surface, in search results, on a shelf, on a collection or reading-list page, or in a server's own browser
- **THEN** the same actions are offered in every one of those places: open, mark as read or mark as unread, start from the beginning, add to a shelf, download or remove the download, and show the publication's details
- **AND** on a shelf, a collection or a reading list the reader owns, the menu also offers to remove the publication from that shelf

#### Scenario: Marking a server publication
- **WHEN** a reader marks a publication from a server as read or unread from that menu
- **THEN** the local state changes at once, and the change is sent to the server, or held and sent when the server is reachable again
- **AND** a server that refuses the change states the refusal on the screen where the reader made it

#### Scenario: An action that does not apply
- **WHEN** an action cannot apply to a publication, such as removing a download that does not exist
- **THEN** the menu does not offer that action, rather than offering it disabled

### Requirement: The finished mark

A publication the reader has finished SHALL carry a mark on its cover that a reader
sees at a glance.

#### Scenario: Seeing what is finished
- **WHEN** the library, the home surface, a shelf or search draws a finished publication
- **THEN** its cover carries a finished mark that is legible on a light cover and on a dark cover, in both appearances and at the largest text size
- **AND** the mark follows each platform's own form for a status badge
- **AND** VoiceOver and TalkBack announce the publication as finished
