# StoryArc — Agent Guide

This project follows the shared **agent-compass** contract, vendored at
[`docs/agent-compass/`](docs/agent-compass/AGENTS.md). Read it first; everything
below is project-specific and **takes precedence on conflict**.

```bash
git submodule update --init --recursive   # after cloning
```

---

## 1. What this repository is

Two independent native reading apps in one repository. iOS is Swift and SwiftUI.
Android is Kotlin and Compose. They share a written contract, design tokens and
test fixtures — and nothing else.

| Path | What lives there |
| --- | --- |
| `docs/openspec/specs/` | **The contract.** 17 capability specs describing user-observable behaviour. |
| `docs/openspec/changes/` | In-flight proposals. Created with `/opsx:propose`. |
| `apps/ios/` | Swift + SwiftUI. XcodeGen spec, one SPM package with three targets. |
| `apps/android/` | Kotlin + Compose. Gradle with a version catalog, four modules. |
| `apps/desktop-*/` | Planning documents only. **No code.** See [ADR-0004](docs/decisions/0004-desktop-strategy.md). |
| `packages/design-tokens/` | OKLCH token source → generated Swift and Kotlin. |
| `packages/test-fixtures/` | Shared publication corpus, **generated then committed**. Both suites read its `manifest.json` and assert the same expectations. |
| `docs/decisions/` | ADRs. Read 0001 before proposing any architecture change. |
| `docs/design.md` | The design system: what the tokens mean and what is forbidden. |

## 2. Non-negotiables

These are product requirements, not preferences. A change that breaks one is
wrong even if it compiles and passes tests.

1. **No cross-platform UI, ever.** Every pixel is SwiftUI or Compose. No web
   view, no shared UI abstraction, no cross-platform toolkit — the single
   exception is reflowable EPUB content, which is HTML by definition.
   ([ADR-0001](docs/decisions/0001-independent-native-cores.md))
2. **No backend, no account, no analytics, no crash reporting.** Data leaves the
   device only to sources the user configured.
3. **Offline is a normal state, not an error.** An unreachable source is grey,
   never red. The library stays browsable; downloads stay readable.
4. **Secrets go to the platform secure store.** Never preferences, logs,
   backups, or diagnostics. Redact before any string leaves memory.
5. **The artwork is the interface.** Chrome recedes, auto-hides, never tints.

## 3. Before you write code

1. **Read the capability spec.** Every behaviour is specified in
   `docs/openspec/specs/<capability>/spec.md` before it is built. If the behaviour you
   are about to implement is not there, stop and propose a change first:
   `/opsx:propose "<what you want to build>"`.
2. **Read the ADR** if the change touches architecture. ADR-0001 (independent
   cores), ADR-0003 (platform floors), ADR-0005 (format libraries) and ADR-0006
   (progress and sync) answer most "why is it like this" questions.
3. **Check the other platform.** A capability change usually obliges both apps.
   You do not have to implement both — you *do* have to say in the handoff what
   the state of the other one is.
4. **Read the capability's row in [`STATUS.md`](docs/openspec/STATUS.md)** before you
   claim something is missing. Several capabilities are further along than an older
   proposal assumes — `source-lifecycle` proposed building a lifecycle that had
   since been built on both platforms — and proposing to build what exists wastes
   the whole change.

## 3b. The OpenSpec lifecycle — the rules that bind you

The contract lives in an OpenSpec root, and OpenSpec is not just a directory
layout: it is a chain of artifacts with a machine-readable gate. These are the
rules. The generic reference is
[`docs/agent-compass/docs/workflows/openspec.md`](docs/agent-compass/docs/workflows/openspec.md).

**One root, and it is `docs/openspec`.** Declared as `paths.openspec` in
`agent-compass.commands.json`. The CLI resolves the *nearest* root from its working
directory, so **every `openspec` command runs from `docs/`** — `cd docs` first, or
use the `pnpm spec:*` scripts. This is not pedantry: an empty `openspec/` at the
repository root, left behind when the root moved in `e419dc89`, captured resolution
and made the CLI answer `No changes exist` on a repository with six active changes.
`pnpm spec:guard` now fails on a second root. **Print the resolved root in your
handoff.**

