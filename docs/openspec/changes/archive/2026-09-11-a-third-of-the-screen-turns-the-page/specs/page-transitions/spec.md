## MODIFIED Requirements

### Requirement: Turn triggers

A page SHALL turn from any input the platform offers, in every mode.

#### Scenario: Tap zones
- **WHEN** a user taps within the leading or trailing edge zone
- **THEN** the page turns in that direction with the current transition, and reader chrome does not appear
- **AND** each zone is a third of the screen's width, leaving the middle third to the chrome
- **AND** this holds in every transition mode, the animated ones included

#### Scenario: Turning the tap zones off
- **WHEN** a reader turns the tap zones off in settings
- **THEN** a tap anywhere toggles the chrome, and no tap turns a page
- **AND** every other trigger still turns pages — swipe, keyboard, controller, and the volume buttons where those are enabled

#### Scenario: The tap zones are on until a reader says otherwise
- **WHEN** a reader has never chosen either way
- **THEN** the tap zones are on, because tapping the side of the page is how most readers turn one

#### Scenario: Hardware input
- **WHEN** a keyboard, an external controller, or the volume buttons where enabled in settings are used
- **THEN** the page turns with the current transition applied
- **AND** where the platform does not let an app observe the volume buttons, no such setting is offered and the reason is stated once, rather than a switch being shown that does nothing

#### Scenario: Turning at a boundary
- **WHEN** a user attempts to turn past the first or last page
- **THEN** the page resists with a bounded rubber-band and returns, rather than completing a turn to nothing
