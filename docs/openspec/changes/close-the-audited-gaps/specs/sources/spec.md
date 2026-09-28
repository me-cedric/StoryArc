## ADDED Requirements

### Requirement: Reading all of a source

The app SHALL keep reading a source past its first slice, in the background, until
the library holds every publication the source offers, and SHALL state its progress
while it reads.

#### Scenario: A large server arrives in full
- **WHEN** a reader adds or refreshes a source that holds more publications than the first slice the app reads
- **THEN** the first slice appears as soon as it is read, newest first, so the library is usable at once
- **AND** the app keeps reading the rest of the source, page by page, and merges each page into the library as it arrives
- **AND** when the read completes, the library holds every publication the source offers, and the source no longer reads as holding more than the library

#### Scenario: Progress while the rest arrives
- **WHEN** the app is still reading the rest of a source
- **THEN** the source's detail screen states how much it has read and how much the source holds, for example "120 of 215 series"
- **AND** the library does not present the count it has as the whole

#### Scenario: The source goes away mid-read
- **WHEN** a source becomes unreachable while the app reads the rest of it
- **THEN** the publications already read stay in the library, grey as offline rows are
- **AND** the read continues from where it stopped when the source is reachable again, without starting over
