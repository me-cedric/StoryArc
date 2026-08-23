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
| `openspec/specs/` | **The contract.** 15 capability specs describing user-observable behaviour. |
| `openspec/changes/` | In-flight proposals. Created with `/opsx:propose`. |
| `apps/ios/` | Swift + SwiftUI. XcodeGen spec, one SPM package with three targets. |
| `apps/android/` | Kotlin + Compose. Gradle with a version catalog, four modules. |
| `apps/desktop-*/` | Planning documents only. **No code.** See [ADR-0004](docs/decisions/0004-desktop-strategy.md). |
| `packages/design-tokens/` | OKLCH token source → generated Swift and Kotlin. |
| `packages/test-fixtures/` | Shared publication corpus. Both suites assert against it. |
| `docs/decisions/` | ADRs. Read 0001 before proposing any architecture change. |
| `docs/design/DESIGN.md` | The design system: what the tokens mean and what is forbidden. |

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
   `openspec/specs/<capability>/spec.md` before it is built. If the behaviour you
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
| `apps/ios` app target or `project.yml` | `pnpm build:ios` |
| One Android module | `cd apps/android && ./gradlew :<module>:lint :<module>:testDebugUnitTest` |
| Android across modules | `pnpm lint:android && pnpm test:android` |
| `packages/design-tokens` | `pnpm tokens:sync` — then **commit the regenerated app copies in the same change** |
| `openspec/specs` | `pnpm spec:validate` |

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
  and run `xcodegen generate`. Never hand-edit the project.
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

## 8. Commits

Conventional commits, scoped by area: `feat(ios):`, `fix(android):`,
`docs(specs):`, `chore(tokens):`.

**Never add AI attribution** — no `Co-Authored-By`, no "Generated with", no
equivalent, in commits, PR titles or bodies, reviews, or issues.

Do not commit, push, tag, or open a PR unless explicitly asked.
