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
- **THEN** it draws the same coverless treatment every other surface draws — the publication's kind, as a symbol over the format's name — rather than one glyph for everything or a treatment of the player's own
- **AND** the treatment does not repeat the publication's title, because every surface that draws this well states the title beside it and the lock screen states it too
- **AND** the system's own media controls are given that same artwork rather than a second one, because the lock screen is where a listener looks for an hour

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

#### Scenario: Where a listening position is written
- **WHEN** a listener pauses, skips, scrubs, chooses a chapter from a list, crosses into another part, or sends the app to the background
- **THEN** the position is written at that moment, because each of those is a listener deciding where they are rather than the audio drifting there
- **AND** a book left playing with none of those happening is written at least every fifteen seconds of audio, so a process the system reclaims mid-chapter costs no more than that
- **AND** every one of those writes reads the position from the player itself at the moment it writes, never from a value a surface published earlier, because a surface is only refreshed when the engine reports something and a clock running on reports nothing
- **AND** no write happens more often than those moments — a scrub writes when the listener lets go of the control and not while they drag it, because a position store written on every frame is a defect of its own

### Requirement: Playback controls

The player SHALL offer the controls a listener of a book needs, and each SHALL be
remembered where remembering it is what the listener would expect.

#### Scenario: Speed
- **WHEN** a listener changes playback speed
- **THEN** the audio changes speed without changing pitch, the value is stated as a number, and it is remembered for that publication and offered as the default for others in the same series
- **AND** at least the range from half speed to triple speed is offered

#### Scenario: Skipping
- **WHEN** a listener uses skip back or skip forward
- **THEN** the audio moves by a fixed interval, stated on the control itself: fifteen seconds back and thirty seconds forward
- **AND** the interval is not configurable, because a listener who wants a different one wants it once and then never thinks about it again, and a control that states its own number needs no explanation
- **AND** skipping past the start or the end of a chapter continues into the neighbouring one rather than stopping at the boundary

#### Scenario: Sleep timer
- **WHEN** a listener sets a sleep timer
- **THEN** a duration or *end of chapter* may be chosen, the remaining time is shown on the player, and playback fades out rather than cutting off when it elapses
- **AND** the position at which it stopped is recorded, so resuming starts a little before it rather than where the fade ended

#### Scenario: Chapters
- **WHEN** a listener opens the chapter list
- **THEN** every chapter is listed with its duration, and choosing one moves there
- **AND** a chapter already finished is marked as finished, a chapter not yet reached carries no mark, and the chapter in progress is marked as the one in progress
- **AND** the chapter in progress also states how much of itself is left, so a listener can tell a chapter they have just begun from one they are about to finish
- **AND** every surface that lists chapters states all of that, the player and the publication's page alike, because a listener reads the list to decide and the player is where they read it while listening
- **AND** a screen reader hears the chapter, its duration, its mark and the remaining time as one control
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
- **THEN** it is announced with a name and, where it carries one, its value — the speed, the remaining sleep time, the position
- **AND** the scrub control is announced as an adjustable with its position stated in time, not as a percentage

#### Scenario: The compact bar under a screen reader
- **WHEN** a screen reader reaches the compact bar
- **THEN** it is announced as one element naming what is playing, with its play/pause action and its open action reachable separately
- **AND** it does not steal focus when it appears, because a listener who started a book and moved on did not ask to be taken back

#### Scenario: At the largest text size
- **WHEN** the player is shown at the largest accessibility text size
- **THEN** the publication, the chapter and every stated value are readable in full, the surface scrolls if it must, and no transport control is pushed off the screen

#### Scenario: The compact bar at the largest text size
- **WHEN** the compact bar is shown at the largest accessibility text size
- **THEN** no transport control is pushed off the screen or shrunk below the platform's minimum touch target, because the transport is what the bar is for
- **AND** whatever text the bar can show is cut at a word and marked as cut, never clipped mid-letter
- **AND** text the bar cannot show is announced in full by assistive technology, and shown in full on the player the bar opens onto
- **AND** where the app owns the bar's height, the bar grows to fit its text rather than cutting it at all