**`openspec validate` is not the completion gate.** It checks the files that are
present. `openspec status --change <name> --json` checks the files that *should* be,
and returns `done` / `ready` / `blocked` / `skipped` per artifact plus
`isPlanningComplete`. A change holding a `proposal.md` and nothing else reports
`23 passed` and is half-planned. `source-lifecycle` sat that way from 2026-08-27.

**Write only the artifact the gate calls `ready`.** `/opsx:continue` does exactly
that. A `tasks.md` written while `design` is `blocked` is a task list for a plan
that does not exist, and the plan written afterwards will not match it.

| The artifact | Holds | Never holds |
| --- | --- | --- |
| `proposal.md` | Why, what changes, which capabilities, non-goals | A technical decision |
| `specs/<capability>/spec.md` | Requirements as user-observable behaviour, with scenarios | A class, framework or library name |
| `design.md` | The concrete approach per platform, with versions | A requirement the spec does not state |
| `tasks.md` | Ordered, test-first tasks naming the file or command each touches | An estimate |

The twelve workflows are all installed: `explore`, `new`, `propose`, `ff`,
`continue`, `update`, `apply`, `verify`, `sync`, `archive`, `bulk-archive`,
`onboard`. Six of them were missing until now, `verify` and `continue` among them,
because `openspec update` needs the root at `<project>/openspec` and cannot see
both this root and the agent directories at once. `pnpm openspec:workflows`
generates them from the installed CLI's own templates and
`pnpm openspec:workflows:check` fails `pnpm lint` when a CLI upgrade moves one.

**Five rules with no exceptions:**

1. **A planning workflow never edits code**, even when the request that triggered
   it asked for a feature. Finish the artifacts, stop, and wait for `/opsx:apply`.
2. **Tick a task the moment its validation passes**, not at the end. A list ticked
   at the end is a claim, not a record. Say in the task list what a tick means —
   `source-lifecycle`'s says a tick means the code exists and something asserts it,
   and does *not* mean anyone watched it work.
3. **Never hand-edit a main spec** under `docs/openspec/specs/`. `/opsx:sync` and
   `/opsx:archive` own that file. A hand edit makes the change's delta unmergeable
   and loses the record of why the behaviour changed.
4. **`/opsx:verify` before `/opsx:archive`**, and update the capability's `STATUS.md`
   row from the verify report in the same pass.
5. **When the implementation contradicts `design.md`, the artifact is what is
   wrong.** Run `/opsx:update`. Do not absorb the delta into a bigger diff.

**A change with no delta declares it.** `skip_specs: true` in the change's
`.openspec.yaml`, with the reason written in a comment beside it — the next reader
cannot tell a deliberate skip from a forgotten delta. `source-lifecycle` is the
worked example.

**The rules above are also in `docs/openspec/config.yaml`**, under `rules.<artifact>`
and `operations.<op>.guidance`, which is what makes them reach you through
`openspec instructions` at the moment you write that artifact rather than only here.
When you add a rule about how an artifact is written, add it there. **Quote any list
item containing `": "`** — an unquoted colon makes YAML read the item as a mapping,
the whole config fails to parse, and the CLI's answer is the misleading
`No changes exist`. `pnpm spec:guard` fails on that too.

## 4. Platform floors

| Platform | Minimum | Target |
| --- | --- | --- |
| iOS | 26.0 | latest SDK |
| Android | API 31 (Android 12) | API 37 |

iOS has **no compatibility shims** — Liquid Glass is used directly. Android has
one conditional, `dynamicColorScheme`, available on every supported version.
([ADR-0003](docs/decisions/0003-platform-floors.md))

## 5. Validation

Use `agent-compass.commands.json`. Run the **smallest set that covers the
change** — never the whole repository when one module moved.

