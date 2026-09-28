## MODIFIED Requirements

### Requirement: Folder libraries

The app SHALL let a user designate one or more folders as libraries and SHALL
retain access to them across launches, reboots, and app updates.

#### Scenario: Adding a folder on iOS
- **WHEN** a user picks a folder through the document picker
- **THEN** the app stores a security-scoped bookmark and can re-open the folder after a device restart without asking again

#### Scenario: Adding a folder on Android
- **WHEN** a user picks a folder through the Storage Access Framework
- **THEN** the app takes a persistable URI permission and can re-open the folder after a reboot without asking again

#### Scenario: Access is revoked
- **WHEN** a stored folder permission is no longer valid — the folder was deleted, the provider was removed, or the user revoked access
- **THEN** the source is marked `unreachable`, matching every other source the reader cannot currently reach, with a plain-language explanation naming the folder and the access that was lost
- **AND** a single action re-picks the folder, preserving reading progress for everything inside it

#### Scenario: Scanning a folder
- **WHEN** a folder library is added or refreshed
- **THEN** the app walks it recursively, identifies supported publications, extracts covers and metadata, and reports progress as a count of items found
- **AND** the scan is cancellable and resumable, and does not block browsing what it has already found

#### Scenario: Nested folder structure becomes series
- **WHEN** a scanned folder contains subfolders each holding multiple publications
- **THEN** each subfolder is presented as a series whose name is the folder name, ordered by the volume or chapter number parsed from each filename
- **AND** a subfolder whose contents cannot be ordered falls back to case-insensitive natural filename order

#### Scenario: Large library
- **WHEN** a folder library contains 10,000 or more publications
- **THEN** the first screen of covers appears within 3 seconds of the scan starting
- **AND** scrolling remains at the display's refresh rate while the scan continues

### Requirement: Opening a single file

The app SHALL open a supported publication handed to it by the system without
requiring the user to configure a source first.

#### Scenario: Open-in from another app
- **WHEN** a user chooses StoryArc from a share sheet, an "Open with" intent, or a file manager
- **THEN** the publication opens directly in the reader
- **AND** the app keeps it, once and unobtrusively, wherever the system's own hand-over grant outlives the app being closed

#### Scenario: Remembering an opened file on iOS
- **WHEN** StoryArc has opened a publication another app handed over
- **THEN** it stores a security-scoped bookmark to that file, and the next launch lists it as a single publication rather than as a folder library
- **AND** the publication belongs to no source, because there is nothing here for the user to rename, reconnect, refresh or remove
- **AND** at most the twenty most recently opened files are kept, and one that has since been moved or deleted is forgotten without being reported as an unavailable folder

#### Scenario: Remembering an opened file on Android
- **WHEN** StoryArc has opened a publication handed over by an `ACTION_VIEW` or `ACTION_SEND` intent, and the sending app granted a persistable URI permission with it
- **THEN** the app takes that permission and the next launch lists the publication as a single publication rather than as a folder library, the same as iOS, at most the twenty most recently opened
- **AND** when the sending app granted no persistable permission, the publication is not kept, because the access ends with the process and there is no way to ask for it afterwards
- **AND** either way, the user keeps such a publication for certain by importing it, which copies it into app storage

#### Scenario: File type registration
- **WHEN** the operating system lists apps that can open `.cbz`, `.cbr`, `.cb7`, `.cbt`, `.epub`, or `.pdf`
- **THEN** StoryArc appears as a handler for each of them

#### Scenario: Unsupported file
- **WHEN** a user opens a file StoryArc cannot read
- **THEN** the app names the format it detected and states which formats it supports, rather than reporting a generic failure
