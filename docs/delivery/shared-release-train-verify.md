# Verification report: shared-release-train

Run on 2026-10-23 by the completion audit, against `main` at `a7f47b712`. The change's delta adds one
capability, `release-train`, with seven requirements. No requirement names a library; the evidence
below names the file that holds each behaviour. The resolved OpenSpec root is `docs/openspec`.

## Summary

| Dimension | Status |
| --- | --- |
| Completeness | 15 of 16 tasks done before this report; task 5.3 is this report and the archive. 7 of 7 requirements have evidence |
| Correctness | 7 of 7 requirements implemented; 16 of 16 scenarios have a test, a workflow step or a rehearsal run |
| Coherence | `design.md` D1 to D4 are followed; no divergence found |

## Requirements and evidence

| Requirement | Evidence |
| --- | --- |
| One version for every client | `scripts/release.mjs` `disagreements()` (line 288) and `--check` (line 432); `pnpm release:check` runs inside `pnpm lint`; `release.yml` step "Every client carries the same version" (line 66). Self-test: "every client at 0.1.0 disagrees with 0.2.1" and "after writing, every client agrees" |
| One tag builds every download | `release.yml` `on.push.tags: ['v*']`, five lanes with `needs: prepare` and no `needs` between them (lines 84 to 111); `publish` runs with `if: always()` (line 122) and names a missing download: self-test "a missing download is named" (line 366) |
| Nothing reaches a reader without the owner | `release.yml` line 155: `gh release create ... --draft --verify-tag`; `android-release.yml` uploads a Play draft (task 4.x notes, rehearsal 39590092252, fix `069bc5939`: a draft upload never sends changes for review); `android-promote.yml` is the manual roll-out |
| The desktop downloads install and run | `windows-release.yml` lines 85 to 122: the portable copy makes `data` beside itself and writes nothing to the profile, the installed copy writes to LOCALAPPDATA, both started for 20 seconds; `apps/desktop-windows/packaging/StoryArc.iss` installs per user; `macos-release.yml` and `apps/desktop-macos/packaging` make the designed window (task 3.x notes); `linux-release.yml` installs the bundle in CI |
| Reader's notes for phones and for desktops | `scripts/release.mjs` `GROUPS` (line 61), self-tests "a missing language is refused" (line 347), "desktop lines do not count against Play" (line 357), "the release text has a heading for each group" (line 360) |
| A rehearsal publishes nothing | `release.yml` `on.push.paths` (lines 24 to 30) and `workflow_dispatch`; `REHEARSAL` keeps the artefact `release-rehearsal-<sha>` (line 146) and skips the draft (line 152). Rehearsal run 39590092252 is green on every lane with no tag, release or upload |
| The App Store lanes wait for the owner | `release.yml` line 112: `if: vars.APPLE_RELEASES == 'true'`; the `ios` job is skipped in the rehearsal and the release succeeds without it |

## Issues

**CRITICAL:** none.

**WARNING:**

- The scenario *Play refuses the upload* (a duplicate build number) has no recorded run. The lane's
  `continue` shape is in `android-release.yml`, and the APK stays attached because `publish` runs with
  `if: always()`. Record the first real refusal when one happens.
- The *macOS disk image* window and the *Linux bundle* start are proved by CI steps, not by a person.
  The owner's first real release is the proof.

**SUGGESTION:** none.

## Assessment

No critical issue. Two warnings to carry. Ready for archive. The release train has rehearsed 0.2.2
on 2026-10-21 and no release has used it for real yet.
