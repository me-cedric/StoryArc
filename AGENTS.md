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
test fixtures — and nothing else. Desktop clients are in preparation
([ADR-0018](docs/decisions/0018-desktop-clients.md)): macOS reuses the iOS
packages, and Windows and Linux share one Rust core with no UI in it.

| Path | What lives there |
| --- | --- |
| `docs/openspec/specs/` | **The contract.** 17 capability specs describing user-observable behaviour. |
| `docs/openspec/changes/` | In-flight proposals. Created with `/opsx:propose`. |
| `apps/ios/` | Swift + SwiftUI. XcodeGen spec, one SPM package with three targets. |
| `apps/android/` | Kotlin + Compose. Gradle with a version catalog, four modules. |
| `apps/desktop-macos/` | SwiftUI, own XcodeGen project, `StoryArcKit` by path. Base only. [ADR-0018](docs/decisions/0018-desktop-clients.md). |
| `apps/desktop-windows/` | C# + WinUI 3. Base only. Builds on Windows; the interop tests also run on macOS. |
| `apps/desktop-linux/` | Rust + GTK4 + libadwaita. Base only. |
| `apps/desktop-core/` | The Rust core Windows and Linux share (`storyarc-core`, `storyarc-ffi`). **No UI, ever.** |
| `packages/design-tokens/` | OKLCH token source → generated Swift and Kotlin. |
| `packages/test-fixtures/` | Shared publication corpus, **generated then committed**. Both suites read its `manifest.json` and assert the same expectations. |
| `docs/decisions/` | ADRs. Read 0001 before proposing any architecture change. |
| `docs/design.md` | The design system: what the tokens mean and what is forbidden. |

## 2. Non-negotiables

These are product requirements, not preferences. A change that breaks one is
wrong even if it compiles and passes tests.

1. **No cross-platform UI, ever.** Every pixel is the platform's own toolkit:
   SwiftUI, Compose, WinUI 3, or GTK4 with libadwaita. No web
   view, no shared UI abstraction, no cross-platform toolkit — the single
   exception is reflowable EPUB content, which is HTML by definition.
   ([ADR-0001](docs/decisions/0001-independent-native-cores.md))
2. **No backend, no account, no analytics, no crash reporting.** Data leaves the
   device only to sources the user configured.
3. **Offline is a normal state, not an error.** An unreachable source is grey,
   never red. The library stays browsable; downloads stay readable.
4. **Secrets go to the platform secure store.** Never preferences, logs,
   backups, or diagnostics. Redact before any string leaves memory. One
   exception: a library export the reader asked to carry secrets holds each
   secret sealed under the reader's passphrase, never in clear
   (`library-portability`, *Secrets travel only sealed, and only when asked*).
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

**Neither `pnpm test:ios` nor `pnpm build:ios` compiles the UI tests.** `test:ios` runs
`StoryArcKit`'s host suites, then the snapshot tests on a simulator; `build:ios` builds the
app target; `StoryArcUITests` is neither. So roughly three hundred lines of `apps/ios/UITests` — the accessibility audits,
the reader audits, the screenshot captures and the walk they all share — were compiled by
no gate at all, and a syntax error in any of them would have surfaced only when somebody
ran the tests by hand.

Demonstrated rather than assumed: a function returning a `String` from an `Int` signature
was added to `ScreenshotTests.swift`, and `pnpm check` exited **0**. `pnpm build:ios:tests`
exited 65 and named the line. It is in `pnpm check` now, and it costs about thirty seconds.

**A `SIGSEGV` from `pnpm check` is usually a stale build, not a bug — run `pnpm clean:swift`.**
`StoryArcCore` is not built with library evolution, so a non-resilient type's memory layout is
baked into everything that compiled against it. Add a case to an enum like `ReadingPosition`
and an incrementally-rebuilt test target keeps the **old** layout. The symptoms are a test
failing on two values that print identically, then the whole suite ending with

    exited with unexpected signal code 11

and no other output. It is not a defect, not flaky, and not a compiler bug — which is exactly
what it looks like for the first hour, and it cost an agent that hour on 2026-09-01.
`pnpm clean:swift` removes the packages' `.build` directories; the next `pnpm test:ios`
rebuilds from scratch. Distinct from `pnpm clean:builds`, which reclaims disk from worktrees
that are **gone** and is safe to run mid-wave.

**`swift build` warns that `PageCurl.metal` is unhandled, and that warning is correct and
harmless.** SwiftPM does not process `.metal` files in a target's sources, so it says so on
every host build. Xcode does: a built app carries
`StoryArcKit_ReaderFeature.bundle/default.metallib` holding `pageCurl`, and
`StoryArcEpub_EpubReaderFeature.bundle/default.metallib` holding `paperGrain` — checked on
2026-09-05 with `strings` over both. `ShaderLibrary.bundle(.module)` finds them there.
**Do not silence it by declaring the file a resource**: `.process`/`.copy` would put the
*source* in the bundle instead of a compiled library, and the curl would stop rendering with
no warning at all. The right reading is that the host build never uses the shader and Xcode's
does.

