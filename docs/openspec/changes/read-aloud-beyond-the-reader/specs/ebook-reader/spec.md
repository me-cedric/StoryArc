## MODIFIED Requirements

### Requirement: Reading aloud

The app SHOULD read a publication aloud using the platform speech engine, and
the session SHALL outlive the screen it was started from.

#### Scenario: Starting playback
- **WHEN** a user starts read-aloud on a reflowable publication
- **THEN** speech begins at the current position, the spoken sentence is highlighted, and the page follows

#### Scenario: Closing the publication while it is being read
- **WHEN** a listener closes the publication while the voice is speaking
- **THEN** speech continues, and the listener is returned to whatever they were doing in the app rather than being kept in the book
- **AND** a transport is available from wherever they land, as *The transport outside the reader* requires
- **AND** reopening the publication resumes at the sentence being spoken, without the voice stopping or repeating

#### Scenario: Background and lock screen
- **WHEN** read-aloud is playing and the app is backgrounded
- **THEN** playback continues, and platform media controls show the publication title and offer play, pause, and sentence skip
- **AND** the second line names the chapter being spoken, or the author where the publication declares no navigation

#### Scenario: Reaching the end of a chapter
- **WHEN** the voice reaches the end of the resource it is reading
- **THEN** it carries on into the next one without being asked, because a chapter boundary is not something a listener asked to stop at
- **AND** at the end of the publication it stops, the highlight is withdrawn, and the media controls go away rather than offering to play a book that has run out of words

#### Scenario: Where the listening got to
- **WHEN** a reader has listened for a while and closes the publication
- **THEN** the position [`reading-progress`](../reading-progress/spec.md) records is where the voice got to, not where the reading stopped, because the page followed the voice
- **AND** this holds whether the session ended with the publication open or continued after it was closed, so nothing is lost by closing the book

#### Scenario: Something else takes the audio
- **WHEN** a phone call, another app, or a spoken direction takes the audio while read-aloud is playing
- **THEN** the voice stops, and when the audio comes back and the platform says playback may resume, it carries on by itself
- **AND** a pause the reader made themselves is never undone this way, however the interruption ends
- **AND** audio taken for good stops the session rather than leaving it paused for ever

#### Scenario: A publication with nothing to say
- **WHEN** a publication carries no text that can be extracted
- **THEN** the read-aloud control is absent rather than present and refusing

## ADDED Requirements

### Requirement: The transport outside the reader

While a read-aloud session is running and its publication is not open, the app
SHALL offer a transport that says what is being spoken, controls it, and returns
to it — and SHALL offer nothing when no session is running.

#### Scenario: Getting back to the book
- **WHEN** a listener chooses the transport while the voice is speaking
- **THEN** the publication opens at the sentence being spoken, without the voice stopping
- **AND** this works from every destination and from anywhere the listener has descended to

#### Scenario: Controlling it without going back
- **WHEN** a listener uses the transport
- **THEN** they can pause, resume, skip a sentence and end the session, without opening the publication first
- **AND** ending it withdraws the transport immediately

#### Scenario: What it says
- **WHEN** the transport is shown
- **THEN** it names the publication being spoken and the chapter, matching what the platform's own media controls show
- **AND** it never carries a control the media controls do not, so a listener learns one set of actions

#### Scenario: It is absent when nothing is playing
- **WHEN** no read-aloud session is running
- **THEN** no transport is present anywhere in the app, and no space is reserved for one
- **AND** it appears when a session starts and goes when the session ends, including when the publication runs out of words

#### Scenario: Opening a different publication
- **WHEN** a listener opens a different publication while the voice is speaking
- **THEN** the session ends at a sentence boundary and the position it reached is recorded before the new publication opens
- **AND** the listener is told once that the voice stopped, rather than discovering it by silence

#### Scenario: The transport on iOS
- **WHEN** a session is running on iOS and the publication is closed
- **THEN** the transport is a compact control carried by the app's own navigation, above it at full size and inline when the navigation is minimised
- **AND** it is the only persistent transport in the app, because the platform already offers the rest on the lock screen

#### Scenario: The transport on Android
- **WHEN** a session is running on Android and the publication is closed
- **THEN** the transport is the system media notification and the lock-screen controls the session already publishes
- **AND** no docked bar is added inside the app, because the platform's navigation has no such slot and the notification survives the app being backgrounded, which a bar cannot

#### Scenario: The session cannot continue
- **WHEN** the platform stops the session for a reason the app does not control — the process is reclaimed, speech becomes unavailable, or the audio is taken for good
- **THEN** the transport disappears rather than staying on screen unable to control anything
- **AND** the position the voice reached is recorded first

#### Scenario: Reaching the transport without touch
- **WHEN** a listener uses a screen reader, a keyboard or a switch
- **THEN** the transport is reachable in the reading order, states what it controls and what is playing, and each of its actions is labelled by what it does
- **AND** it does not take focus when it appears, because a session starting must not interrupt what the listener is doing
