# release-train Specification

## Purpose
Defines how one version of StoryArc reaches the readers on Android, iOS, macOS, Windows and Linux: one version and
one tag for all clients, the downloads that a release carries, a rehearsal that publishes nothing, and the steps
that only the owner takes.

## Requirements

### Requirement: One version for every client

Each release SHALL have one version `X.Y.Z` and one build number. Every client of that release SHALL show the same
version on its About screen. The build number SHALL only go up, and a release that failed SHALL never give its
number to a later release.

#### Scenario: Two devices on the same release
- **WHEN** a reader installs release 0.3.0 on an Android phone and on a Windows PC
- **THEN** both About screens show version 0.3.0

#### Scenario: A client disagrees with the others
- **WHEN** the version of one client in the repository is different from the version of the other clients
- **THEN** the release command stops before it makes a commit or a tag, and names the file that disagrees
- **AND** the repository check fails with the same message until the versions agree

#### Scenario: A release that failed
- **WHEN** the release with build number 7 fails
- **THEN** the next release uses build number 8

### Requirement: One tag builds every download

One release command SHALL make one `vX.Y.Z` tag. That tag SHALL build the downloads of Android, Windows, macOS and
Linux, and attach them to one GitHub release. The builds SHALL be independent: a build that fails SHALL NOT stop
another build.

| Platform | Downloads, named with the version |
| --- | --- |
| Android | a signed APK |
| Windows | an installer and a portable zip, for x64 and for ARM64 |
| macOS | a disk image |
| Linux | a Flatpak bundle, for x86_64 and for aarch64 |

#### Scenario: All builds succeed
- **WHEN** the owner releases 0.3.0
- **THEN** one tag `v0.3.0` exists, and its GitHub release carries every download in the table

#### Scenario: One build fails
- **WHEN** the Windows build of 0.3.0 fails
- **THEN** the Android, macOS and Linux downloads are still attached
- **AND** the release text names Windows as missing
- **AND** the owner fixes the cause and releases 0.3.1; the tag `v0.3.0` is not moved or made again

### Requirement: Nothing reaches a reader without the owner

A tag SHALL make the GitHub release as a draft, and SHALL upload the Android build to Play internal testing as a
draft. Only the owner SHALL publish the GitHub release, and roll out or promote the Play build. An automatic Play
roll-out SHALL happen only in a manual run where the owner asks for it.

#### Scenario: After the tag
- **WHEN** the lanes of 0.3.0 complete
- **THEN** the GitHub release `v0.3.0` is a draft that only the repository's maintainers can see
- **AND** Play internal testing holds 0.3.0 as a draft, and no tester receives it

#### Scenario: Play refuses the upload
- **WHEN** Play refuses the bundle, for example because it already has that build number
- **THEN** the Android lane fails with Play's message, and the APK is still attached to the draft release

### Requirement: The desktop downloads install and run

Each desktop download SHALL install or start without an extra tool. The Windows installer SHALL install for the
current user without administrator rights, and SHALL add a Start menu entry and an uninstaller. The portable Windows
copy SHALL keep its data in a folder beside itself, and SHALL leave nothing in the user profile. The macOS disk image
SHALL open a window that shows the app, the Applications folder and an arrow between them.

#### Scenario: Windows installer
- **WHEN** a reader runs the Windows installer
- **THEN** StoryArc is in the Start menu and in Installed apps, and it starts
- **AND** uninstalling it removes the app

#### Scenario: Windows portable copy
- **WHEN** a reader unzips the portable copy onto a USB stick and starts it
- **THEN** its library, settings and downloads are in a `data` folder beside the executable

#### Scenario: An unsigned download
- **WHEN** Windows SmartScreen or macOS Gatekeeper stops the first start, because the download has no paid signature
- **THEN** the release text tells the reader the steps to open it anyway

#### Scenario: macOS disk image
- **WHEN** a reader opens the disk image
- **THEN** a window shows the StoryArc app, the Applications folder and an arrow, on the StoryArc background

#### Scenario: Linux bundle
- **WHEN** a reader runs `flatpak install --user` on the bundle
- **THEN** Flatpak gets the GNOME runtime from Flathub, and StoryArc starts from the application menu

### Requirement: Reader's notes for phones and for desktops

Each release SHALL have one set of reader's notes in the four listing languages. A line SHALL apply to every
platform, to phones and tablets only, or to desktops only. Play SHALL show the lines for every platform and the
lines for phones and tablets. The GitHub release SHALL show all lines in English, under one heading for each group
that has lines.

#### Scenario: A desktop-only line
- **WHEN** a release has a line for desktops only
- **THEN** the GitHub release shows it under the desktop heading
- **AND** Play does not show it

#### Scenario: Notes are missing a language
- **WHEN** the notes of the version are missing in one of the four languages
- **THEN** the release command stops before it makes a commit or a tag, and names the missing language

### Requirement: A rehearsal publishes nothing

A rehearsal SHALL build every download and the release text from the current commit, and SHALL keep them as one
workflow artefact. It SHALL NOT make a tag, a GitHub release or a Play upload. It SHALL run when a push changes the
release machinery, and when a maintainer starts it by hand.

#### Scenario: A change to a release lane
- **WHEN** a push changes a release workflow or the release script
- **THEN** a rehearsal runs, and its artefact holds every download and the release text

#### Scenario: A rehearsal fails
- **WHEN** one build of a rehearsal fails
- **THEN** the other downloads are still in the artefact, and no release, tag or upload exists

### Requirement: The App Store lanes wait for the owner

The iOS lane to TestFlight and the macOS Developer ID signature and notarisation SHALL exist, and SHALL stay off
until the owner switches them on. While they are off, a release SHALL NOT fail because of them.

#### Scenario: Before the Apple subscription
- **WHEN** the owner releases 0.3.0 and the Apple lanes are off
- **THEN** no iOS build is made, the macOS disk image has an ad hoc signature, and the release succeeds

#### Scenario: Switched on without credentials
- **WHEN** the owner switches the Apple lanes on, and a needed secret is missing
- **THEN** the iOS lane fails and names the missing secret, and the other downloads are still attached
