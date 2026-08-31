## MODIFIED Requirements

### Requirement: Reading aloud

The app SHOULD read a publication aloud using the platform speech engine.

Read-aloud SHALL drive the player defined in
[`audio-playback`](../audio-playback/spec.md) rather than controls of its own, and
SHALL NOT stop because the reader left the publication.

> **What changes, and what does not.** Every behaviour the previous version of this
> requirement specified is kept below word for word: the highlight, the page
> following the voice, carrying on past a chapter boundary, the position that is
> where the voice got to, the interruption rules, and the absent control for a
> publication with no text. What is added is that the session has somewhere to live
> once the publication is closed.

#### Scenario: Starting playback
- **WHEN** a user starts read-aloud on a reflowable publication
- **THEN** speech begins at the current position, the spoken sentence is highlighted, and the page follows
- **AND** the player's compact bar appears, naming the publication and the chapter being spoken

#### Scenario: Leaving the publication while it speaks
- **WHEN** a reader closes the reader, or navigates anywhere else in the app, while read-aloud is playing
- **THEN** the voice carries on, and the compact bar is how the reader gets back to it
- **AND** returning resumes at the sentence being spoken then, not at the position from when they left, because the voice did not wait

#### Scenario: The same controls as a narrated book
- **WHEN** a listener opens the full player during read-aloud
- **THEN** speed, skip, the sleep timer and the chapter list all work, per [`audio-playback`](../audio-playback/spec.md)
- **AND** the voice is named on the publication's own page rather than in the player, because a listener is listening to the book either way

#### Scenario: Background and lock screen
- **WHEN** read-aloud is playing and the app is backgrounded
- **THEN** playback continues, and platform media controls show the publication title and offer play, pause, and sentence skip
- **AND** the second line names the chapter being spoken, or the author where the publication declares no navigation

#### Scenario: Reaching the end of a chapter
- **WHEN** the voice reaches the end of the resource it is reading
- **THEN** it carries on into the next one without being asked, because a chapter boundary is not something a listener asked to stop at
- **AND** at the end of the publication it stops, the highlight is withdrawn, and the media controls go away rather than offering to play a book that has run out of words
- **AND** the compact bar goes away with them

#### Scenario: Where the listening got to
- **WHEN** a reader has listened for a while and closes the publication
- **THEN** the position [`reading-progress`](../reading-progress/spec.md) records is where the voice got to, not where the reading stopped, because the page followed the voice

#### Scenario: Something else takes the audio
- **WHEN** a phone call, another app, or a spoken direction takes the audio while read-aloud is playing
- **THEN** the voice stops, and when the audio comes back and the platform says playback may resume, it carries on by itself
- **AND** a pause the reader made themselves is never undone this way, however the interruption ends
- **AND** audio taken for good stops the session rather than leaving it paused for ever

#### Scenario: A publication with nothing to say
- **WHEN** a publication carries no text that can be extracted
- **THEN** the read-aloud control is absent rather than present and refusing
