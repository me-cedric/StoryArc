# kavita-server Specification

## Purpose

First-class integration with a Kavita server. Kavita already speaks OPDS, but
OPDS cannot express collections, reading lists, per-page progress, or the "want
to read" state. This capability uses Kavita's own API so that StoryArc is a
genuine Kavita client rather than a catalogue browser pointed at one.

## Requirements

### Requirement: Kavita connection

The app SHALL connect to a Kavita server using its base URL and a user API key,
and SHALL manage session tokens without exposing them to the user.

#### Scenario: Adding a server
- **WHEN** a user enters a Kavita base URL and API key
- **THEN** the app authenticates, confirms the server version and the account name, and saves the source
- **AND** rejects a server whose version is older than the minimum StoryArc supports, naming the required version

#### Scenario: Pasting a full OPDS URL
- **WHEN** a user pastes a Kavita OPDS URL that embeds the API key
- **THEN** the app extracts the base URL and key and configures a native Kavita source rather than a generic OPDS source

#### Scenario: Session token expires
- **WHEN** a request fails because the session token has expired
- **THEN** the app re-authenticates with the stored API key and retries the request once, without the user seeing an error

#### Scenario: API key revoked
- **WHEN** re-authentication fails because the API key is no longer valid
- **THEN** the source is marked `unauthorized` with an explanation and an action to enter a new key

### Requirement: Library structure

The app SHALL mirror Kavita's own structure — libraries, series, volumes, and
chapters — rather than flattening it.

#### Scenario: Browsing a Kavita source
- **WHEN** a user opens a Kavita source
- **THEN** the app lists that server's libraries, and entering one lists its series with cover, title, and progress

#### Scenario: Series with volumes and loose chapters
- **WHEN** a series contains both volumes and chapters not belonging to a volume
- **THEN** the detail screen lists volumes and loose chapters in Kavita's own order, clearly distinguishing the two

#### Scenario: Continue point
- **WHEN** a user opens a series they have partially read
- **THEN** the screen's primary action is "Continue" pointing at the exact chapter and page Kavita reports as next

### Requirement: Metadata

The app SHALL display the metadata Kavita holds — summary, genres, tags, people,
publication status, age rating, and release year — and SHALL prefer it over
metadata embedded in the file.

#### Scenario: Server metadata differs from file metadata
- **WHEN** a publication's `ComicInfo.xml` disagrees with Kavita's metadata
- **THEN** the app displays Kavita's values, because the server is the curated source

#### Scenario: Reading a downloaded Kavita title offline
- **WHEN** a downloaded Kavita publication is opened with the server unreachable
- **THEN** the cached server metadata is displayed, not the file's embedded metadata

### Requirement: Server-side collections and reading lists

The app SHALL read, create, and modify Kavita collections and reading lists, and
SHALL treat them as the same kind of object as locally created ones.

#### Scenario: Viewing server collections
- **WHEN** a user browses collections
- **THEN** Kavita's collections appear alongside local ones, each labelled with the source it belongs to

#### Scenario: Adding to a server reading list
- **WHEN** a user adds a publication to a Kavita reading list
- **THEN** the change is sent to the server and reflected for other Kavita clients
- **AND** if the server is unreachable, the change is queued and applied on reconnection

#### Scenario: Mixing sources in one list
- **WHEN** a user tries to add a publication from a different source to a Kavita reading list
- **THEN** the app explains that a server list can only contain that server's publications, and offers to create a local list instead

### Requirement: Progress synchronisation

The app SHALL synchronise reading progress with Kavita in both directions. The
detailed conflict rules are in [`reading-progress`](../reading-progress/spec.md).

#### Scenario: Progress pushed
- **WHEN** a user reads a Kavita publication and leaves the reader
- **THEN** the page position is sent to the server, and retried on the next successful connection if it fails

#### Scenario: Progress pulled
- **WHEN** a Kavita source refreshes
- **THEN** progress recorded on other devices is reflected in the library

#### Scenario: Marking read state
- **WHEN** a user marks a publication read or unread
- **THEN** the state is sent to Kavita and reflected in that server's own UI

### Requirement: Server-side search

The app SHALL use Kavita's search when searching within a Kavita source.

#### Scenario: Searching a Kavita source
- **WHEN** a user searches within a Kavita source
- **THEN** the query is sent to the server, returning matches across series, chapters, people, genres, and tags — not only titles cached locally

#### Scenario: Searching while the server is unreachable
- **WHEN** the server is unreachable
- **THEN** the search falls back to the local cache and states that results are limited to cached content
