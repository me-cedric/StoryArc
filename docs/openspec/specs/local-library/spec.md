# local-library Specification

## Purpose

Reading what is already on the device or in the user's own cloud storage,
without a server. On iOS that means security-scoped bookmarks into Files —
covering iCloud Drive, Dropbox, Nextcloud, and any other File Provider — and
files opened directly from another app. On Android it means the Storage Access
Framework and `ACTION_VIEW` intents. This is the source type that must work with
zero configuration.

## Requirements

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
- **THEN** the source is marked `unauthorized` with a plain-language explanation naming the folder
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
- **WHEN** StoryArc has opened a publication handed over by an `ACTION_VIEW` or `ACTION_SEND` intent
- **THEN** the publication is not kept, because the access that came with the intent ends with the process unless the sending app chose to make it persistable, and there is no way to ask for it afterwards
- **AND** the user keeps such a publication by importing it, which copies it into app storage

#### Scenario: File type registration
- **WHEN** the operating system lists apps that can open `.cbz`, `.cbr`, `.cb7`, `.cbt`, `.epub`, or `.pdf`
- **THEN** StoryArc appears as a handler for each of them

#### Scenario: Unsupported file
- **WHEN** a user opens a file StoryArc cannot read
- **THEN** the app names the format it detected and states which formats it supports, rather than reporting a generic failure

### Requirement: Imported copies

The app SHALL let a user import a publication into app-managed storage, so that
the copy survives the original being moved or deleted.

#### Scenario: Importing
- **WHEN** a user imports a file
- **THEN** it is copied into app storage, indexed, and listed under an "On this device" source
- **AND** the app reports the space used

#### Scenario: Deleting an imported copy
- **WHEN** a user deletes an imported publication
- **THEN** the app confirms, naming the title and the space to be freed, and states that the original file elsewhere is untouched

### Requirement: Watched changes

The app SHALL detect changes to a folder library without a full rescan.

#### Scenario: New file appears
- **WHEN** a file is added to a watched folder while the app is in the foreground
- **THEN** it appears in the library within 10 seconds without a manual refresh

#### Scenario: Change detected while backgrounded
- **WHEN** the app returns to the foreground after files changed
- **THEN** it reconciles by comparing file modification times and sizes rather than re-reading every archive