> **The last clause is conditional because on one platform the height is not the app's to
> give, and the unconditional version asked for something worse.** It used to read "the
> compact bar grows to fit its text rather than truncating the chapter to one word", and iOS
> cannot honour it: its bar is `tabViewBottomAccessory`, whose height is the **system's**.
> Removing the line limit there does not make the bar taller — it trades a *truncated* title,
> which is honest and readable, for a *clipped* one, which is neither. iOS's own accessibility
> audit reports `Text clipped` on that bar, and satisfying the old wording would have made
> that finding permanent rather than fixing it.
>
> So the requirement now states what a reader needs — the transport stays usable, the cut is
> honest, and nothing is *only* available in the place that cannot show it — and asks for
> growth where growth is the app's to give. Android's bar is hand-composed and measures
> itself, so it grows and is asserted doing so. iOS truncates, announces the untruncated text,
> and opens onto a surface with room. **Neither platform is excused a clause; they satisfy
> different ones, and which one is decided by who owns the height.** Recorded 2026-09-01 after
> `/opsx:update`; §8.4 of the task list carries the per-platform evidence.

### Requirement: Chapters before the first minute

A listener SHALL be able to see an audiobook's chapters without starting it, and SHALL be
able to start at any one of them.

The publication's own page SHALL list them. The player already lists them, and the player is
reached by starting the book, so a listener choosing what to listen to next could see a
chapter list only by first playing something they had not chosen.

#### Scenario: The chapter list on the publication's page
- **WHEN** a listener opens an audiobook's page in the library
- **THEN** the page lists its chapters in order, each with its title and its duration
- **AND** the chapter the listener stopped inside is marked as the one in progress
- **AND** a chapter already finished is marked as finished

#### Scenario: Starting from a chapter
- **WHEN** a listener chooses a chapter on the publication's page
- **THEN** playback starts at that chapter rather than where the book was left
- **AND** the position the book was left at is not lost by looking at the list

#### Scenario: An audiobook with one part
- **WHEN** an audiobook carries no chapter markers and is a single file
- **THEN** the page states the book's duration and offers no list, because a list of one row tells a listener nothing
- **AND** nothing is reported as missing, by the same rule that opens an unchaptered audiobook without complaint

#### Scenario: The primary action says where it will resume
- **WHEN** a listener opens the page of an audiobook they have already started
- **THEN** the action that starts playback names the chapter it will resume inside
- **AND** an audiobook never started offers to start it, naming no chapter

### Requirement: Listening in a car

The app SHALL offer its audiobooks to the car systems each platform provides, so a listener
can browse and control a book without handling the phone.

A car surface SHALL show what the listener was in the middle of, and SHALL let them browse
the audiobooks on the device. It SHALL NOT require the app to be open on the phone first.

#### Scenario: Continuing in the car
- **WHEN** a listener connects to a car and asks for StoryArc
- **THEN** the book they were in the middle of is offered first, with its position kept
- **AND** it is offered even when the app was not running, because the system starts the app for this

#### Scenario: Browsing audiobooks in the car
- **WHEN** a listener browses StoryArc on a car screen
- **THEN** the audiobooks on the device are listed, and choosing one starts it
- **AND** the list is short and flat, because a car screen is read at a glance and deep browsing is a driving hazard

#### Scenario: The car's own transport controls
- **WHEN** a listener uses the car's play, pause or skip controls
- **THEN** the book responds as it does in the app, and the position is recorded the same way
- **AND** a chapter is what a skip moves between, so a car's next-track control moves a chapter rather than a file

#### Scenario: Only what a car should carry
- **WHEN** the car surface is built
- **THEN** it offers audiobooks and read-aloud sessions and nothing else, because a car screen is not a place to browse comics
