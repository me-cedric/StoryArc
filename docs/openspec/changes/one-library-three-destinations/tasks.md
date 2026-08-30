# Tasks

Ordered so that the two things that block everything else — the Android
navigation rewrite and the iOS shell — are answered first, and so that no two
tasks in the same phase write the same file. The slice letters in brackets are
[`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md) §7.1.

**Every task that changes a screen owes a screenshot from a booted simulator or
emulator** — light and dark, default and largest text size — per
[AGENTS.md §6](../../../../AGENTS.md). A SwiftUI `#Preview` or a Compose
`@Preview` is not proof. Put them beside the before set in
`docs/designs/screenshots/`.

## Phase 0 — Answer before building

- [ ] **0.1** Settle whether the iOS search role expands into a field in place.
      Build a throwaway four-destination shell, tap it, screenshot. Deliverable: a
      screenshot and a go/no-go on the fallback named in `design.md`.
- [ ] **0.2** Confirm `androidx.compose.material3.adaptive` 1.3.0 resolves
      alongside `material3 1.5.0-alpha26`, and that `TopSearchBar`,
      `ExpandedFullScreenContainedSearchBar`, `WideNavigationRail` and
      `MediumFlexibleTopAppBar` are reachable without an experimental opt-in
      spreading past `:core:designsystem`. Deliverable: a resolved dependency
      graph, or the alpha that does resolve. **Version-catalogue edits belong to
      its owner** — this task reports, it does not commit the bump.
- [ ] **0.3** Confirm the availability projection can be computed from the
      download record plus the local-file case for every source type, with no
      source consulted. Deliverable: a host unit test that answers it for one
      publication of each type with the network off.

## Phase 1 — The shells

- [ ] **1.1** **[C] Android navigation rewrite.** Replace the boolean cascade in
      `MainActivity.kt` with a typed navigation graph and `NavigationSuiteScaffold`
      carrying the three destinations. Per-destination back history, per-destination
      state restoration, predictive back preserved. `MainActivity.kt` ends under
      800 lines. Screenshot: each destination, phone and tablet.
- [ ] **1.2** **[D] iOS shell.** `TabView` with three `Tab`s, the search role,
      `.tabViewStyle(.sidebarAdaptable)` and the minimize behaviour, around the
      existing library view. Settings and add-source leave the library toolbar.
      Screenshot: each destination, iPhone and iPad, portrait and landscape.
- [ ] **1.3** Verify against the delta that the destination count does not change
      when a source is added, renamed, reordered or removed. A test with nine
      configured sources, on both platforms.

## Phase 2 — What the destinations hold

- [ ] **2.1** **[E1/E2] Home**, both platforms: Keep reading, Up next, recently
      added, pinned shelves, finished. Assembled from local history alone.
      Screenshot: all three degradations — carousel, single card, and Home as the
      empty state.
- [ ] **2.2** Test that Home renders complete and unchanged with every source
      unreachable, and that no shelf appears, reorders or grows when a slow source
      answers. This is the property most likely to regress silently, so it is a
      test rather than an inspection.
- [ ] **2.3** **[I1/I2] The on-device destination**, both platforms. Downloads
      content leaves the settings modal; the queue becomes a pinned section that is
      absent when nothing is in flight; storage limits and network policy stay in
      settings. Screenshot: with a queue in flight, with none, and empty.
- [ ] **2.4** Delete the per-source destinations and the server chip strip above
      the shelf on both platforms, and delete the source line under a cover.
      Screenshot: the library with two sources configured, before and after.

## Phase 3 — The availability axis

- [ ] **3.1** The availability projection, both platforms, with the host tests
      from 0.3 extended to the whole library.
- [ ] **3.2** **[G1/G2]** The library's primary scope becomes availability. The
      by-library filter lands in the same commit as the removal of the source
      scope, so no reader loses per-source browse between one build and the next.
      Screenshot: everywhere, on-this-device, and the filter sheet.
- [ ] **3.3** The on-device mark on a cover, and dimming for a publication that is
      neither downloaded nor reachable — with the accessibility label carrying the
      fact, not the opacity. Screenshot: a grid with all four combinations of
      progress and availability.
- [ ] **3.4** Section headings in a long library, by series where declared and by
      the sort key otherwise. Screenshot: a library of at least 200 publications.
- [ ] **3.5** Wire the iOS views that are already written, translated and
      unreachable — recent searches, the cached notice, the scope control in its
      new availability form, and file import from the empty state. No new strings.

## Phase 4 — Large screens

- [ ] **4.1** **[K1]** iPad: the sidebar's sections and shelves, with no source
      entry; shelves touching the leading and trailing edges; the settings measure
      capped. Screenshot: iPad Pro portrait and landscape, and in Split View.
- [ ] **4.2** **[K2]** Android: Material's five breakpoints replacing the
      two-valued window class, the collapsed and expanded rail, and the two-pane
      scaffold. Screenshot: compact, medium and expanded, and a foldable half-open.
- [ ] **4.3** Verify the resize path: a two-pane window narrowed to one pane keeps
      what the reader was looking at, and widening restores the second pane.

## Phase 5 — First run and the empty path

- [ ] **5.1** **[M1/M2]** The first-run empty state on both platforms: one
      sentence, one action that opens a comic with no configuration, one plain
      secondary. The four source types move one level down. Screenshot: first
      launch, both platforms, largest text size.
- [ ] **5.2** Every empty state in the three destinations, checked against the
      delta's rule that an empty section is absent rather than rendered empty.

## Phase 6 — Gates

- [ ] **6.1** `corepack pnpm spec:validate`.
- [ ] **6.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm build:ios`. No Swift file over 400 lines.
- [ ] **6.3** Android: `./gradlew test lint`. No Kotlin file over 800 lines —
      `MainActivity.kt` and `LibraryScreen.kt` both start over it.
- [ ] **6.4** `corepack pnpm lint`.
- [ ] **6.5** The screenshot set is complete: every task above that changes a
      screen has its light, dark, default-size and largest-size captures beside the
      before set, and the handoff references them.