**Run `swiftlint` from the repository root, and nowhere else.** `.swiftlint.yml` is at the
root and SwiftLint looks for it in the *working directory*, not upwards from the files it is
given. A run from `apps/ios` finds no config, falls back to SwiftLint's own defaults, and lints
`.build/checkouts` as well — which reported **659 violations in 759 files** against a tree that
has none. It cost three misread gate results in one session before the file count gave it away.
`pnpm lint:ios` is safe because pnpm runs scripts from the root; a hand-run after a `cd` is not.
**If the file count is not what you saw last time, you are measuring a different thing.**

**Do not memorise the number here — read it from the last run.** This line used to name a
figure, and the figure went stale while the sentence beside it told every agent to compare
against it: the tree grew from 611 files to 660 over four days of ordinary work, so an agent
following the rule would have concluded a correct run was measuring the wrong thing. What is
diagnostic is the *jump*, and the jump is unmistakable — a mis-scoped run lints
`.build/checkouts` too, so it reports hundreds of files more and hundreds of violations against
a tree that has none. A handful more files than yesterday is the repository growing.

**A test that fails as though the code cannot write a file was diagnosed wrong twice here, and
the real cause was a data-protection class.** `CoverCacheTests` failed on exactly two of its five
assertions — the two needing a *successful* store, with `cache.image(for:) → nil` — while the
three asserting *absence* passed, because those pass vacuously when nothing was written.

The cause: `CoverCache` and `DownloadStore` set `FileProtectionType.completeUnlessOpen` on their
directories. **Data protection is an iOS facility, and `StoryArcKit` builds for macOS so the pure
targets can be host-tested.** On macOS the attribute *is* accepted — `attributesOfItem` reads back
`NSFileProtectionCompleteUnlessOpen` — and the file written under it then cannot be read by the
process that just wrote it: `CGImageDestinationFinalize` returns `true`, and both
`Data(contentsOf:)` and `CGImageSourceCreateImageAtIndex` fail. Isolated by four trials differing
in one variable; both stores now apply it under `#if os(iOS)`, and the tests assert its *absence*
on the host so the guard is pinned from both sides.

**Two wrong diagnoses came first, and each appeared to be confirmed.** The volume was at 100% with
1.2 GB free, so it was called a full disk; clearing 15 GB "fixed" it. Then it recurred, and a
`pnpm clean:swift` "fixed" it. Both were coincidences — the runs that passed were a different
checkout and a differently-timed one. **When a symptom is intermittent, a fix that appears to work
once has proved nothing. Change one variable, and keep the trial that isolates it.**

**The `SIGSEGV` above is still a real and separate failure**, with its own evidence: it was an
enum layout baked into an incrementally-rebuilt target. Do not read the two as one symptom.

**The disk is still worth watching before a wave, for its own reasons.** Four parallel worktrees
cost roughly 700 MB each in the checkout and 2 GB each in DerivedData, and `ModuleCache.noindex`
reached **15 GB** on its own. `pnpm clean:builds` reports every shared cache's size and the free
space and warns when a wave will not fit; it does not remove the caches, because they belong to
no project and rebuild themselves. `pnpm clean:builds:caches` is the lever when the space is what
you need, at the cost of a few minutes on the next build.

**Android had the identical hole, and it has already cost this project.** `pnpm test:android`
runs `test`, which is the JVM unit tests; the sixteen files under `src/androidTest` are
instrumented and compiled by neither that nor `lint`. This is how `ProgressStoreTest` came to
sit uncompiled for months with nineteen positional call sites binding the wrong parameter — a
suite that appeared to cover the app's most consequential behaviour and ran nothing. It was
found by accident.

Proven the same way: a `String` returned from an `Int` signature in
`core/persistence/src/androidTest/.../LibraryPreferencesTest.kt` left `pnpm test:android` at
exit **0**, and `assembleAndroidTest` exited 1 and named the line. `pnpm build:android:tests`
is in `pnpm check` too.

Neither command runs anything. They compile, which is the part that was missing — a test that
does not compile is not a failing test, it is an absent one, and absent is what both platforms
were.

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
| iOS | 26.1 | latest SDK |
| Android | API 31 (Android 12) | API 37 |
| macOS | 26 | latest SDK |
| Windows | 11 24H2 (build 26100) | latest Windows App SDK 2.x |
| Linux | GTK 4.14 + libadwaita 1.5 (Ubuntu 24.04, Pop!_OS 24.04) | the current GNOME runtime |

iOS has **no compatibility shims** — Liquid Glass is used directly. Android has
one conditional, `dynamicColorScheme`, available on every supported version.
([ADR-0003](docs/decisions/0003-platform-floors.md))

## 5. Validation

Use `agent-compass.commands.json`. Run the **smallest set that covers the
change** — never the whole repository when one module moved.

