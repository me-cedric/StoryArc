## Why

StoryArc now has five clients: Android, iOS, macOS, Windows and Linux. Only Android has a release lane. The
`vX.Y.Z` tag builds the Android app and nothing else. The desktop workflows run on pushes to `main` and publish
nothing. Each client also keeps its own version, and the versions do not agree today: Android is 0.2.1, and iOS,
macOS, Windows and Linux are 0.1.0. A reader with two devices cannot tell if the two builds have the same features.

One version and one tag for all clients keep the clients together. The clients share the core, the specs and the
reader's notes.

## What Changes

- One release has one version `X.Y.Z` and one build number for every client. `pnpm release` writes the version into
  each client and adds it to the release commit. A check fails when two clients disagree.
- One `vX.Y.Z` tag builds every download: the Android APK, a Windows installer and a portable Windows zip, a macOS
  disk image with a designed window, and a Linux Flatpak bundle. The lanes are independent. A lane that fails does
  not stop the others.
- Nothing reaches a reader without the owner. The GitHub release is made as a draft, and the owner publishes it.
  The Play upload is a draft on internal testing, and the owner rolls it out and promotes it in the Play Console.
  An automatic roll-out stays possible, only when the owner asks for it in a manual run.
- A rehearsal builds every download and the release text, and publishes nothing. It runs on each push that changes
  the release machinery.
- The reader's notes stay one file, with lines for every platform, lines for phones and tablets, and lines for
  desktops. Play gets the shared and the mobile lines. The GitHub release gets all of them, under headings.
- **BREAKING** for the APK: a tag no longer publishes the GitHub release and no longer rolls out to Play internal
  testers by itself.
- The Windows app runs without an MSIX package, so that the installer and the portable zip work. The portable copy
  keeps its data in a folder beside itself.
- The App Store lanes for iOS and macOS (TestFlight, Developer ID signature, notarisation) are written but switched
  off, until the owner has an Apple Developer subscription and switches them on.

Platforms: Android, iOS, macOS, Windows and Linux. iOS gets only the switched-off lane.

## Capabilities

### New Capabilities

- `release-train`: how a version reaches the readers on each platform: one version, one tag, the downloads that a
  release carries, a rehearsal, and the owner's manual steps.

### Modified Capabilities

None. `settings-and-about` already asks each client to show its version. This change makes the shown version the
same on every platform.

## Non-goals

- The Microsoft Store. The MSIX stays a CI artefact.
- A signed Windows installer. Windows SmartScreen warns on the first run until the owner buys a signing identity.
- A Developer ID signature and notarisation for the macOS download, until the owner has the Apple subscription.
- A Flathub submission. Flathub requires that a human submits it (desktop-clients task 6.5).
- An update check inside the desktop apps.
- A separate version or tag for each platform.

## Impact

- `scripts/release.mjs` and its self-test: the version of each client, `--check`, the split notes, the release text.
- Version files: `apps/android/gradle.properties`, `package.json`, `apps/ios/project.yml`,
  `apps/desktop-macos/project.yml`, `Cargo.toml` and `Cargo.lock`, the Windows `.csproj` and `Package.appxmanifest`,
  the Linux metainfo file.
- Workflows: a new `release.yml`; `android-release.yml` becomes one of its lanes; new Windows, macOS, Linux and iOS
  lanes.
- Windows app: the data folder when the app has no package identity, and the version shown on About.
- macOS: a disk image background and its layout.
- Docs: `AGENTS.md` §10, `CLAUDE.md` "Releasing", `RELEASE_NOTES.md` head.
