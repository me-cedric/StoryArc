## Context

See proposal.md for the motivation and specs/release-train/spec.md for the behaviour.

The current state, with the file that proves each part:

- `scripts/release.mjs` bumps `versionName` and `versionCode` in `apps/android/gradle.properties`, writes the
  version into `package.json`, files the `## Unreleased` notes of `RELEASE_NOTES.md`, commits, tags `vX.Y.Z` and
  pushes. It reads and writes no other client version.
- `.github/workflows/android-release.yml` starts on `push: tags: ['v*']`. It builds the bundle and the APK,
  publishes the GitHub release with `gh release create`, and rolls the bundle out to Play internal testing with
  `fastlane supply --release_status completed`.
- `desktop-windows.yml` builds on `windows-2025-vs2026` and makes an unsigned MSIX with `build.ps1 -Package`. The
  app reads its data folder from `ApplicationData.Current.LocalFolder` (`Shell/StateFiles.cs`) and its version from
  `Package.Current` (`Shell/NetworkServices.cs`). Both throw when the app has no package identity.
- `desktop-macos.yml` generates the project with XcodeGen and builds on `macos-26`. The `.xcodeproj` is not tracked.
- `apps/desktop-linux/scripts/flatpak-build.sh` builds the Flatpak from `build-aux/com.mecedric.StoryArc.json` in the
  `ghcr.io/flathub-infra/flatpak-github-actions:gnome-51` image. The build passed on aarch64
  (desktop-clients task 1.25 notes).
- Client versions: Android 0.2.1 (code 6); the two `project.yml` files 0.1.0 (build 1); `Cargo.toml`
  `[workspace.package]` 0.1.0; `Package.appxmanifest` `0.1.0.0`; the Linux metainfo `<release version="0.1.0">`.
- The repository is public, so the `ubuntu-24.04-arm` runner is free.

## Goals / Non-Goals

**Goals:**

- One tag builds every download into a draft release. A rehearsal proves the same path on every push to the
  release machinery, without a tag.
- No new build tool beyond Inno Setup on Windows and `dmgbuild` on macOS.
- The Apple lanes are complete and stay off.

**Non-Goals:**

- A change to what a client does, except the Windows data folder and version source when the app has no package.

**Accessibility:** no screen changes. The disk image window has text labels from Finder for the app and the
Applications folder; the background carries no text that a reader needs.

## Decisions

### D1. The Android build number is the build number of every client

`versionCode` stays the one counter. `release.mjs` writes it as `CURRENT_PROJECT_VERSION` for iOS and macOS. The
Windows file version is `X.Y.Z.0`, because the Microsoft Store requires the fourth part to be 0 (Reported) and a
later Store lane then needs no change. Linux carries no build number.

### D2. `release.mjs` writes every version file, and `--check` keeps them equal

`gradle.properties` stays the source. A table in `release.mjs` lists each file with a read and a write function:

| File | Field |
| --- | --- |
| `apps/android/gradle.properties` | `versionName`, `versionCode` (source) |
| `package.json` | `version` |
| `apps/ios/project.yml`, `apps/desktop-macos/project.yml` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` |
| `Cargo.toml`, `Cargo.lock` | `[workspace.package] version`; the entries of the workspace crates |
| `apps/desktop-windows/src/StoryArc.Windows/StoryArc.Windows.csproj` | `<Version>` |
| `apps/desktop-windows/src/StoryArc.Windows/Package.appxmanifest` | `Identity Version`, as `X.Y.Z.0` |
| `apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml` | the first `<release version date>` |

`node scripts/release.mjs --check` fails, by file name, on a disagreement. `pnpm lint` runs it. *Alternative:* CI
passes the version to each build from the tag. Rejected: §10 forbids `-PversionName` in a publishing lane, because a
local build of the same commit then shows another version.

`Cargo.lock` is edited as text for the workspace crates, so `release.mjs` needs no Rust toolchain. The Linux CI
build runs `cargo build --locked`, which fails on a lock that disagrees.

### D3. Notes in three groups

Under each `### <language>` heading, lines before any sub-heading apply everywhere. Two optional sub-headings follow:
`#### Phones and tablets` and `#### Desktop`. `--play-notes` writes the shared lines and the mobile lines, and keeps
the 500-character limit. A new `--release-body <version>` prints the GitHub release text: the en-US lines under
"Everywhere", "Phones and tablets" and "Desktop" (only the headings that have lines), then the table of downloads
and the steps for an unsigned download. *Alternative:* a platform prefix on each line. Rejected: it cannot keep a
desktop line out of Play.

