## MODIFIED Requirements

### Requirement: The curl

The curl SHALL be driven by the finger, not by a timeline, and SHALL turn in
both directions.

#### Scenario: The page follows the finger
- **WHEN** a user drags across the page in curl mode
- **THEN** the page deforms and lifts in real time under the finger, at the display's refresh rate including 120 Hz
- **AND** the lifted page casts a shadow on the page beneath, and its leading edge catches light

#### Scenario: The sheet rolls rather than folds
- **WHEN** the page is part-way through a turn
- **THEN** the lifted sheet is curved, not creased: its leading edge is a curve across the page rather than a straight line
- **AND** the back of the sheet is visible as a band whose width grows as the sheet lifts, dimmed because paper is not transparent
- **AND** the shadow cast on the page beneath follows that curve rather than a straight edge

#### Scenario: Turning back
- **WHEN** a user drags towards the page they came from
- **THEN** the previous page lifts in from the opposite edge and lays down over the current one, following the finger in the same way a forward turn does
- **AND** the release rule is the same — past halfway the turn completes, before it the page springs back, and a flick completes the turn regardless of distance

#### Scenario: Turning back from the first page
- **WHEN** a user drags backwards on the first page of a publication, or forwards on the last
- **THEN** nothing lifts and the page stays where it is, rather than turning to an empty sheet

#### Scenario: Release behaviour
- **WHEN** a user releases the drag
- **THEN** past the halfway point the turn completes, before it the page springs back, and a flick completes the turn regardless of distance

#### Scenario: The curl is interruptible
- **WHEN** a user starts a new drag while a curl is still settling
- **THEN** the new gesture takes over from the current position without the page snapping
- **AND** a new drag in the opposite direction unwinds the settling turn rather than starting a second one

#### Scenario: Curl direction respects reading direction
- **WHEN** the publication reads right-to-left
- **THEN** the curl originates from the opposite edge and the gesture is mirrored
- **AND** the backwards turn is mirrored with it

#### Scenario: Curl is not offered where it cannot be honest
- **WHEN** the device lacks the platform capability the curl needs, or cannot render it at the display's refresh rate
- **THEN** Curl is absent from the picker on that device and Slide is the default, with the reason stated once in plain language — naming the requirement, not an API level
- **AND** the app never ships a curl that stutters in preference to a slide that does not

#### Scenario: Every other mode stays available
- **WHEN** Curl is absent on a device
- **THEN** Slide, Fast fade and Scroll are fully available, and no other reader behaviour differs
- **AND** a user who set Curl on a capable device and later opens the library on this one reads with Slide without their stored preference being overwritten
