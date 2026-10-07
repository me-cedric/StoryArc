## Why

StoryArc reads on a phone. A reader who sits at a desk, or who keeps a library on a NAS next to the
desktop, has no native reader there. On 2026-10-07 the owner decided that desktop work starts now,
in parallel with the mobile apps.

The audit of the 17 capability specs (`docs/delivery/desktop-parity-2026-10-07.md`) shows the
contract already holds on a desktop. Of 95 requirements, 60 to 64 hold as written, 25 to 27 need a
desktop reading, 4 to 6 lose some scenarios, and 2 are mobile only. What is missing is the behaviour
a desktop adds: windows, menus, keys, a pointer, files dropped on the app, and a screen reader on
each operating system. Nothing describes it, so nothing can be built or tested against it.

This change is **wave 0, a preparation wave**. It documents, researches, audits and plans. It puts
a small build base in place. It implements no feature.

## What Changes

- **One new capability, `desktop-experience`,** states what a reader sees and does on a desktop:
  the native interface per operating system, the window model, menus and shortcuts, pointer and
  keyboard reading, drag and drop, file associations, the desktop reading of each mobile term, the
  Linux display servers, and operating-system integration of covers and recent items.
- **Three desktop clients are planned, each native.** macOS, Windows and Linux each get their own
  interface in the platform's own toolkit. The two Rust-based clients share one interface-free core
  of non-visual logic. macOS keeps using the logic the iOS app already has.
- **A plan for waves 1 to 6** in `tasks.md`: test-first, grouped into lanes that up to four agents
  can run on disjoint files. Every requirement the audit marked as inherited, reinterpreted or
  partial has a task or a named deferral.
- **A build base, written by other tasks in this wave.** Empty projects that compile, a Rust
  workspace with one exported function, three CI workflows filtered by path, and a build-from-source
  guide. They show the toolchains work. They show no reader.
- **A `Desktop` section in `docs/openspec/STATUS.md`,** one row per target, each marked base only.
- **No existing requirement changes.** The delta holds `ADDED` requirements only, so nothing
  collides with the mobile changes in flight.
  One scenario waits on the owner: the default of the edge click zones (task 1.26). Its answer is
  stated in the delta as holding on a desktop only, and it modifies no requirement text.

## Capabilities

### New Capabilities

- `desktop-experience`: the behaviour a reader gets on macOS, Windows and Linux that the two mobile
  apps do not have, and the reading of mobile terms on a desktop. It applies to all three desktop
  platforms unless a requirement names one.

### Modified Capabilities

None. The 17 main specs hold on a desktop as written or through the readings recorded in
`desktop-experience`. The audit lists the classification of each requirement per platform.

## Impact

**Platforms.** macOS, Windows and Linux are new. iOS and Android are not affected: no file under
`apps/ios` or `apps/android` changes, and mobile CI does not run on a desktop-only change.

**New directories.** `apps/desktop-macos`, `apps/desktop-windows`, `apps/desktop-linux`,
`apps/desktop-core`, and a root Rust workspace. Three new CI workflows, `desktop-macos.yml`,
`desktop-linux.yml` and `desktop-windows.yml`, each filtered to its own paths.

**Dependencies.** The macOS project consumes `apps/ios/Packages/StoryArcKit` by path and does not
modify it. The Rust core and the C# and GTK interfaces add third-party dependencies. `design.md`
names each with its version and licence.

**Decisions.** ADR-0018 settles the stack and supersedes ADR-0004 on timing. `design.md` records
the research answers.

**Contract that stays binding on every desktop.** No cross-platform interface layer. No backend, no
analytics, no crash reporting. Offline is a normal state, drawn grey and never red. Secrets live
only in the platform secure store. The artwork is the interface.

## Non-goals

- **No feature code in wave 0.** The base compiles and does nothing a reader can use.
- **No cross-platform interface.** Each desktop draws its own interface. Only non-visual logic is
  shared, and only between Windows and Linux.
- **No change to the mobile apps,** to their specs, or to their CI.
- **No change to a main spec.** Mobile-only requirements stay as they are. The desktop drops are
  recorded in the audit, not by editing a spec.
- **No signed or published build.** Apple notarisation, the Microsoft Store listing, Flathub
  submission and Windows code signing need decisions and accounts the owner holds. They are
  recorded as open questions in `design.md`.
- **No desktop widgets, tray icon, background sync, notifications, command palette, reader tabs,
  printing or global hotkeys.** The audit rejects each one for now.
- **No app icon chooser on a desktop.** No supported way to switch the icon and keep it exists on
  the three platforms.
