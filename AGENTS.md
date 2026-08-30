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
| `docs/openspec/specs/` | **The contract.** 15 capability specs describing user-observable behaviour. |
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
| One Android module | `cd apps/android && ./gradlew :<module>:lint :<module>:testDebugUnitTest` |
| Android across modules | `pnpm lint:android && pnpm test:android` |
| `packages/design-tokens` | `pnpm tokens:sync` — then **commit the regenerated app copies in the same change** |
| `docs/openspec/specs` | `pnpm spec:validate` |

A task is not complete until you report changed files, the exact commands you
ran, the result of each, whether a failure is pre-existing or introduced, and
the remaining risks. See the Completion Gate in the compass contract.

## 6. Visual proof

**A change a user can see owes a screenshot from a booted simulator or emulator.**

A SwiftUI `#Preview` and a Compose `@Preview` are development aids, not proof —
neither exercises real data, real insets, real system materials, or a real
Dynamic Type setting.

```bash
xcrun simctl io booted screenshot shot.png     # iOS
adb exec-out screencap -p > shot.png           # Android
```

Capture **light and dark**, at default and largest text size. Two exceptions,
and the handoff must name which one applies: code behind a flag that nothing
renders yet, and a pure refactor whose screenshots are byte-identical — where
the identical screenshots *are* the proof.

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

**Never remove a worktree whose agent is still running** — `git worktree list` marks those
`locked`, and removing one destroys uncommitted work. Confirm a branch is merged
(`git log --oneline main..<branch>` is empty) before deleting it.
