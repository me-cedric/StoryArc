## 1. One version and the notes

- [x] 1.1 Align the client versions to 0.2.1, build 6, in every file of design D2. No tag. Verify:
  `node scripts/release.mjs --check` passes.
  **Done 2026-10-21:** every client at 0.2.1 (6); the metainfo release is dated 2026-10-10, the tag date of v0.2.1.
- [x] 1.2 Add the version table and `--check` to `scripts/release.mjs`, with self-test cases for each file and for a
  disagreement. Verify: `pnpm release:selftest` passes, and `--check` fails by file name on a changed file.
  **Done 2026-10-21:** `CLIENTS` and `disagreements` in `scripts/release.mjs`; the self-test covers each file, a nested
  `version` left alone, and a wrong build number named by file.
- [x] 1.3 The release command writes every file of the table and refuses a version whose notes miss a language,
  before it commits. Verify: a self-test case with a missing `fr-FR` section stops; `pnpm release patch --dry` lists
  every file.
  **Done 2026-10-21:** the missing-language refusal already ran before the commit; the command now also refuses
  disagreeing clients before the bump and writes every `CLIENTS` file.
- [x] 1.4 Split notes (design D3): `--play-notes` keeps the desktop lines out; `--release-body` prints the GitHub
  text. Verify: self-test cases for a desktop-only line and a mobile-only line.
  **Done 2026-10-21:** `notesGroups`, `playNotes` (a generic line when a release has no phone line), `releaseBody`
  with `--notes-from` for a rehearsal; self-test cases for both groups and for missing downloads.
- [x] 1.5 Run `release.mjs --check` in `pnpm lint`. Verify: `pnpm lint` passes.
  **Done 2026-10-21:** `pnpm release:check` is the second step of `pnpm lint`.

## 2. The train

- [x] 2.1 `release.yml` with `prepare`, the lanes and `publish` (design D4). `android-release.yml` becomes a reusable
  lane with a draft Play upload, and loses its tag trigger and `gh release create`, in the same commit. Verify:
  `actionlint` passes.
  **Done 2026-10-21:** `actionlint` passes on every release workflow.

## 3. The lanes

- [x] 3.1 Windows: data root and version without package identity (design D5), with a unit test of the data root.
  Verify: the test passes on the Windows runner.
  **Done 2026-10-21:** `StoryArc.Interop.Shell.DataRoot`, used by `StateFiles`; the version is the assembly's and
  the title the brand name. `DataRootTests` (3) pass with `dotnet test` on the Mac; the Windows runner runs them on
  the next pull request through `desktop-windows.yml`.
- [x] 3.2 Windows lane: self-contained publish, portable zip, Inno Setup installer, smoke start, for x64 and ARM64.
  Verify: the rehearsal artefact holds four Windows files, and the smoke step passes on x64.
  **Done 2026-10-21:** rehearsal 39590092252: four Windows files; on x64 the portable copy and the installed copy
  each start and stay up for 20 s, and the uninstaller removes the app. The check found two start-up crashes,
  fixed in `SystemSettingsWatcher.cs` and `AccentApplier.cs`, and `Shell/CrashLog.cs` now keeps a local record.
- [x] 3.3 macOS: the background drawing and the `dmgbuild` settings. Verify: a local disk image opens on this Mac
  with the app, the Applications link and the arrow on the background.
  **Done 2026-10-21:** `make-background.swift`, `background.tiff`, `dmg-settings.py`, `make-dmg.sh`, and the Mac
  app icon (`make-icon.swift`, it had none). The screen was locked, so the window was checked from the image's
  `.DS_Store` layout drawn over the background, not a Finder screenshot.
- [x] 3.4 macOS lane: archive, ad hoc signature, disk image; the Developer ID and notarisation path behind
  `APPLE_RELEASES`. Verify: the rehearsal artefact holds the disk image.
  **Done 2026-10-21:** rehearsal 39583011946 made `StoryArc-0.2.1-macos.dmg`: universal (x86_64, arm64), 0.2.1,
  ad hoc signature.
- [x] 3.5 Linux lane: Flatpak bundle for x86_64 and aarch64 with the runtime repository, and an install check.
  Verify: the rehearsal artefact holds two bundles, and `flatpak info` passes in each job.
  **Done 2026-10-21:** rehearsal 39584537758 built and installed both bundles, after `cargo-sources.json` was
  regenerated (549 crates; `aes-gcm` was missing).
- [x] 3.6 iOS lane behind `APPLE_RELEASES`. Verify: `actionlint` passes; the rehearsal shows the job as skipped.
  **Done 2026-10-21:** `actionlint` passes; every rehearsal shows `ios` as skipped.

## 4. Rehearsal

- [x] 4.1 Push the branch and let the rehearsal run. Verify: every lane is green, and the artefact holds the APK,
  four Windows files, the disk image, two Flatpak bundles and the release text. No tag, release or Play upload
  exists.
  **Done 2026-10-21:** rehearsal 39590092252 green on every lane, `ios` skipped; the artefact holds all eight
  downloads and a release text that names nothing as missing. No tag, release or Play upload was made.

## 5. Docs and close

- [x] 5.1 Rewrite `AGENTS.md` §10 and the "Releasing" part of `CLAUDE.md`: one command, the draft release, the Play
  draft, the rehearsal, the Apple switch. Update the head of `RELEASE_NOTES.md` for the three groups. Verify: every
  workflow name in the docs exists under `.github/workflows/`.
  **Done 2026-10-21:** §10 and "Releasing" rewritten; the notes head names the three groups.
- [x] 5.2 Add the `release-train` row to `docs/openspec/STATUS.md`. Verify: the row names the Apple lanes as off.
  **Done 2026-10-21:** the "Releases" section at the end of STATUS.md.
- [ ] 5.3 Run `/opsx:verify`, then `/opsx:archive`. Verify: `pnpm spec:guard` reports no error.