### D4. One orchestrating workflow with reusable lanes

```
release.yml
  on: push tags v*            -> real run
      push branches, paths    -> rehearsal (release workflows, scripts/release.mjs, packaging files)
      workflow_dispatch       -> rehearsal
  prepare  version, tag == v<versionName> (real run), release.mjs --check, release body
  android  uses android-release.yml   needs prepare
  windows  uses windows-release.yml   needs prepare   matrix x64, ARM64
  macos    uses macos-release.yml     needs prepare
  linux    uses linux-release.yml     needs prepare   matrix x86_64, aarch64
  ios      uses ios-release.yml       needs prepare   if vars.APPLE_RELEASES == 'true'
  publish  needs all, if always()
           real run:  gh release create --draft with every download that exists, and the body;
                      a line for each missing platform
           rehearsal: one artefact "release-rehearsal-<sha>" with the downloads and the body
```

Each lane builds and uploads its files as a workflow artefact. Only `publish` talks to the GitHub release, so the
lanes never race to make it. Jobs that only need `prepare` do not cancel each other (Known: only a matrix with
`fail-fast` cancels). A matrix sets `fail-fast: false`. Path filters do not apply to tag pushes (Known), so one
`push` block carries both.

`android-release.yml` becomes `workflow_call` with a `rehearsal` input, keeps `workflow_dispatch` for a manual Play
run, loses `push: tags`, and loses `gh release create`. On a tag it uploads to Play with `--release_status draft`.
A manual run keeps the `track` and `releaseStatus` inputs, so `completed` stays available when the owner asks. A
rehearsal builds and signs, and skips Play.

### D5. Windows: an unpackaged, self-contained build

`dotnet publish` with `-p:WindowsPackageType=None -p:SelfContained=true -p:WindowsAppSDKSelfContained=true` for each
platform. The output folder runs without the .NET or Windows App SDK runtimes. WebView2 ships with Windows 11.

- `StateFiles` gets one data root. With package identity: `ApplicationData.Current.LocalFolder`, as today. Without
  it: `data\` beside the executable when a file named `portable` is there, else `%LOCALAPPDATA%\StoryArc`. The
  identity check is one `ApplicationData.Current` call in a `try`, done once (`Shell/StateFiles.cs`). The pure
  function `StoryArc.Interop.Shell.DataRoot` takes the inputs and is unit-tested (`DataRootTests`).
- The version comes from the assembly version, for every build. The `.csproj` gets `<Version>`, which
  `release.mjs` writes and keeps equal to `Package.appxmanifest`. The window title is the literal brand name,
  not `AppInfo`, which also needs a package.
- Portable: the publish folder plus the `portable` file, zipped as `StoryArc-X.Y.Z-windows-<arch>-portable.zip`.
- Installer: Inno Setup 6, script `apps/desktop-windows/packaging/StoryArc.iss`. `PrivilegesRequired=lowest`, install
  to `{localappdata}\Programs\StoryArc`, a Start menu entry, an uninstaller, `ArchitecturesAllowed` set for each
  architecture. Output `StoryArc-X.Y.Z-windows-<arch>-setup.exe`. The runner image ships Inno Setup or the lane
  installs it with Chocolatey (Assumed: the lane prints `iscc` and its version).
- A smoke step starts the published `StoryArc.exe`, waits 20 seconds, fails if the process exited, then stops it.

### D6. macOS: an ad hoc disk image with a designed window

`xcodebuild archive` of the `StoryArc` scheme for `generic/platform=macOS` with `CODE_SIGN_IDENTITY=-`, then the
`.app` from the archive. `dmgbuild` 1.6.5 (pip) writes the disk image and its window layout without Finder, so it
works on a runner with no session. Settings file `apps/desktop-macos/packaging/dmg-settings.py`: window 660 x 400,
icon size 128, the app at (180, 200), the Applications link at (480, 200), `background.tiff`.

The background is drawn by `apps/desktop-macos/packaging/make-background.swift` with AppKit: the brand arc gradient
(`#F566B8`, `#A855F7`, `#5B4BF5`) at low strength on a light surface, and an arrow between the two icon positions.
It writes 660 x 400 and 1320 x 800 PNGs, and `tiffutil -cathidpicheck` joins them into one Retina TIFF. The TIFF is
tracked, and the script stays to redraw it.

