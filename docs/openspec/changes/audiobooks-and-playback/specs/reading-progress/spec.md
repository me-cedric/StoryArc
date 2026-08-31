## MODIFIED Requirements

### Requirement: Progress across formats and sources

The app SHALL translate progress meaningfully rather than dropping it.

Progress SHALL be recorded in whatever unit the publication is read in, and SHALL
mean the same thing to the reader whichever that is.

#### Scenario: Same publication from two sources
- **WHEN** a user reads a publication from a local folder and later opens the same publication from a server
- **THEN** the local progress applies, resolved through content identity

#### Scenario: Reflowable position
- **WHEN** progress is stored for a reflowable publication
- **THEN** it is stored as a position within the content, not as a page number, so it survives a typography change or a different device

#### Scenario: An audiobook's position is a time
- **WHEN** progress is stored for an audiobook
- **THEN** it is an offset in time within a named part, and a percentage is derived from the total duration
- **AND** it survives the app being closed, the device restarting, and the file being re-downloaded, exactly as a page index does
- **AND** it is resolved through content identity like every other position, so the same audiobook from a folder and from a share is one publication

#### Scenario: A publication that is both listened to and read
- **WHEN** a reflowable publication has been read aloud and then read silently, or the reverse
- **THEN** there is one position, and it is wherever the reader last was by either means, because it is one publication
- **AND** the app does not keep a separate listening position, so returning never offers a choice of two places

#### Scenario: Finishing by listening
- **WHEN** a listener reaches the end of an audiobook, or the voice reaches the end of a publication read aloud
- **THEN** the publication is marked finished by the same rule that marks a comic finished on its last page
- **AND** the same end-of-publication offers apply — the next in the series, and deleting the download if that setting is on
