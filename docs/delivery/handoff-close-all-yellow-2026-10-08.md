# Agent Handoff: close every yellow row (stopped 2026-10-08)

Goal: close every open and partial task, so that no row of the README status table stays yellow.
Mode: implementation, stopped in the middle of wave 3 of 6.
Spec: the open changes under `docs/openspec/changes/`. The task lists are the record.
Branch: work lands on `main`. `main` is `6088f1cd` (wave 2 landed), and it is on `origin/main`.
Base: `main`.

The session stopped after a crash and a spend limit. Nothing runs now: no workflow, no agent, no emulator, no simulator and no Gradle daemon.

## 1. Where the working files are

The plan files are outside the repository, beside the agent memory:
`~/.claude/projects/-Users-mecedric-Documents-Projects-StoryArc/close-yellow-2026-10-07/`

| File | What it is |
| --- | --- |
| `RESUME.md` | The six-wave plan |
| `decisions.md` | D1 to D38, then the owner answers O1 to O8 and the parent choices O9 to O22. An O-row wins over older text in a tasks.md |
| `pkg-<lane>.json` | The tasks of each lane, with `whatIsLeft` from the triage of 2026-10-07 |
| `waves.json` | The lanes of waves 3 to 6, with their simulators, emulators and extra instructions |
| `pipeline.js` | The workflow script for waves 3 to 6. It takes `waves.json` as args, plus `prefilled` and `hints` (see section 4) |
| `brief-worker.md`, `brief-reviewer.md`, `brief-merge.md`, `brief-frames.md`, `brief-land.md` | The agent briefs. Sections 0 and 0b hold the time caps and the memory rules |
| `done/` | The saved reports of the agents that finished, and `prefilled.json` |
| `device-checklist.md` | One line for each device step that was proved on a simulator or an emulator |

## 2. What landed

| Wave | State | Main |
| --- | --- | --- |
| Triage and owner decisions | Landed. 13 stale ticks fixed. The spec deltas for O3 (credentials sealed under a passphrase) and O4 (iOS fetches a remote PDF whole) are written | `1f4daf15` |
| 1: voice-android, curl-core, stream, portability-data | Landed. 13 tasks ticked | `3bb5c9b4` |
| 2: smb3, covers-a, curl-prose, ios-playback | Landed. 12 tasks ticked. Findings 23.3 to 23.7 recorded | `6088f1cd` |
| 3: widgets, covers-b, portability-ui, android-player | Built, reviewed and merged on the branch `wave-3`. **Not landed**: the Android frames and the land step did not finish | none |
| 4: sync-engine, l10n, fixes-android | Built and reviewed. **Not merged** | none |
| 4: fixes-ios, readers-proof | Partly built. A spend limit stopped both | none |
| 5 and 6 | Not started | none |

Task counts on `main` at `6088f1cd` (done, partial, open): audiobooks-and-playback 76, 11, 4; close-the-audited-gaps 232, 3, 12; cover-for-every-publication 16, 6, 5; library-portability 19, 4, 7; library-sync 3, 0, 18; one-library-three-destinations 21, 15, 1; one-vocabulary-in-four-languages 24, 5, 3; publication-detail 13, 12, 4; read-aloud-beyond-the-reader 15, 8, 1; reader-theming-and-page-transitions 51, 5, 2; a-server-shelf-shows-what-it-holds 28, 0, 1. Waves 3 and 4 close many of these when they land. `desktop-clients` belongs to another session and is not part of this goal.

## 3. Worktrees that hold unlanded work

Keep each one until its work is on `main`. Each is under `.claude/worktrees/`.

| Worktree | Branch | What it holds |
| --- | --- | --- |
| `wf_a5d53750-639-9` | `wave-3` | Wave 3 merged (`755ff045`). Uncommitted: the Android frames in `docs/designs/screenshots/{android-player,covers-b-android,library-portability-android,widgets-android}-2026-10-08/` and an edit to `scripts/android-routes.mjs`. The iOS frames report is in `done/w3-frames-ios.json` |
| `wf_a5d53750-639-1` to `-4` | `worktree-wf_a5d53750-639-1` to `-4` | The wave 3 lanes, already merged into `wave-3`. Remove them after wave 3 lands |
| `wf_a5d53750-639-12` | `worktree-wf_a5d53750-639-12` | Wave 4 sync-engine, done and reviewed (`done/w4-sync-engine.json`) |
| `wf_a5d53750-639-13` | `worktree-wf_a5d53750-639-13` | Wave 4 l10n, done and reviewed (`done/w4-l10n.json`) |
| `wf_a5d53750-639-14` | `worktree-wf_a5d53750-639-14` | Wave 4 fixes-android, done and reviewed (`done/w4-fixes-android.json`) |
| `wf_176858a0-d64-2` | `worktree-wf_176858a0-d64-2` | Wave 4 fixes-ios, the newest copy: the commits of `639-15`, plus a work-in-progress commit `48b62cd5`. Not reviewed |
| `wf_a5d53750-639-15` | `worktree-wf_a5d53750-639-15` | The older fixes-ios copy. `d64-2` replaces it. Remove it after `d64-2` lands |
| `wf_a5d53750-639-18` | `worktree-wf_a5d53750-639-18` | Wave 4 readers-proof: uncommitted only (`apps/ios/UITests/CurlWalk.swift` and eight frames under `docs/designs/screenshots/a-tap-that-curls-2026-10-06/`) |

