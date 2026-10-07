## Purpose

How a reader takes their library off one device and puts it on another, across platforms and
across versions, in a document they can read and a future version of the app can still open.

## ADDED Requirements

### Requirement: One versioned document

The app SHALL export the reader's library as a single JSON document that declares its format
version, and SHALL be able to read every version it has ever written.

#### Scenario: What the document declares
- **WHEN** an export is written
- **THEN** it declares a format version, the app version and the platform that wrote it, and the moment it was written
- **AND** the body is readable JSON, so a reader can open it and a later version can diff it

#### Scenario: An older document is migrated forward
- **WHEN** a document declaring an older format version is imported
- **THEN** it is migrated through each transform in order, and imported

#### Scenario: A newer document is refused, by name
- **WHEN** a document declaring a newer format version than this app knows is imported
- **THEN** the app refuses it, names the version it found and the newest it understands, and changes nothing
- **AND** it does not import the parts it happens to recognise, because a partial import of an unknown document changes data silently

#### Scenario: A field this version does not know
- **WHEN** a document of a known version carries a field this build does not know
- **THEN** the field is ignored and the rest is imported, and a re-export does not have to carry it back

#### Scenario: A record this version cannot read
- **WHEN** a position record carries a kind this version does not know, or lacks a field its kind needs
- **THEN** that record alone is dropped and the rest is imported
- **AND** the preview counts only the records the import will keep
- **AND** a document written by a platform this version has never heard of is read like any other, because the platform name decides nothing

#### Scenario: A document that is too large
- **WHEN** a document larger than 64 MiB is imported
- **THEN** the app refuses it by name, before it parses a byte, and changes nothing

### Requirement: What an export carries

The app SHALL export every durable store that describes the reader's own choices, and SHALL
name what it leaves out.

#### Scenario: The library's shape
- **WHEN** an export is written
- **THEN** it carries the sources and servers, the collections and reading lists, the pinned shelves, the settings, the reading themes, the per-publication reader settings, the reading progress, and the covers the reader chose

#### Scenario: What it does not carry
- **WHEN** an export is written
- **THEN** it carries no publication files, no downloaded copies and no cover cache, because those are recreated from the sources it does carry
- **AND** the app states this, so a reader does not take an export as a backup of their books

#### Scenario: The two platforms write one shape
- **WHEN** an export written on one platform is imported on the other
- **THEN** every record is understood, including the records whose stores disagree on the wire today: the source timestamp, the source kind, the shelf cover key, the reading position and the pinned-shelf container
- **AND** the document's own shape is the agreed one, and each platform converts at its own boundary

#### Scenario: A chosen cover travels
- **WHEN** an export is written and the reader has chosen covers
- **THEN** each one is carried in a `covers` list as its override key and its image in base64, sorted by key
- **AND** an import keeps a cover this device already holds, and drops one with bad base64, an empty image, or an image over 8 MB

### Requirement: Secrets travel only sealed, and only when asked

The app SHALL NOT write a source secret into an export unless the reader chooses to carry
secrets and gives a passphrase. A secret that travels SHALL be sealed with AES-256-GCM under a
key derived from that passphrase with PBKDF2-HMAC-SHA256, and the document SHALL carry every
parameter: the KDF and cipher names, the iteration count, the salt and each nonce. The app SHALL
make a re-import possible without the passphrase.

#### Scenario: A server in the export
- **WHEN** a source with a password, a token or an API key is exported, and the reader did not choose to carry secrets
- **THEN** its address, its name, its username and its settings travel, and its secret does not

#### Scenario: Carrying secrets under a passphrase
- **WHEN** the reader chooses to carry secrets, and gives a passphrase twice that matches
- **THEN** each secret is written only as ciphertext in the document's `secrets` object, keyed by its source
- **AND** the iteration count is at least 600,000, and the passphrase itself is written nowhere

#### Scenario: Importing sealed secrets
- **WHEN** a document with sealed secrets is imported, and the reader gives the right passphrase
- **THEN** each secret goes straight to the platform secure store, and its source reaches its server with no sign-in

#### Scenario: A wrong or missing passphrase
- **WHEN** the reader gives a wrong passphrase, or chooses to import without one
- **THEN** the app states that the secrets could not be opened, imports everything else, and marks each such source as needing a sign-in

#### Scenario: One document, both platforms
- **WHEN** a document sealed on one platform is imported on the other with the right passphrase
- **THEN** every secret opens

#### Scenario: Signing in again after an import
- **WHEN** an imported source needs a secret to reach its server
- **THEN** the source is listed, marked as needing a sign-in, and reaching it asks for the secret once
- **AND** the library it already carried stays browsable, because an unreachable source is a normal state

#### Scenario: A certificate pin
- **WHEN** an export carries a source that had a pinned certificate
- **THEN** the pin travels, and importing it does not silently change what the app trusts: the reader is told which source gained a pin and from where

### Requirement: Import merges

The app SHALL merge an import into what the device already holds, record by record, and SHALL
NOT replace the device's library wholesale.

#### Scenario: Reading progress on both sides
- **WHEN** a publication has a position on the device and a different position in the document
- **THEN** the two are merged by the rule the app already uses for a server disagreement: the furthest position wins, and finished stays finished

#### Scenario: A device that never synced
- **WHEN** reading progress is merged on a device that has never synchronised with any server, so it holds no watermark
- **THEN** the merge still decides correctly, and does not treat an absent watermark as proof that the local side moved

#### Scenario: A collection that exists on both sides
- **WHEN** a collection or reading list in the document has the same identity as one on the device
- **THEN** their members are merged rather than one replacing the other, and the reader is told how many were added

#### Scenario: The reader sees what will happen first
- **WHEN** an import is about to run
- **THEN** the app states what it will add, what it will merge, and what it will ask for a sign-in, before anything changes