| Changed | Run |
| --- | --- |
| `apps/ios/Packages/StoryArcKit` | `pnpm test:ios:host` (host tests only, no simulator). `pnpm test:ios` runs the host tests, then the snapshot tests (`pnpm snap:ios`) on a simulator |
| `apps/ios/Packages/StoryArcEpub` | `pnpm test:ios:epub` — **needs a booted simulator**, because Readium is iOS-only and `swift test` cannot build this package at all. The script is what CI's `epub` job runs, so the two cannot drift. Keep its `-collect-test-diagnostics never`: without that flag a failure sends `xcodebuild` to collect a sysdiagnose, which times out after 600 seconds and turns a 30-second answer into an 11-minute one. `PublicationEgressTests` guards [ADR-0015](docs/decisions/0015-epub-webview-network-egress.md) and sets the floor at about 13 seconds of testing |
| `packages/test-fixtures` | `pnpm fixtures:build`, then **commit the regenerated corpus and manifest**, then run both platforms' format tests |
| `apps/ios` app target or `project.yml` | `pnpm build:ios` |
| `apps/ios/UITests` | `pnpm build:ios:tests` — **nothing else compiles them** |
| Any `src/androidTest` | `pnpm build:android:tests` — **nothing else compiles them either** |
| One `apps/ios/UITests` class | `xcodebuild test … -only-testing:StoryArcUITests/<Class>`, or `…/<Class>/<test>` for one case. **Scope it.** The whole target is the capture suite as well as the audits, it holds the simulator for minutes, and on 2026-09-07 one run of it hung for over an hour against a contended simulator. A class takes about twenty seconds |
| One Android module | `pnpm gradle :<module>:lint :<module>:testDebugUnitTest` |
| Android across modules | `pnpm lint:android && pnpm test:android` |
| `packages/design-tokens` | `pnpm tokens:sync` — then **commit the regenerated app copies in the same change** |
| `apps/desktop-macos` | `pnpm build:macos` |
| `apps/desktop-core` | `pnpm test:desktop:core && pnpm lint:desktop` |
| `apps/desktop-linux` | `apps/desktop-linux/scripts/container-build.sh ubuntu-24.04` — the floor distro; `arch`, `manjaro` and `fedora` also work. GTK is not installed on the Mac host |
| `apps/desktop-windows` | `pnpm test:desktop:interop` on any host; the WinUI app builds only on Windows, so its proof is the `desktop-windows` CI workflow |
| `docs/openspec/specs` | `pnpm spec:validate` |
| `docs/openspec/changes` | `pnpm spec:validate && pnpm spec:guard` — validate checks the files that are there, the guard checks the ones that should be |
| A `[~]` partial in a task list | `pnpm partial:tasks` — part of `pnpm lint`. `openspec-guard`'s `taskProgress` counts `- [ ]` and `- [x]` and **nothing else**, so a partial sits in neither the numerator nor the denominator: `audiobooks-and-playback` reports 15/29 where the honest figure is 15 of 51, and `[ready]` fires on the last `[ ]` even with twenty `[~]` open — announcing a change as archivable, which is the one action that is expensive to undo. This prints the three-way count and fails on that shape. The guard is vendored, so it is not edited |
| A `## MODIFIED` delta | `pnpm delta:drop` — part of `pnpm lint`. A MODIFIED requirement replaces the **whole block**, so anything the main spec holds and the delta omits is deleted the moment the change is archived. Neither `validate` nor the guard looks at that, and it has cost this repo three requirements' worth of near-misses. Carry the sentence, or record the removal in `.delta-drops.json` **with its reason** — a stale entry there is itself an error, so the file drains |
| **Two** changes with a `## MODIFIED` delta on one requirement | The same `pnpm delta:drop`. Each delta can be spotless against the main spec and lethal to the other: whichever syncs second replaces the block and takes the first's scenarios with it, after the first change has archived and its delta is gone. Identical blocks are safe in any order and are not reported. Otherwise make the **later** block a superset of the earlier one and record the order in `.delta-drops.json`; an order over a genuinely disjoint pair is refused, because no order saves it. This check was added on 2026-09-04 and found **four** live instances on its first run, one on a requirement that was about to be synced |
| `docs/openspec/config.yaml` | `pnpm spec:guard` — a broken list item makes the CLI report an empty project |
| The `@fission-ai/openspec` version | `pnpm openspec:workflows` then commit the regenerated workflow files |
| Any Swift or Kotlin file | `pnpm lines:check` — part of `pnpm lint`. The 800-line cap is a ratchet. No file is over it now, and the record in `scripts/line-cap.mjs` is empty. A file that crosses the cap fails the build. Split it at a real seam. |

**Scope a test run to what moved, and say why when you cannot.** Section 5 opens with that
rule and the iOS UI target is where it is easiest to break, because one flag is the difference
between twenty seconds and twenty minutes. Use `-only-testing:` with a class, or with a single
case, and name the class from the failure you are chasing rather than from the target it lives in.

