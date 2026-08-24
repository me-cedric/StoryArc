---
status: accepted
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0002 — One repository for two independent apps

## Context and problem statement

[ADR-0001](0001-independent-native-cores.md) makes the iOS and Android apps
independent. Independent codebases are a normal reason to use separate
repositories. So why one?

Because the thing they share is the thing that matters most: the *specification*
of the product. If the contract lives in one repository and the implementations
live in two others, the contract goes stale, and there is no single commit that
shows a capability changing on both platforms.

## Considered options

1. Three repositories — the contract in one, each app in its own.
2. One repository with a root build system (Turborepo, Nx or Bazel).
3. One repository with no build-system coupling.

### Three repositories

- Good, because each app clones and builds without the other.
- Bad, because the contract goes stale once it lives away from the code.
- Bad, because no single commit shows a capability changing on both platforms.

### One repository with a root build system

- Good, because one command could build everything.
- Bad, because `apps/ios` and `apps/android` already build standalone with
  `xcodebuild` and `./gradlew`. A root build adds a layer that neither needs.
- Bad, because it would put a Node toolchain in the path of a native build.

### One repository with no build-system coupling

- Good, because the contract, both implementations and the tokens move in one
  reviewable commit.
- Good, because each app keeps its own native build, unchanged.
- Bad, because every clone carries both apps.

## Decision Outcome

One repository. Applications under `apps/`, shared declarative artefacts under
`packages/`, contract under `docs/openspec/`, decisions and design under `docs/`.

```
storyarc/
├── apps/
│   ├── ios/                      Swift + SwiftUI, XcodeGen, SPM modules
│   ├── android/                  Kotlin + Compose, Gradle version catalog
│   ├── desktop-macos/            documented, not implemented
│   ├── desktop-windows/          documented, not implemented
│   └── desktop-linux/            documented, not implemented
├── packages/
│   ├── design-tokens/            OKLCH source → generated Swift + Kotlin
│   └── test-fixtures/            shared publication corpus for both test suites
├── docs/
│   ├── openspec/
│   │   ├── project.md            product context for agents and humans
│   │   ├── specs/<capability>/   15 capability specs — the contract
│   │   └── changes/              in-flight proposals
│   ├── decisions/                ADRs
│   ├── architecture/             per-platform architecture
│   └── design/                   design system and motion
└── scripts/                      cross-cutting tooling
```

**No build-system coupling.** There is no Turborepo, no Nx, no Bazel, and no
root build that knows how to build both apps. `apps/ios` builds with `xcodebuild`
and `apps/android` builds with `./gradlew`, exactly as they would standalone.
The root `package.json` exists only for the token pipeline and spec validation —
a Node toolchain is never required to build either app.

**Independent versioning.** Each app has its own version and its own release
tag: `ios-v1.2.0`, `android-v1.1.0`. The repository is not versioned as a unit,
because the two apps do not ship together.

## Consequences

- One commit can change a capability spec, both implementations, and the design
  token that underpins them — visible as a single reviewable unit.
- CI runs three independent jobs (iOS, Android, contract) and only the affected
  ones on a given change.
- A `git clone` is larger than either app alone. Acceptable; neither app carries
  large binary assets, and the fixture corpus is capped.
- Someone who only wants the Android app still clones the iOS app. Acceptable
  for a project of this size, and the alternative loses the contract.

## Links

- Related decisions: [ADR-0001](0001-independent-native-cores.md) is why the two
  codebases are independent in the first place.
- Layout: `README.md` §Repository layout carries the same tree.
- Contract root: [`docs/openspec/`](../openspec) — the specs the repository
  exists to hold next to the code.
