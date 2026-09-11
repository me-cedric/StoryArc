## MODIFIED Requirements

### Requirement: About

The app SHALL include an About screen identifying the author and stating that
the app is free.

The screen SHALL name the author by the handle `@me-cedric`, and that byline SHALL be the
control that opens the author's profile. The screen SHALL NOT carry a second control to the
same address.

#### Scenario: About contents
- **WHEN** a user opens About
- **THEN** the screen shows the app version and build, the byline "By @me-cedric", a link to the StoryArc repository, and the licence
- **AND** the byline opens <https://github.com/me-cedric>
- **AND** no other row on the screen opens that address

#### Scenario: Support link
- **WHEN** a user opens About
- **THEN** it states that StoryArc is completely free and open source with no paid tier and no advertising, and offers an optional link to <https://ko-fi.com/mecedric>
- **AND** the support link is never presented as a prompt, an interstitial, or a nag — it appears only on this screen

#### Scenario: Acknowledgements
- **WHEN** a user opens acknowledgements
- **THEN** every third-party library is listed with its licence text

#### Scenario: Reporting a problem
- **WHEN** a user chooses to report a problem
- **THEN** the app opens the repository's issue tracker with the app version, platform version, and device class pre-filled, and no personal data
