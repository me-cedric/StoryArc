## MODIFIED Requirements

### Requirement: Auto-hiding chrome

The reader SHALL show no controls while reading, and reveal them on demand.

Revealed chrome SHALL consist of **a way out and a way in, and nothing else**: an
affordance that closes the publication, and one menu affordance that leads to
everything the reader can do with it. No third control appears over the page.

> **Why this is now a count.** The previous text specified a top bar, a bottom bar
> and a page slider, and each of the eleven controls between them was added on its
> own justification. Naming the two that may be over the page is the only form of
> this rule that holds: any other wording invites a twelfth.

#### Scenario: Entering the reader
- **WHEN** a publication opens
- **THEN** the page fills the screen, the system status and home indicators dim per platform convention, and the two controls are shown once and then withdraw themselves within a few seconds without being asked
- **AND** they are not shown again until a centre tap asks for them

> **This sentence used to say "chrome is hidden", and the screenshots caught that no
> reader had ever done it.** All four — both platforms, both readers — start with chrome
> visible and withdraw it after four seconds, and no source-level test looks at the
> arrival frame, so the divergence survived every gate for as long as the requirement has
> existed. See [`before-2026-08-31d`](../../../../designs/screenshots/after-2026-08-31d/README.md).
>
> The behaviour is the half that is right, and the sentence is the half being fixed. A
> reader who has just opened a book has not yet learned that a centre tap brings back the
> way out; showing it once and taking it away teaches that in the only place it can be
> taught, and costs four seconds of a page nobody is reading yet. Apple Books, which this
> change follows, does the same. A requirement that forbids it would make the app harder
> to leave in exchange for a purity no reader asked for.
>
> What is kept is the part that matters: the controls go **by themselves**, and nothing
> is drawn over the page again until it is asked for.

#### Scenario: Revealing controls
- **WHEN** a user taps the centre of the screen
- **THEN** exactly two controls fade in over the page — one that closes the publication and one that opens the reader's menu — and the page does not reflow
- **AND** they fade out again after 4 seconds of no interaction, or immediately on a second centre tap
- **AND** no title, page number, percentage or slider is drawn over the page, because each of those is a fact the menu states better and none of them is an action

#### Scenario: Everything else is in the menu, and labelled
- **WHEN** a user opens the reader's menu
- **THEN** it offers the table of contents, bookmarks, search within the publication, reading themes and reader settings, each named in words rather than by icon alone
- **AND** every control that was reachable from the reader before this change is reachable from here in one action

#### Scenario: Edge taps turn pages
- **WHEN** a user taps within the left or right edge zone
- **THEN** the page turns in the corresponding direction and chrome does not appear
- **AND** the edge zones are mirrored in right-to-left mode
- **AND** each zone is a third of the screen's width, and the middle third is what reveals the controls — see [`page-transitions`](../page-transitions/spec.md), which owns the gesture and the setting that turns it off

#### Scenario: Chrome does not obscure the page
- **WHEN** chrome is visible
- **THEN** it floats over the page on a translucent material and the page is not resized or shifted

#### Scenario: Fewer controls is not fewer ways in
- **WHEN** a user uses any gesture the reader supported before this change — edge tap, swipe, pinch, drag to zoom, or the mirrored equivalents in right-to-left mode
- **THEN** it behaves exactly as it did, because moving controls into a menu must not make the reader harder to drive