**Three files are shared harness, and moving one of them earns a broad run.** They are
`AuditWalk.swift`, `AudiobookWalk.swift` and `SweepWalk.swift`. A change inside them reaches
classes the failure never named, so a scoped run proves nothing about the rest.

`SweepWalk.realCovers` is the sharpest case and is the reason this paragraph exists.
It picks covers by matching `PublicationFormat.displayName`, from a hard-coded list of the
names. Get that list wrong and it matches nothing, every capture class picks **zero covers**,
and every one of them **passes**. On 2026-09-07 the list still held `"Audiobook"` after that
display name had been split into four, and no gate could have said so. A list that names a
string the enum no longer answers is the failure mode; the comment above the list says as much.

The same applies to a view a capture class photographs. Deleting `HomeEmpty` changed what the
first-run walks see, and no audit class touches it.

So: scoped by default. Broad when shared harness or a photographed view moved, and then state
the file that earned it. A broad run nobody asked for and nobody explained is how a simulator
is held for an hour with nothing to show.

**A UI run against an unseeded device proves nothing, and nothing said so.** The suite needs
two seeding steps, in this order, after the app is installed and before the tests run:

```bash
node scripts/corpus.mjs --simulator <udid>      # 17 publications into the app's Documents
node scripts/seed-simulator.mjs --device <udid> # the download records and their files
```

Measured on 2026-09-07 without them: of 107 cases, **42 skipped and 11 failed**, every one of
them downstream of an empty device. The suite reported that as a slow run with some red in it,
which is indistinguishable from a broken app.

**The instruction existed only inside the assertions.** "This device's shelf never showed a
cover for Fine Print", "This device's library showed no EPUB cover at any of the six scroll
depths", and "No audiobook on this device's shelf" each name a remedy, and a person only reads
them after the run has already failed. `corpus.mjs` was in the repository the whole time and
appeared in no document.

Seeding is not sufficient either, and this is unfinished rather than solved. With the corpus
in place `ReaderAuditTests.testEpubReaderPassesTheAudit` passes where it skipped, and
`testReaderPassesTheAudit` still skips with "No publication on this device opens a page with
an action on it". Whatever the comic path needs is not the corpus alone. Nobody has chased it.

**The UI target is 191 cases and 183 app launches, so nearly every case pays a cold
start.** Measured on 2026-09-07: 23.5 seconds a case on average, about **75 minutes** for the
whole target. `AccessibilityAuditTests.testSettingsPassesTheAudit` alone took 124 seconds, and
four `AppIconCaptureTests` cases took about 97 seconds each.

The launches are structural rather than careless. `sweepLaunch` injects a different set of
launch arguments per case — appearance, downloads, filters, recents — and a launch argument
can only be set before a launch, so a case needing different state must relaunch. That is
what makes each capture a photograph of a known state instead of whatever the case before it
left behind.

**The waste is that many cases pass the same arguments.** Grouping cases by their launch
argument signature and launching once per group would collapse most of the 183. Nobody has
done it, and it is a refactor of the capture suite rather than a tweak. Until then, read the
per-case seconds in a run before assuming a slow suite is a hung one: watching the same
opening walk repeat is the suite working, not the suite stuck.

**A guard you add must be proved able to fail, in the same change that adds it.** Three
checks in this repository could not fail, and each looked exactly like protection:

- `NoSegmentedButtonsTest`'s retired-spelling list caught four spellings and not a bare
  `import androidx.compose.material3.SegmentedButton` — which is the residue its own change
  had to clean by hand.
- `AppIconManifestTest`'s foreground assertion accepted either the coloured art or the flat
  art, and every mipmap carries the flat art in its `<monochrome>` element, so the second half
  of the disjunction was satisfied for all five faces whatever the `<foreground>` said. Not
  permissive: **vacuous**.
- `delta-drop-check.mjs` itself was written from an incident it could not detect, because it
  compared each delta against the main spec and never against a sibling delta.

Two of the three were found by verification passes months of gate runs would never have
found, because a check that always passes is indistinguishable from a codebase that is clean.
So: mutate the thing the check protects, watch the check fail **by name**, and revert. Where
the check is a script, ship the mutation as a `--self-test` — `delta-drop-check.mjs` and
`partial-tasks-check.mjs` both have one, and `pnpm lint` is not where you discover that a
self-test was worth writing.

**Android needs a JDK 21 and an SDK, and neither is on the path by default.**
`pnpm gradle <task>` (and `pnpm lint:android` / `test:android` / `build:android`) find
both, and write the gitignored `apps/android/local.properties` a fresh worktree lacks —
`scripts/gradle.mjs` says where it looks. A bare `./gradlew` still needs `JAVA_HOME`
exported, because the wrapper needs a JVM before it can read any property file. Homebrew's
JDKs are keg-only and macOS ships a `/usr/bin/java` stub that reports no runtime and
shadows them, so "Unable to locate a Java Runtime" means the path, never a missing install.