| Changed | Run |
| --- | --- |
| `apps/ios/Packages/StoryArcKit` | `pnpm test:ios` (host, no simulator) |
| `packages/test-fixtures` | `pnpm fixtures:build`, then **commit the regenerated corpus and manifest**, then run both platforms' format tests |
| `apps/ios` app target or `project.yml` | `pnpm build:ios` |
| One Android module | `pnpm gradle :<module>:lint :<module>:testDebugUnitTest` |
| Android across modules | `pnpm lint:android && pnpm test:android` |
| `packages/design-tokens` | `pnpm tokens:sync` — then **commit the regenerated app copies in the same change** |
| `docs/openspec/specs` | `pnpm spec:validate` |
| `docs/openspec/changes` | `pnpm spec:validate && pnpm spec:guard` — validate checks the files that are there, the guard checks the ones that should be |
| `docs/openspec/config.yaml` | `pnpm spec:guard` — a broken list item makes the CLI report an empty project |
| The `@fission-ai/openspec` version | `pnpm openspec:workflows` then commit the regenerated workflow files |
| Any Swift or Kotlin file | `pnpm lines:check` — part of `pnpm lint`. The 800-line cap is a ratchet: five files are already over it and recorded in `scripts/line-cap.mjs` with the length they had, so they may shrink and may not grow. A sixth crossing fails the build. |

**Android needs a JDK 21 and an SDK, and neither is on the path by default.**
`pnpm gradle <task>` (and `pnpm lint:android` / `test:android` / `build:android`) find
both, and write the gitignored `apps/android/local.properties` a fresh worktree lacks —
`scripts/gradle.mjs` says where it looks. A bare `./gradlew` still needs `JAVA_HOME`
exported, because the wrapper needs a JVM before it can read any property file. Homebrew's
JDKs are keg-only and macOS ships a `/usr/bin/java` stub that reports no runtime and
shadows them, so "Unable to locate a Java Runtime" means the path, never a missing install.

A task is not complete until you report changed files, the exact commands you
ran, the result of each, whether a failure is pre-existing or introduced, and
the remaining risks. See the Completion Gate in the compass contract.

## 6. Visual proof

**A change a user can see owes a screenshot from a booted simulator or emulator.**

A SwiftUI `#Preview` and a Compose `@Preview` are development aids, not proof —
neither exercises real data, real insets, real system materials, or a real
Dynamic Type setting.

```bash
xcrun simctl io booted screenshot shot.png     # iOS, whatever is on screen
adb exec-out screencap -p > shot.png           # Android, whatever is on screen
```

On Android, prefer the harness — it walks to the screen, sets the condition, and
**puts the device back**, which the raw command cannot do and which a person
forgets:

```bash
pnpm capture:android --list                                        # the routes
pnpm capture:android Downloads --out shot.png --dark --font-scale 2.0
```

Capture **light and dark**, at default and largest text size. Two exceptions,
and the handoff must name which one applies: code behind a flag that nothing
renders yet, and a pure refactor whose screenshots are byte-identical — where
the identical screenshots *are* the proof.

**A screenshot that could look the same for a boring reason needs a control.**
The EPUB reader's chrome photographed in cream proves nothing on its own — the
app might simply not have been set to a dark appearance. The same device, at the
same moment, with the library drawn true black beside it, is what turns the first
picture into evidence. Capture the control whenever the claim is *this screen
disagrees with the rest of the app*.

## 7. Things that will bite you

- **iOS:** `StoryArcKit` builds with `InternalImportsByDefault`. Public API that
  exposes a Foundation or SwiftUI type needs `public import`, not `import`.
