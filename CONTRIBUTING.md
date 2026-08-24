# Contributing to StoryArc

Thanks for looking. StoryArc is a solo project that welcomes help, and it has
one unusual rule that shapes everything else.

## The rule: specify before you build

**Every behaviour is written down before it is implemented.** The 15 capability
specs in [`docs/openspec/specs/`](docs/openspec/specs) are the contract both apps are
built against — they are what keeps two independent codebases from drifting into
two different products.

If what you want to add is already specified, implement it. If it is not, propose
it first:

```bash
# in Claude Code or Gemini CLI
/opsx:propose "add support for <thing>"
# in Codex
$openspec-propose "add support for <thing>"
```

That produces a proposal, delta specs, a design note and a task list under
`docs/openspec/changes/`. Review it, then implement.

The OpenSpec root is `docs/openspec`. The CLI resolves it from `docs/`, so run
`cd docs` before any `openspec` command, or use the `pnpm spec:*` scripts.

This is not bureaucracy for its own sake. Two native codebases have nothing at
compile time stopping them from diverging; the spec is the only thing that does.

## Setup

```bash
git clone --recurse-submodules https://github.com/me-cedric/StoryArc.git
cd StoryArc
pnpm install
```

| Working on | You need |
| --- | --- |
| iOS | macOS 26+, Xcode 26+, `brew install xcodegen swiftlint` |
| Android | JDK 21, Android SDK platform 37 + build-tools |
| Specs or tokens only | Node 24 and pnpm — no mobile toolchain at all |

## Validation

Run the **smallest set that covers your change**, not the whole repository.

| You changed | Run |
| --- | --- |
| `apps/ios/Packages/StoryArcKit` | `pnpm test:ios` — host only, no simulator |
| iOS app target or `project.yml` | `pnpm build:ios` |
| One Android module | `cd apps/android && ./gradlew :<module>:lint :<module>:testDebugUnitTest` |
| Android across modules | `pnpm lint:android && pnpm test:android` |
| `packages/design-tokens` | `pnpm tokens:sync`, then commit the regenerated app copies |
| `docs/openspec/specs` | `pnpm spec:validate` |
| Not sure | `pnpm check` |

## Things that will bite you

- **iOS:** `StoryArcKit` builds with `InternalImportsByDefault`. Public API
  exposing a Foundation or SwiftUI type needs `public import`.
- **iOS:** `StoryArc.xcodeproj` is generated and gitignored. Edit `project.yml`
  and run `xcodegen generate`. Never hand-edit the project.
- **Android:** AGP 9 compiles Kotlin itself. Do not apply
  `org.jetbrains.kotlin.android`; Kotlin options go in
  `android { kotlin { compilerOptions { } } }`.
- **Tokens are generated.** Never edit `StoryArcTokens.swift` or
  `StoryArcTokens.kt`. Edit `packages/design-tokens/tokens/*.json` and run
  `pnpm tokens:sync`.
- **Contrast is a build gate.** If `pnpm tokens:check` fails, fix the token —
  do not lower the floor.

## Visual proof

**A change a user can see owes a screenshot from a booted simulator or emulator.**

A SwiftUI `#Preview` and a Compose `@Preview` are development aids, not proof.
Neither exercises real data, real safe-area insets, real system materials, or a
real Dynamic Type setting.

```bash
xcrun simctl io booted screenshot shot.png     # iOS
adb exec-out screencap -p > shot.png           # Android
```

Capture **light and dark**, at default and largest text size, and put them in the
pull request.

Two exceptions, and you must name which one applies: code behind a flag that
nothing renders yet, and a pure refactor whose screenshots are byte-identical —
in which case the identical screenshots *are* the proof.

## Tests

Every behaviour change needs one of: an updated nearby test, a focused
regression test, or an explicit statement of why no automated test fits.

The domain layer is UI-free on both platforms specifically so it can be tested
in milliseconds. `ProgressMergeTests.swift` and `ProgressMergeTest.kt` assert the
**same table** from
[ADR-0006](docs/decisions/0006-progress-storage-and-sync.md) — if you change one,
change the other, or the two apps will quietly disagree about where someone
stopped reading.

## Commits and pull requests

Conventional commits, scoped by area:

```
feat(ios): add page-curl gesture recogniser
fix(android): keep reader position through a configuration change
docs(specs): clarify offline behaviour for OPDS pagination
chore(tokens): raise tertiary text contrast on light surfaces
```

Valid scopes: `ios`, `android`, `desktop`, `tokens`, `specs`, `docs`, `ci`,
`repo`, `fixtures`. `commitlint` enforces this on commit.

**No AI attribution.** No `Co-Authored-By`, no "Generated with", no equivalent —
in commits, pull requests, reviews or issues.

Branches: `<type>/<area>/<short-kebab-description>`, e.g.
`feat/ios/page-curl`.

In the pull request, say:

- which capability spec the change implements,
- what you ran and what the result was,
- **the state of the other platform** — implemented, not applicable, or follow-up.

## What will not be accepted

- A cross-platform UI layer, a web view for anything but reflowable EPUB
  content, or a shared UI abstraction. This is the product's central constraint,
  not a preference. See [ADR-0001](docs/decisions/0001-independent-native-cores.md).
- Analytics, crash reporting, telemetry, or any network call to a service the
  user did not configure.
- A colour written as a hex literal in app code.
- Lowering an accessibility floor to make a design work.

## Code of Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