### Keep CI green at the source

The pre-push hook runs `pnpm lint`, which checks the contract only. The iOS and Android
gates run in CI, so a push can be red with a clean hook. From 2026-10-07 to 2026-10-10,
main was red on both platforms. Each rule below comes from one of those failures.

1. **Run the gate of each platform you changed before you push.** For `apps/ios`, run
   `pnpm build:ios:tests` and the `-only-testing:` run of each UI class you touched. For
   `apps/android`, run `pnpm test:android`. Run `connectedDebugAndroidTest` when you
   changed a `src/androidTest` file or code that one of those tests uses.
2. **Run instrumented tests on the API level of CI.** CI uses API 36
   (`.github/workflows/android.yml`). A local API 35 emulator hid a product defect: the
   speech engine binds later on API 36, and the voice stayed silent after a call
   (d680fcac9). Use the API 36 image, one emulator at a time.
3. **Wait for a condition, never for a fixed time.** A runner is slower than your Mac.
   A fixed half second after a page turn failed on CI (a2a97e7be). On Android,
   `waitForIdle` does not wait for work on `Dispatchers.IO`. Use `waitUntil` with the
   condition (36b39c1e9, 4e0112467). On iOS, use `waitForExistence` or an expectation.
4. **Fix the product when a test exposes a race.** "Constructed" is not "ready". A
   `TextToSpeech` object exists before its engine binds. Do not make the test slower to
   hide the gap. Make the product wait for the ready signal (d680fcac9).
5. **Make each UI walk work at the default size and at the largest size.** Do not scroll
   through one element type, such as `app.scrollViews.firstMatch`. The type changes with
   the layout and the text size. Swipe the app with `app.swipeUp()` (ee82bb00e). Tap a
   control only when it is hittable, because the reader chrome hides after four seconds
   (987300eae).
6. **Keep each Swift expression cheap to type-check.** An expression that compiles on a
   Mac can time out on the runner (db148c5a6). Build long chains in steps with typed
   constants. To find slow expressions, build with
   `-Xfrontend -warn-long-expression-type-checking=25`.
7. **Declare in `project.yml` every module that a target imports.** An undeclared module
   can link in an incremental local build and fail in the clean CI build (db148c5a6).
8. **Give each test its own state.** Do not share a player, a store, or a device setting
   with another test. CI runs the tests in a fixed order on one device. A test that passes
   alone can fail after another test (0ca24cd15). `pnpm test:ios:ci --list` prints the
   CI order.
9. **Check the CI run of each push, and fix a red main first.** Watch it with
   `gh run watch <id> --exit-status`. When main is red, stop new work and fix the cause.
   Do not retry, skip, or loosen the test to get green. A test that fails "now and then"
   is a defect: record the run ID and fix it. Read the failing test name in the result
   bundle or in the `android-instrumented-reports` artifact.

Two local traps make a false failure. Both happened on 2026-10-10:

- This Mac has an "iPhone 17 Pro" simulator on more than one runtime. Give the same UDID
  to `scripts/install-and-seed-simulator.mjs` and to `xcodebuild`. If you do not, the test
  runs on a device that has no seed.
- A compile error that the source contradicts comes from a stale `.build/ios-ui`. Delete
  that folder and build again.

A task is not complete until you report changed files, the exact commands you
ran, the result of each, whether a failure is pre-existing or introduced, and
the remaining risks. See the Completion Gate in the compass contract.

## 6. Visual proof

**A change a user can see is looked at, and checked against the Apple Human Interface
Guidelines and Material 3, by the one who made it, before it lands.** The owner set this
rule on 2026-10-09 (change `lighter-visual-check`): a frames phase after each merge cost
2 to 5 hours a wave. Use the cheapest check that shows the screen as a reader sees it.
Every tool here is free and open source; use nothing paid.

**1. Look at your own screen while you build.** After a UI change, look at the screen in
light and dark, at the default text size, and fix what is wrong before you commit:

- **Snapshot tests first** (`pnpm snap:ios`, `pnpm snap:android`). They draw each screen
  state with fixture data in seconds: swift-snapshot-testing on a booted iOS simulator,
  Roborazzi on Robolectric for Android, with no emulator. Open the PNG and look at it. A
  changed image fails the test until you record it again (`pnpm snap:ios:record`,
  `pnpm snap:android:record`) — record only after you looked.
