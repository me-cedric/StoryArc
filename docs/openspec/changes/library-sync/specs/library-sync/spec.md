## Purpose

How two devices belonging to one reader stay in step, without an account, without a service,
and without claiming more than each platform can honestly deliver.

## ADDED Requirements

### Requirement: The sync document lives where the reader chose

The app SHALL keep its sync document in a location the reader configured, and SHALL NOT send
the reader's data anywhere else.

#### Scenario: Choosing where it lives
- **WHEN** a reader turns sync on
- **THEN** they choose a network share they have already added, or a folder through the system picker
- **AND** the app states that every device they want in step must be able to reach that same place

#### Scenario: A folder that is really a cloud drive
- **WHEN** the folder the reader picked is provided by iCloud Drive, Google Drive, Dropbox or another file provider
- **THEN** the app writes to it as it would to any folder, and holds no account with that provider

#### Scenario: Sync is off until it is turned on
- **WHEN** a reader has never turned sync on
- **THEN** no sync document is written, read or looked for, and nothing leaves the device

#### Scenario: The place is unreachable
- **WHEN** the share is offline, the folder has been removed, or the provider refuses
- **THEN** the app keeps the reader's library working, shows the source as unreachable rather than as an error, and syncs when it can reach it again

### Requirement: When a sync happens

The app SHALL synchronise at moments it can honestly guarantee, and SHALL describe what it does
in terms of those moments rather than as continuous.

#### Scenario: The reader opens the app
- **WHEN** the app comes to the foreground and sync is on
- **THEN** it reads the document, merges, and writes back anything this device changed

#### Scenario: The reader closes a publication
- **WHEN** a reader leaves a publication they were reading
- **THEN** that position is written, because it is the position they will look for on the other device

#### Scenario: In the background, as far as each platform allows
- **WHEN** the app is in the background
- **THEN** it synchronises opportunistically within what the platform grants, and the app does not promise an interval it cannot keep
- **AND** the setting says what each platform actually does, rather than one sentence that is true on neither

### Requirement: Two devices that both moved

The app SHALL reconcile a record that changed in two places, by the rule it already uses for a
disagreement with a server.

#### Scenario: A position on two devices
- **WHEN** the same publication has a different position in the document and on this device
- **THEN** the furthest position wins, and a publication marked finished stays finished

#### Scenario: The watermark that decides it
- **WHEN** a position is synchronised, in either direction
- **THEN** the watermark that records what was last synchronised is written
- **AND** a conflict notice is shown only when the two sides really did diverge, which requires that watermark to be true

#### Scenario: A shelf changed on both sides
- **WHEN** a collection or a reading list gained members on two devices
- **THEN** the members are merged rather than one side replacing the other

#### Scenario: A deletion is not a disagreement
- **WHEN** a reader deleted a collection on one device and did not touch it on the other
- **THEN** the deletion travels, and a record the reader removed does not return at the next sync

#### Scenario: Two devices write at once
- **WHEN** two devices write the document at nearly the same moment
- **THEN** neither loses the other's records: a write is not a blind overwrite of the whole document

### Requirement: Kavita keeps what Kavita owns

The app SHALL leave a record Kavita already synchronises to Kavita, and SHALL carry in the
document only what Kavita cannot hold.

#### Scenario: A Kavita publication's position
- **WHEN** a publication comes from a Kavita server and its position changes
- **THEN** that position goes to the server, as it does today, and the document does not carry a second copy to disagree with it

#### Scenario: Everything Kavita cannot hold
- **WHEN** the record belongs to a local file, a network share or an OPDS catalogue
- **THEN** the document carries it, because every Kavita record is keyed to a Kavita series or chapter and there is nothing there to key it to
