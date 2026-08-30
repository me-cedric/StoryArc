# page-transitions Specification

## Purpose

How a page becomes the next page. Four modes, shared by both readers, because a
transition is a property of the container rather than of the content — the same
curl serves a comic page and an EPUB page.

This capability exists separately because the curl is the one interaction in
StoryArc that no library provides. Readium exposes every typographic preference
and no transition preference at all, so slide, curl and fade are StoryArc's own
code on both platforms, and their cost needs stating rather than discovering.

## Requirements

### Requirement: Transition modes

The app SHALL offer exactly these page-transition modes, selectable per
publication and remembered per series.

| Mode | Behaviour |
| --- | --- |
| **Curl** | Interactive page turn that follows the finger, with a lit leading edge and a shadow cast on the page beneath |
| **Slide** | Paged translation along the reading axis |
| **Fast fade** | Short cross-dissolve, no translation |
| **Scroll** | Continuous scrolling, no discrete turn |

#### Scenario: Choosing a mode
- **WHEN** a user picks a transition mode
- **THEN** it applies to the current publication immediately without losing the reading position, and is remembered for the series

#### Scenario: Scroll axis
- **WHEN** a user selects Scroll
- **THEN** the axis follows the publication's reading direction — vertical for webtoons and reflowable text, horizontal where the publication declares it
- **AND** the axis is separately overridable

#### Scenario: A mode is unavailable for the content
- **WHEN** a mode cannot apply to the open publication
- **THEN** it is shown unavailable with a one-line reason, never silently absent

### Requirement: The curl

The curl SHALL be driven by the finger, not by a timeline.

#### Scenario: The page follows the finger
- **WHEN** a user drags across the page in curl mode
- **THEN** the page deforms and lifts in real time under the finger, at the display's refresh rate including 120 Hz
- **AND** the lifted page casts a shadow on the page beneath, and its leading edge catches light

#### Scenario: Release behaviour
- **WHEN** a user releases the drag
- **THEN** past the halfway point the turn completes, before it the page springs back, and a flick completes the turn regardless of distance

#### Scenario: The curl is interruptible
- **WHEN** a user starts a new drag while a curl is still settling
- **THEN** the new gesture takes over from the current position without the page snapping

#### Scenario: Curl direction respects reading direction
- **WHEN** the publication reads right-to-left
- **THEN** the curl originates from the opposite edge and the gesture is mirrored

#### Scenario: Curl is not offered where it cannot be honest
- **WHEN** the device lacks the platform capability the curl needs, or cannot render it at the display's refresh rate
- **THEN** Curl is absent from the picker on that device and Slide is the default, with the reason stated once in plain language — naming the requirement, not an API level
- **AND** the app never ships a curl that stutters in preference to a slide that does not

#### Scenario: Every other mode stays available
- **WHEN** Curl is absent on a device
- **THEN** Slide, Fast fade and Scroll are fully available, and no other reader behaviour differs
- **AND** a user who set Curl on a capable device and later opens the library on this one reads with Slide without their stored preference being overwritten

### Requirement: Reduced motion

Motion settings SHALL be honoured without hiding what was disabled.

#### Scenario: Reduce Motion is on
- **WHEN** the system Reduce Motion setting is enabled
- **THEN** Curl and Slide are replaced by Fast fade
- **AND** the picker still lists them, marked unavailable, with the reason named — a control that vanishes teaches the user nothing

#### Scenario: Reduce Motion turned off mid-session
- **WHEN** a user disables Reduce Motion while the reader is open
- **THEN** the previously chosen mode is restored without the reader being reopened

### Requirement: Turn triggers

A page SHALL turn from any input the platform offers, in every mode.

#### Scenario: Tap zones
- **WHEN** a user taps within the leading or trailing edge zone
- **THEN** the page turns in that direction with the current transition, and reader chrome does not appear

#### Scenario: Hardware input
- **WHEN** a keyboard, an external controller, or the volume buttons where enabled in settings are used
- **THEN** the page turns with the current transition applied
- **AND** where the platform does not let an app observe the volume buttons, no such setting is offered and the reason is stated once, rather than a switch being shown that does nothing

#### Scenario: Turning at a boundary
- **WHEN** a user attempts to turn past the first or last page
- **THEN** the page resists with a bounded rubber-band and returns, rather than completing a turn to nothing

### Requirement: Transition performance

A transition SHALL never be the reason a turn feels slow.

#### Scenario: The next page is not ready
- **WHEN** a turn begins and the destination page has not finished decoding
- **THEN** the transition runs against a placeholder holding the correct aspect ratio, so the turn does not jump when the content arrives

#### Scenario: Frame budget
- **WHEN** any transition is running
- **THEN** it holds the display's refresh rate, and a dropped frame during a turn is treated as a defect rather than as acceptable variance

#### Scenario: Memory during a curl
- **WHEN** a curl is running
- **THEN** at most the outgoing and incoming page rasters are held, and prefetch depth shrinks under memory pressure rather than the app being terminated