- **The running app where a snapshot cannot show it**: navigation, system materials (Liquid
  Glass over content), insets, system interface (shade, widgets, CarPlay), and the content of
  a web view. Drive it with **agent-device** (Callstack, MIT), pinned in `pnpm device`:
  `pnpm device open com.mecedric.storyarc --platform ios --udid <lane simulator> --session
  <lane> --foreground` prints an accessibility snapshot with `@refs`; `settings appearance
  dark` (and `light`) switches the appearance, `settings animations off` lets a screen settle;
  then `press @e12
  --settle`, `scroll down --until <selector>`, `snapshot -i` (element bounds, for hit sizes),
  `screenshot /tmp/<lane>/<screen>-light.png`, and `close`. Android uses
  `com.mecedric.storyarc.debug --platform android --serial <emulator>`. It claims the device
  for your worktree, so parallel lanes do not take each other's. `.mcp.json` exposes the same
  commands as MCP tools. Without it, `xcrun simctl io <id> screenshot` and
  `adb exec-out screencap -p`.
- **One emulator at a time** on this machine. A snapshot needs none.

**What to check in each image.** Each of these is a fault, not a remark, so fix it or
record it as a task:

- A hit target under 44 x 44 pt (iOS) or 48 x 48 dp (Android), or two Android targets
  less than 8 dp apart.
- **Two or more related actions drawn side by side or stacked** (for example up, down,
  edit and delete on a row). They become one menu (`Menu`, `DropdownMenu`) or a
  platform pattern (swipe actions, a drag handle to reorder). A row whose title wraps
  because its actions take the width is this fault, even when each target passes.
- A destructive action that is not last, alone, in the destructive style, and confirmed
  (unless it can be undone).
- Text under 4.5:1 against what is behind it (3:1 for large text), in light or dark.
- Clipped, truncated or one-letter-per-line text; content under a bar or outside the
  safe area.
- A look-alike of a system component (a hand-made menu, sheet, alert or switch).
- A control in the other platform's idiom: a Material tonal capsule on iOS, a glass or
  iOS-style control on Android. On iOS 26, a close action is a `Button(role: .close)`; a
  secondary action is borderless or `.glass`, not a tinted capsule beside plain text.
- A larger hit region that changed the drawn size of a control. The touch area grows; the
  capsule, the chip or the icon keeps its system size.
- A screen that is wrong in one appearance only.

**2. Machines check the guidelines.** The accessibility checks run over every screen of
`docs/designs/screen-catalogue.md`: `performAccessibilityAudit` in the iOS UI tests
(`CatalogueAuditTests`), and the `:core:snapshots` checks of the Compose semantics tree in the
Android Robolectric tests. On Android, a target under 48 dp, a contrast failure or a missing
label fails the test. On iOS, a target under 44 pt, a missing label or a contrast finding on
an element that the audit names fails the test. A contrast finding on an element that a bar
covers or the window cuts is printed. Clipped text and Dynamic Type findings are printed, not
failed. A contrast fault that stands for now goes in `knownContrastFaults`
(`apps/ios/UITests/CatalogueVerdict.swift`) with its reason, and a steady entry that no longer
occurs fails the test. `pnpm test:ios:audit` runs the iOS audit on a local simulator with the
seed and the corpus. The iOS workflow runs it in the step *Catalogue audit*.
`pnpm tokens:check` holds the palette pairs to 4.5:1. `close-the-audited-gaps` 28.7 holds
the one open gap (`lighter-visual-check` is archived). **A new screen adds its catalogue entry**: a snapshot test in light and
dark, and an audit.

**3. Commit no screenshot by default.** A snapshot reference is the proof for a screen
state. For a screen that a snapshot cannot draw, take the screenshots in `.build/screens/`
(git ignores it), look at them, then delete them. Write `Visual-proof: checked` in the
commit message. The owner asked for this on 2026-10-10, after `docs/designs/screenshots/`
reached 1,645 images and 476 MB.

- Delete a screenshot run when its check ends: `rm -rf .build/screens/<run>`. Do this in
  the same turn, also when the check failed.
- Commit a screenshot only when a lasting document shows it: the README, an ADR, a design
  document, `docs/mvp-device-checklist.md` or `docs/openspec/STATUS.md`. Then commit one
  light and one dark image of the screen, downscaled with `pnpm frames:shrink`.
- Never commit a sweep, a dated proof folder, or one image for each task. A task cites its
  snapshot test or its commit, not an image.

The largest text size, all four languages and the guideline checks are not committed as
frames. The snapshot tests and the audits cover them. Both platforms draw each catalogue
screen in light at the largest text size too (iOS `<NN>-<name>.largest.png` at AX5, Android
`<NN>-<name>-largest.png` at font scale 2.0); look at that image too.

`pnpm preview:proof` is the gate, and `pnpm lint` runs it at pre-push. It refuses a branch
that adds a line inside a `View` or a `@Composable` and adds neither a frame under
`docs/designs/screenshots/` nor a snapshot reference (`__Snapshots__/` on iOS,
`src/test/snapshots/` on Android). Three markers, named in a commit message on the branch:
`Visual-proof: flag` (code behind a flag that nothing renders yet), `Visual-proof:
identical` (a pure refactor whose snapshots or screenshots are byte-identical) and
`Visual-proof: checked` (a screen checked on a simulator or a device, with the screenshots
deleted after the check). It reads
added lines only, cuts out every preview block, and stays quiet on a comment, an import or
a test source. `scripts/preview-proof-check.mjs` says why each of those is deliberate.

