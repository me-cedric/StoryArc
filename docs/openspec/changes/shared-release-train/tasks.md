## 1. One version and the notes

- [ ] 1.1 Align the client versions to 0.2.1, build 6, in every file of design D2. No tag. Verify:
  `node scripts/release.mjs --check` passes.
- [ ] 1.2 Add the version table and `--check` to `scripts/release.mjs`, with self-test cases for each file and for a
  disagreement. Verify: `pnpm release:selftest` passes, and `--check` fails by file name on a changed file.
- [ ] 1.3 The release command writes every file of the table and refuses a version whose notes miss a language,
  before it commits. Verify: a self-test case with a missing `fr-FR` section stops; `pnpm release patch --dry` lists
  every file.
- [ ] 1.4 Split notes (design D3): `--play-notes` keeps the desktop lines out; `--release-body` prints the GitHub
  text. Verify: self-test cases for a desktop-only line and a mobile-only line.
- [ ] 1.5 Run `release.mjs --check` in `pnpm lint`. Verify: `pnpm lint` passes.

## 2. The train

- [ ] 2.1 `release.yml` with `prepare`, the lanes and `publish` (design D4). `android-release.yml` becomes a reusable
  lane with a draft Play upload, and loses its tag trigger and `gh release create`, in the same commit. Verify:
  `actionlint` passes.

## 3. The lanes

- [ ] 3.1 Windows: data root and version without package identity (design D5), with a unit test of the data root.
  Verify: the test passes on the Windows runner.
- [ ] 3.2 Windows lane: self-contained publish, portable zip, Inno Setup installer, smoke start, for x64 and ARM64.
  Verify: the rehearsal artefact holds four Windows files, and the smoke step passes on x64.
- [ ] 3.3 macOS: the background drawing and the `dmgbuild` settings. Verify: a local disk image opens on this Mac
  with the app, the Applications link and the arrow on the background.
- [ ] 3.4 macOS lane: archive, ad hoc signature, disk image; the Developer ID and notarisation path behind
  `APPLE_RELEASES`. Verify: the rehearsal artefact holds the disk image.
- [ ] 3.5 Linux lane: Flatpak bundle for x86_64 and aarch64 with the runtime repository, and an install check.
  Verify: the rehearsal artefact holds two bundles, and `flatpak info` passes in each job.
- [ ] 3.6 iOS lane behind `APPLE_RELEASES`. Verify: `actionlint` passes; the rehearsal shows the job as skipped.

## 4. Rehearsal

- [ ] 4.1 Push the branch and let the rehearsal run. Verify: every lane is green, and the artefact holds the APK,
  four Windows files, the disk image, two Flatpak bundles and the release text. No tag, release or Play upload
  exists.

## 5. Docs and close

- [ ] 5.1 Rewrite `AGENTS.md` §10 and the "Releasing" part of `CLAUDE.md`: one command, the draft release, the Play
  draft, the rehearsal, the Apple switch. Update the head of `RELEASE_NOTES.md` for the three groups. Verify: every
  workflow name in the docs exists under `.github/workflows/`.
- [ ] 5.2 Add the `release-train` row to `docs/openspec/STATUS.md`. Verify: the row names the Apple lanes as off.
- [ ] 5.3 Run `/opsx:verify`, then `/opsx:archive`. Verify: `pnpm spec:guard` reports no error.