## 4. How to continue

1. Read `RESUME.md`, `decisions.md` and this note. Check that nothing runs: `pgrep -fl "qemu-system|GradleDaemon"` and `xcrun simctl list devices booted`.
2. Check the base of each worktree in section 3 with `git -C <worktree> log --oneline -3` and `git -C <worktree> status --porcelain`.
3. Launch a **fresh** run of `pipeline.js` with `waves.json` as args. Add `"base": "main"`, the `prefilled` map from `done/prefilled.json`, and these `hints`:
   - `build:fixes-ios`: take over `wf_176858a0-d64-2` (not `639-15`), and finish the package `pkg-fixes-ios.json`.
   - `build:readers-proof`: take over the uncommitted work in `wf_a5d53750-639-18`, and finish `pkg-readers-proof.json`.
   - `frames:w3:android`: keep the good uncommitted frames in `wf_a5d53750-639-9`, and take only what is missing.
   - `land:w3`: read `git log` and `git status` in `wf_a5d53750-639-9` first.

   In `waves.json`, the wave 3 lanes and the wave 4 lanes sync-engine, l10n and fixes-android need only their `key`, because `prefilled` skips them.
4. **Do not use `resumeFromRunId`** on this pipeline. The cache replays only the unchanged prefix of agent calls in call order. Parallel results come back in a new order, so finished agents run again. This happened once on 2026-10-08 and was stopped in time.
5. When waves 3 to 6 land, do the docs pass of wave 6 in `RESUME.md`. Archive each change whose tasks are all ticked. Update the STATUS rows and turn the README rows green. Give the owner `device-checklist.md`.

## 5. Decisions taken in this goal

The owner answered eight questions on 2026-10-07 (O1 to O8 in `decisions.md`):
- The finger drives the EPUB curl.
- A coverless iOS shelf draws the generic glyph.
- Credentials travel in an export only when the reader asks, sealed under a passphrase.
- iOS fetches a remote PDF whole before it opens it.
- Widget and CarPlay signing stays an owner step.
- A device step is proved on an emulator, and the owner gets a checklist.
- SMB 3 encryption is proved against the local Samba (`scripts/smb-server.sh --encrypted`).
- Each wave lands on `main` and is pushed. There is no release.

The parent took O9 to O22 under the owner's standing rule: the choice with the most features that stays true to the Apple HIG and Material 3. Two need the owner to know about them:
- O21: a book that ends on a damaged part is not marked finished.
- O22: this Mac's Xcode 27 has no Simulator.app, so the CarPlay window proof is on the device checklist.

## 6. Risks

- **Spend limit.** It stopped four agents at once on 2026-10-08. A wave of four lanes uses about 10 agents and 3 to 4 million tokens.
- **Memory.** The Mac has 24 GB, and the swap reached 50 GB. One cause was ours: a leaked emulator. Run one emulator at a time, booted with `-memory 2048 -no-window`. Kill it when it is no longer needed. Run `./gradlew --stop` when a lane ends. The briefs carry this rule in section 0b.
- **Hung UI tests.** One land step lost 11 hours to iOS UI tests with no time cap. Every brief now caps commands with `perl -e 'alarm shift; exec @ARGV' <seconds> <command>`.
- **Another session commits desktop work to `main`.** A land step must rebase onto `main` before it fast-forwards.

## 7. Validation of what landed

| Command | Result |
| --- | --- |
| `pnpm lint` on wave 1 and wave 2 | passed |
| `pnpm test:ios`, `pnpm test:android`, `pnpm build:ios`, `pnpm build:android` on wave 1 | passed |
| `pnpm test:ios` on the smb3 lane (3,658 tests) and the widgets lane (3,740 tests) | passed |
| Waves 3 and 4 on the merged tree | not run: they are not merged |

## Next Step

1. Launch the fresh `pipeline.js` run that section 4 describes.
