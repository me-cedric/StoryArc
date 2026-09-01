## ADDED Requirements

### Requirement: One player for everything that speaks

The app SHALL present a single playback surface, and every source of spoken audio —
a narrated audiobook and the read-aloud voice alike — SHALL drive that one surface.

A listener knows they are listening to a book. Which of the two produced the sound
is a fact about the file, stated once where the publication is described, and never
a reason to learn a second set of controls.

#### Scenario: The compact bar
- **WHEN** something is playing or paused and the listener is anywhere but the full player
- **THEN** a compact bar rests above the navigation control, naming the publication and the chapter being spoken, and offering play, pause and a way to open the full player
- **AND** it does not displace, cover or resize the navigation control, and the content behind it can still be scrolled to its end

#### Scenario: Nothing is playing
- **WHEN** no session is active
- **THEN** the compact bar is absent rather than present and empty, and the space it occupied returns to the content

#### Scenario: The full player
- **WHEN** the compact bar is opened
- **THEN** the full player shows the cover, the publication, the chapter, the position and duration, and offers play, pause, skip back, skip forward, a scrub control, the chapter list, playback speed and a sleep timer
- **AND** the same source that fed the compact bar feeds this, so opening it never restarts, reloads or repositions the audio

#### Scenario: A publication with no cover
- **WHEN** the player shows a publication the app holds no cover art for
- **THEN** it draws the same coverless treatment every other surface draws — the title set as artwork — rather than a generic glyph
- **AND** the system's own media controls get that same artwork, because a lock screen showing a headphones symbol is the one place a listener looks for an hour

#### Scenario: Both sources look the same
- **WHEN** the player is driven by the read-aloud voice rather than by a narrated file
- **THEN** the surface, the controls and the lock-screen presentation are the same, and the synthesised voice is named once on the publication's own page rather than in the player
- **AND** every control the player offers works, or is absent — none is present and refusing

#### Scenario: Playback outlives the publication
- **WHEN** a listener leaves the publication, or the reader, while audio is playing
- **THEN** playback continues and the compact bar carries it, so the listener can browse, search or close the reader without stopping the book
- **AND** the way back to where the audio is reading is one action from the compact bar

#### Scenario: Starting a second thing
- **WHEN** a listener starts playing a second publication while one is already playing
- **THEN** the first stops and its position is recorded before the second begins, because two books speaking at once is never what was meant
- **AND** the first is not resumed automatically when the second ends

### Requirement: Playback controls

The player SHALL offer the controls a listener of a book needs, and each SHALL be
remembered where remembering it is what the listener would expect.

#### Scenario: Speed
- **WHEN** a listener changes playback speed
- **THEN** the audio changes speed without changing pitch, the value is stated as a number, and it is remembered for that publication and offered as the default for others in the same series
- **AND** at least the range from half speed to triple speed is offered

#### Scenario: Skipping
- **WHEN** a listener uses skip back or skip forward
- **THEN** the audio moves by a fixed interval the listener can configure, and the interval is stated on the control itself
- **AND** skipping past the start or the end of a chapter continues into the neighbouring one rather than stopping at the boundary

#### Scenario: Sleep timer
- **WHEN** a listener sets a sleep timer
- **THEN** a duration or *end of chapter* may be chosen, the remaining time is shown on the player, and playback fades out rather than cutting off when it elapses
- **AND** the position at which it stopped is recorded, so resuming starts a little before it rather than where the fade ended

#### Scenario: Chapters
- **WHEN** a listener opens the chapter list
- **THEN** every chapter is listed with its duration and the current one marked, and choosing one moves there
- **AND** a publication with no chapter markers lists its parts in playing order instead, rather than showing an empty list

#### Scenario: Lock screen and system controls
- **WHEN** audio is playing and the app is in the background
- **THEN** the system's own media controls show the cover, the publication, the chapter, the elapsed and total time, and offer play, pause, and skip in both directions
- **AND** those controls drive the same session, so using them keeps the app's own surface in step

#### Scenario: Something else takes the audio
- **WHEN** a call, another app or a spoken direction takes the audio
- **THEN** playback stops, and resumes by itself when the system says it may — but a pause the listener made is never undone this way
- **AND** audio taken for good ends the session and records the position rather than leaving it paused for ever

#### Scenario: Headphones removed
- **WHEN** the audio route changes to the device's own speaker because headphones were disconnected
- **THEN** playback pauses, because a book suddenly playing out loud is never what was intended
- **AND** it does not resume by itself when they are reconnected

### Requirement: Reaching the player without sight

Every playback control SHALL be operable by assistive technology, and the surface
SHALL be usable at the largest text size.

#### Scenario: Labels and values
- **WHEN** a screen reader reaches a playback control
- **THEN** it is announced with a name and, where it carries one, its value — the speed, the skip interval, the remaining sleep time, the position
- **AND** the scrub control is announced as an adjustable with its position stated in time, not as a percentage

#### Scenario: The compact bar under a screen reader
- **WHEN** a screen reader reaches the compact bar
- **THEN** it is announced as one element naming what is playing, with its play/pause action and its open action reachable separately
- **AND** it does not steal focus when it appears, because a listener who started a book and moved on did not ask to be taken back

#### Scenario: At the largest text size
- **WHEN** the player is shown at the largest accessibility text size
- **THEN** the publication, the chapter and every stated value are readable in full, the surface scrolls if it must, and no transport control is pushed off the screen
- **AND** the compact bar grows to fit its text rather than truncating the chapter to one word