A SwiftUI `#Preview` and a Compose `@Preview` are development aids, not proof: neither runs
in the test suite with fixture data.

**`docs/designs/screenshots/` keeps only what a lasting document shows.** On 2026-10-10 it
went from 1,645 images (476 MB) to 128 images (42 MB). The snapshot references are the
baseline now, not a sweep. When a lasting document stops showing an image, delete the image
in the same commit. Task lists and archived changes still name some removed images; the
folder's README says how to get one back from git history. Never commit an archive of
screenshots: a 242 MB `Archive.zip` was staged once and caught before it landed.

**A screenshot that could look the same for a boring reason needs a control.**
The EPUB reader's chrome photographed in cream proves nothing on its own — the
app might simply not have been set to a dark appearance. The same device, at the
same moment, with the library drawn true black beside it, is what turns the first
picture into evidence. Capture the control whenever the claim is *this screen
disagrees with the rest of the app*.

## 7. Things that will bite you

### Every fixture port, in one table

A mock server is chosen by a port, and two suites decide whether to run by opening a socket
on theirs. So a second fixture on a claimed port does not clash — it is *answered*, and the
suite runs against the wrong server. Measured on 2026-09-12: a mock OPDS catalogue was put on
4445, `SmbClientTest.isServerRunning()` opened a socket, found it, and six SMB cases ran
against a catalogue and failed with "Failed to connect" about a server that was listening.

Take the next free number, and add the row here in the same commit.

| Port | Fixture | Started by |
| --- | --- | --- |
| 4444 | OPDS catalogue, the first one | `node scripts/opds-server.mjs <corpus> --port 4444` |
| 4445 | SMB share, signed and unencrypted | `scripts/smb-server.sh` |
| 4446 | SMB share, `smb encrypt = required` | `scripts/smb-server.sh --encrypted` |
| 4447 | OPDS catalogue, the second one | `node scripts/opds-server.mjs <corpus> --port 4447` |
| 4448 | SMB share with a writable `Sync` share, signed and unencrypted | `scripts/smb-server.sh --writable` |
| 4449 | SMB share with a writable `Sync` share, `smb encrypt = required` | `scripts/smb-server.sh --writable --encrypted` |
| 4999 | Nothing, by design — a refused connection is what *Not answering* means | nobody |
| 5000 | Kavita server | `node scripts/kavita-server.mjs <corpus>` |
| 5001 | Kavita server, for the UI walks that add one through the real form | `node scripts/kavita-server.mjs <corpus> --port 5001` |

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

- **`agent-compass` sync can disable a gate silently.** On 2026-09-07 it created a
  top-level `commitlint.config.js` beside `commitlint.config.mjs`. cosmiconfig takes the
  first match, and `.js` wins, so our `scope-enum` rule went quiet: `feat(bogus): x` passed.
  It also wrote a `tsconfig.base.json` that is invalid JSON, into a repository with no
  TypeScript. Both files were deleted. `pnpm commitlint:guard` now asserts the scope list is
  in force, by behaviour rather than by filename. **After any sync, run `pnpm lint` before
  you believe the sync.** The sync also reports a file as an upstream conflict when the lock
  simply has no hash for it; nine files were reported on 2026-09-07 and upstream had changed
  none of them.

## 8. Commits

Conventional commits, scoped by area: `feat(ios):`, `fix(android):`,
`docs(specs):`, `chore(tokens):`.

**Never add AI attribution** — no `Co-Authored-By`, no "Generated with", no
equivalent, in commits, PR titles or bodies, reviews, or issues.

Do not commit, push, tag, or open a PR unless explicitly asked.

A change that a reader of the app notices adds one line to `RELEASE_NOTES.md` in the same
commit. Section 10 gives the rules.

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

## 10. Releases

**"Make a new release" means all of this, in this order, and nothing less.** It is one
command, because every step after the first is a place a manual release forgets something.

```bash
pnpm release patch        # or minor, or major, or an explicit 0.4.0
```

That command, and then the tag it pushes, produce:

1. the new `versionName` and `versionCode` written into `apps/android/gradle.properties`,
   the version into `package.json`, and the `## Unreleased` notes of `RELEASE_NOTES.md`
   filed under the new version, all committed as `chore(release): vX.Y.Z`
2. a `vX.Y.Z` tag, pushed with the branch
3. a signed App Bundle **and** a signed APK, built once by
   [`android-release.yml`](.github/workflows/android-release.yml) from that commit
4. a GitHub release on the tag, carrying the APK, with the notes of that version as its text
5. that bundle on Play's **internal testing** track, rolled out to the internal testers, with
   the same notes as "What's new". Internal testing normally skips Play's review and reaches
   the testers in minutes.