When `vars.APPLE_RELEASES == 'true'`, the lane instead signs with the Developer ID certificate in a temporary
keychain, notarises with `xcrun notarytool submit --wait` and the App Store Connect key, and staples the ticket. The
step fails and names the missing secret when one is empty.

### D7. Linux: a Flatpak bundle for each architecture

The job runs in the `gnome-51` image with `--privileged`, as `flatpak-build.sh` does. `flatpak-builder --repo=repo`,
then `flatpak build-bundle repo StoryArc-X.Y.Z-linux-<arch>.flatpak com.mecedric.StoryArc
--runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo`, so that `flatpak install --user` finds the runtime.
x86_64 on `ubuntu-24.04`, aarch64 on `ubuntu-24.04-arm`. A smoke step installs the bundle in the container and runs
`flatpak info`.

### D8. iOS: a complete lane that stays off

`ios-release.yml`: XcodeGen, `xcodebuild archive`, `-exportArchive` with `method app-store-connect` and automatic
signing through the App Store Connect key (`-allowProvisioningUpdates`), then `fastlane pilot upload` with the notes
as "What to Test", internal testers only. It runs only when `vars.APPLE_RELEASES == 'true'`. The first step names
each empty secret: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.

## Risks / Trade-offs

- [The APK is no longer public the moment the tag lands] → the owner publishes the draft; §10 says so.
- [`ms-appx:` fonts or resources fail without package identity] → the smoke step catches a crash at start; a
  rendering defect needs a look on a Windows PC, which the owner can do with the rehearsal zip.
- [SmartScreen and Gatekeeper warn on the unsigned downloads] → the release text gives the steps to open them.
- [`cargo-sources.json` is stale after a `Cargo.lock` change] → the Flatpak build fails offline and names the crate;
  run `flatpak-cargo-sources.sh`.
- [A secret appears in a log] → secrets go through `env` or a file in `$RUNNER_TEMP` that an `if: always()` step
  removes, as `android-release.yml` does today.
- [A rehearsal on every push to the release files costs runner minutes] → path filters keep it to the release
  machinery, and `concurrency` cancels an older rehearsal of the same branch.

## Migration Plan

1. Align the client versions to 0.2.1, build 6. No tag.
2. Land `release.mjs --check` in `pnpm lint`, and the split notes.
3. Land `release.yml` and the lanes, and remove the tag trigger from `android-release.yml` in the same commit.
4. A rehearsal on the branch passes, and its artefact holds every download.

Rollback: restore `push: tags` and `gh release create` in `android-release.yml`, and delete `release.yml`.

## Open Questions

1. The owner sets `APPLE_RELEASES` to `true` and adds the Apple secrets after the subscription. Nothing in this
   change depends on the date.
