# network-share Specification

## Purpose

Reading directly from an SMB share — the way most people's NAS actually exposes
a comics folder. The hard part is not listing files; it is behaving correctly
when the network drops mid-page, the device sleeps, or the user walks out of
Wi-Fi range. This capability owns that.

## Requirements

### Requirement: SMB connection

The app SHALL connect to SMB 2 and SMB 3 shares using a host, share name,
optional path, and either guest access or username and password.

#### Scenario: Adding a share
- **WHEN** a user enters a host, share, and credentials
- **THEN** the app validates the connection before saving and reports success or the specific failure — host unreachable, share not found, authentication rejected, or protocol unsupported

#### Scenario: Browsing to a subfolder
- **WHEN** a user adds a share without knowing the folder path
- **THEN** the app lets them browse the share's directory tree and pick the folder to use as the library root

#### Scenario: SMB 1 only server
- **WHEN** a server offers only SMB 1
- **THEN** the app refuses to connect and explains that SMB 1 is disabled for security reasons, naming the setting to enable SMB 2 or later on the server

#### Scenario: Encrypted transport
- **WHEN** the server supports SMB 3 encryption
- **THEN** the app negotiates it
- **AND** the source detail screen states whether the connection is encrypted

### Requirement: Disconnect and reconnect

The app SHALL survive network interruption without losing the user's place and
SHALL NOT present a modal error for a transient drop.

#### Scenario: Connection drops while reading
- **WHEN** the share becomes unreachable while a user is reading a publication streamed from it
- **THEN** already-buffered pages remain readable
- **AND** the app reconnects in the background and resumes streaming at the current page
- **AND** an inline, dismissible indicator appears only if a page is actually blocked on the network for more than 2 seconds

#### Scenario: Device sleeps and wakes
- **WHEN** the device sleeps with an open SMB session and later wakes
- **THEN** the app re-establishes the session transparently on the next read

#### Scenario: Network changes
- **WHEN** the device moves between Wi-Fi networks or from Wi-Fi to cellular
- **THEN** the app tears down the stale session and re-establishes it if the share is reachable on the new network
- **AND** marks the source `unreachable` rather than retrying indefinitely if it is not

#### Scenario: Reconnection fails repeatedly
- **WHEN** reconnection has failed for longer than 60 seconds while the reader is open
- **THEN** the app offers to download the current publication for offline reading if it is not already downloaded, and to return to the library

### Requirement: Streaming reads

The app SHALL read only the parts of a remote archive it needs, rather than
downloading whole files to display one page.

#### Scenario: Opening a large archive
- **WHEN** a user opens a 400 MB CBZ on a share
- **THEN** the first page renders without transferring the whole archive
- **AND** subsequent pages are prefetched ahead of the reading position

#### Scenario: Metered connection
- **WHEN** the device is on a metered connection
- **THEN** the app respects the platform's data-saver setting and, when it is active, requires explicit confirmation before streaming or downloading

### Requirement: Discovery

The app SHOULD offer to discover SMB hosts on the local network to reduce manual entry.

#### Scenario: Discovering hosts
- **WHEN** a user adds an SMB source
- **THEN** the app lists hosts advertising SMB on the local network, if the platform permits it, alongside a manual-entry field
- **AND** manual entry is always available and never gated behind discovery

#### Scenario: Local network permission denied
- **WHEN** the platform's local-network permission is denied
- **THEN** discovery is hidden, manual entry still works, and the app explains once how to enable discovery in system settings