**The rules that bind you:**

- **`apps/android/gradle.properties` is the only place a version lives, and
  `scripts/release.mjs` is the only thing that edits it.** Do not hand-edit either version
  field and do not pass `-PversionName` in a lane that publishes. A version typed twice is a
  version that disagrees with itself.
- **The version code only ever goes up.** Play refuses a code it has already accepted, and
  it refuses it after the build has run. Never reuse or lower one, even for a release that
  failed — cut the next one instead.
- **Never build or sign a release locally.** The upload keystore and the Play service
  account are repository secrets and have no copy on this machine. A release that was not
  built by CI is not a release.
- **Ask before you release.** A release is outward-facing and a tag is hard to withdraw.
  Cut one only when asked for one outright; §8's "do not commit, push, or tag unless asked"
  is not suspended here, it is the reason this section is explicit.
- **Promotion stays a separate, deliberate act, and the owner decides it.** This lane stops
  at internal testing. The owner promotes the build to closed testing (`alpha`), then to
  production, in the Play Console. When the owner asks you to promote, run
  [`android-promote.yml`](.github/workflows/android-promote.yml). It reuses the artefact and
  rebuilds nothing, so the bytes testers approved are the bytes production gets. The notes
  travel with the release. A promotion to `alpha`, `beta` or `production` sends the build
  for review. Never promote without the owner's request.

  ```bash
  gh workflow run android-promote.yml -f versionCode=<code> -f from=internal -f to=alpha
  ```

**Keep the reader's notes as you work.** `RELEASE_NOTES.md` is what Play shows as "What's
new" and what the GitHub release says. `CHANGELOG.md` is the record for developers; the
notes are for readers.

- **Write the line in the same commit as the change.** Each change that a reader notices
  adds one line under `## Unreleased`: a feature, a fix of a visible defect, a changed
  behaviour. A refactor, a test, a CI or a docs change adds nothing.
- **Write for a reader, not a developer.** One short sentence for each line, starting with
  `- `. Say what the reader can do now or what works now. Do not name files, modules,
  libraries, tests, task numbers or platforms' internals.
- **Write each line in the four languages of the Play listing.** `### en-US`, `### de-DE`,
  `### es-ES` and `### fr-FR` under `## Unreleased`, the same lines in the same order. Use
  the app's own words for a feature: its `strings.xml` in `values`, `values-de`, `values-es`
  and `values-fr`. `LANGUAGES` in `scripts/release.mjs` lists the languages; change it when
  the listing changes.
- **Describe the Android app.** Only it ships today. Leave out a change that only iOS or a
  desktop app has.
- **Keep the section short.** Play takes at most 500 characters in each language. Merge
  small fixes into one line, such as "- Fixes for reading and playback."
- **`pnpm release` checks this.** It refuses a language with no notes and notes over 500
  characters, before it changes anything. Then it files the section under the version.

**Check the result, do not assume it.** The lane can fail after the tag is pushed —
a rejected version code, an expired key.

```bash
gh run watch --exit-status        # while it runs
gh release view v0.2.0            # the APK is attached, or it is not
```

**iOS is not wired into this yet.** `pnpm release` touches the Android version only. Do not
claim a release covers iOS.

**Store listing.** The listing is the texts, screenshots, feature graphic and icon that the
stores show. Updating it is outward-facing, so the owner decides it, as with a release.

- **Run `pnpm store:publish` only when the owner asks.** It checks the files, zips them,
  attaches the zip to the draft release `store-assets` and starts `android-listing.yml` with
  `validateOnly=true`. Play validates the listing and changes nothing. `pnpm store:publish
  --dry` checks and zips, and sends nothing.
- **Use `--publish` only when the owner asks for it outright.** It starts the same workflow
  with `validateOnly=false`. Play then shows the new listing to everyone.
- **The App Store takes two steps.** `pnpm store:publish --platform appstore` writes and
  zips the layout, then stops. `--upload` starts `ios-listing.yml` with `upload=true`, which
  writes the texts and screenshots to the editable version. Without it, the workflow only
  proves that the key works. It never submits for review and never uploads a binary.
- **The inputs are files on this Mac.** The texts are `docs/designs/store/{android,ios}/listing/*.md`.
  The images are in `.build/store/`, where the screenshot run writes them. The script refuses
  a text over its store limit and an image of the wrong size, and it names the language and
  the field. Fix the file and run it again. `pnpm store:publish:selftest` proves the checks.
- **The store keys never come to this Mac.** Both workflows run in CI and shred the key.
  The owner sets up two things once. For Play, the service account of
  `PLAY_SERVICE_ACCOUNT_JSON` needs the Play Console permission to edit the store listing.
  For the App Store, the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`
  hold an App Store Connect API key with the App Manager role. The workflow stops with a
  message when one is missing.
- **`android-listing.yml` needs a track that already holds a release.** Its default is
  `internal`. `supply` looks for a release even when it uploads only a listing.