- **iOS:** `StoryArc.xcodeproj` is generated and gitignored. Edit `project.yml`
  and run `xcodegen generate`. Never hand-edit the project. One file inside it
  *is* committed — `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
  the app binary's only lockfile. Commit the new resolution whenever a
  dependency moves; `pnpm lockfile:ios` fails if you do not.
- **Android:** AGP 9 compiles Kotlin itself. Do **not** apply
  `org.jetbrains.kotlin.android`; Kotlin options live in
  `android { kotlin { compilerOptions { } } }`. The Compose compiler is still a
  separate plugin.
- **Android:** material3 is pinned to a **1.5.0 alpha** because
  `MaterialExpressiveTheme` is `internal` in 1.4.0. Known risk, documented in
  [`apps/android/README.md`](apps/android/README.md).
- **Tokens:** never edit a `StoryArcTokens.swift` or `StoryArcTokens.kt`. They
  are generated. Edit `packages/design-tokens/tokens/*.json` and run
  `pnpm tokens:sync`.
- **Contrast is a build gate.** `pnpm tokens:check` fails the build on a token
  pair below its WCAG floor. Fix the token, do not lower the floor.
- **Fixtures are generated too.** Never hand-edit a file under
  `packages/test-fixtures/comics/` or its `manifest.json`. Change
  `scripts/generate.py`, run `pnpm fixtures:build`, commit the result.
  `pnpm fixtures:check` fails CI when they drift.
- **The format layer is the drift hotspot.** `PageOrdering`, `ZipReader` and
  `ByteReader` exist in both codebases as deliberate mirrors, asserted against
  the same corpus. Change one, change the other — including the unit tests, which
  match case for case. This layer has already produced one silent cross-platform
  divergence (digit-run overflow in natural sort), which is why it is mirrored
  rather than merely specified.
- **The central directory is the only authority in a ZIP.** Local headers carry
  zeros when a data descriptor is used. Never trust a local header for a size;
  `data-descriptor.cbz` in the corpus exists to catch it.
- **Archive parsing runs on untrusted input.** Every read is bounds-checked
  against the source length, and no length field out of a file is used to
  allocate. See [ADR-0008](docs/decisions/0008-ranged-reads-and-own-zip-reader.md).

## 8. Commits

Conventional commits, scoped by area: `feat(ios):`, `fix(android):`,
`docs(specs):`, `chore(tokens):`.

**Never add AI attribution** — no `Co-Authored-By`, no "Generated with", no
equivalent, in commits, PR titles or bodies, reviews, or issues.

Do not commit, push, tag, or open a PR unless explicitly asked.

## 9. Working in a worktree

Parallel agents each get their own git worktree and a branch. The worktree is a full
checkout, and once Gradle and SwiftPM have built in it, roughly **700 MB** — four agents is
three gigabytes. So the cycle has an end, and the end is part of the task.

**Check what your worktree branched from, before anything else.** A worktree is not
always cut from the tip: two agents in one wave started 14 and 15 commits behind `main`,
and one of them had been briefed to build on a function that did not exist at its base.
`git log --oneline main..HEAD` and `HEAD..main` answer it in a second. If your branch has
no commits of its own, `git merge --ff-only main` before you start; if it already has some,
say so in your report and let the parent decide — do not rebase.

**While you are working in one:**

- **Commit each coherent piece as you finish it.** A mirrored pure type with its tests is a
  commit; wiring it into both UIs is another. Do not save one perfect commit for the end — a
  session that dies with nothing committed loses everything, and that has happened here.
- **Stay inside the files your task names.** Parallel agents rebase cleanly onto each other
  only if their file sets are disjoint. If you need a file another agent owns, say so in your
  report rather than editing it.
- Do not merge, push, or rebase. The parent session does that.

**When the work is done, the parent closes the loop, per branch, in this order:**

1. **Rebase onto `main`**, which has usually moved — other agents merge while you work.
   Rebase, do not merge-commit: it keeps one readable line of history.
   `git rebase main <branch>`
2. **Run the gates on the rebased branch**, not on what the agent tested. A rebase can break
   what passed in isolation, and §5 applies to the merged result, not the agent's snapshot.
3. **Fast-forward onto `main`.** `git merge --ff-only <branch>`
4. **Remove the worktree and *both* branches.** `git worktree remove` leaves behind the
   `worktree-wf_*` branch it was created from — `git worktree list` then looks clean while a
   git client shows dozens of stale branches. Sweep both:
   ```
   git branch -d <branch>
   git worktree remove --force .claude/worktrees/<dir>
   git branch -D worktree-<dir>
   git worktree prune
   ```
5. **Reclaim the build data, which git does not.** `git worktree remove` deletes the
   checkout and nothing else. Xcode keeps build products in
   `~/Library/Developer/Xcode/DerivedData/<name>-<hash of the project path>`, outside the
   repository, and that hash differs for every worktree — so each agent leaves roughly
   **1.5 GB** behind that no git command will ever touch, on top of the ~700 MB inside the
   checkout. Fifty folders had accumulated before anyone looked: **92 GB, 47 of them
   orphaned, on a machine with 1.9 GB free.**
   ```
   pnpm clean:builds        # or clean:builds:dry to see what would go
   ```
   It removes a build folder only when the project it names no longer exists, so it is safe
   to run while other agents are building. **Run it after every wave**, not at the end of a
   session — the point of the cycle having an end is that the end happens each time.

**Never remove a worktree whose agent is still running** — `git worktree list` marks those
`locked`, and removing one destroys uncommitted work. Confirm a branch is merged
(`git log --oneline main..<branch>` is empty) before deleting it.
