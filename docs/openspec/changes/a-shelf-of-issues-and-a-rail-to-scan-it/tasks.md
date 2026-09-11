**What a tick means.** The code exists and something asserts it — a JVM unit test,
a Robolectric composition, or an XCTest case. A tick does not mean anybody watched
the screen work; a task that needs a device says so, and stays open until a frame
is committed beside it.

**Where the tests were written after the code, the task says so and names the
mutation that proved the assertion can fail.** Two of the suites below landed with
their implementation rather than before it. A test written afterwards that has
never been seen to fail is indistinguishable from a test that cannot.

## 1. Room to grow, before anything is added

- [x] 1.1 The two files at their caps, recorded before anything moved: `LibraryView.swift` at 397 of 400 and `LibraryScreen.kt` at 799 of 800. `pnpm lines:check` passed at that point and passes now, which is the control for the two lifts below.
- [x] 1.2 `title` and `selectionTitle` lifted out of `LibraryView.swift` into `LibraryTitles.swift`, documentation intact. **`BulkSelectionChromeTest`'s iOS twin failed on the move alone** — it asks whether the navigation bar states the selection and reads `LibraryView.swift` for the answer. The guard now reads both files, so it keeps asking the question it was written to ask. `LibraryView.swift` is 391 lines.
- [x] 1.3 `KavitaSearchOffer` lifted out of `LibraryScreen.kt` into `KavitaSearchOffer.kt`, documentation intact, `private` widened to `internal` because it crossed a file. `:feature:library:compileDebugKotlin` succeeds and `LibraryScreen.kt` is 795 lines.

## 2. The grouping choice exists and is remembered

- [x] 2.1 `LibraryGroupingTest` (4 cases) and `LibraryGroupingTests` (6 cases): an unreadable stored name answers series, every case round-trips through its name, `isCollapsing` is true only for series, and the storage key is neither the availability key nor the download key. **Written with the enum rather than before it**; the enum is four lines of behaviour and the round-trip case is the one that could fail.
- [x] 2.2 `LibraryGrouping` in `feature/library/LibraryGrouping.kt` and `LibraryFeature/LibraryGrouping.swift` — same name, same two cases, same default. Its own file on each platform rather than a tail on `LibraryFacets`, so the twin is findable by name (ADR-0001).
- [x] 2.3 `grouping()` and `saveGrouping(String)` on `LibraryPreferences`, in the shape `downloadFilter()` has. `:core:persistence:testDebugUnitTest` passes.

## 3. The choice changes the rows

- [x] 3.1 `ShelfRowsGroupingTest` (3 Robolectric cases) composes `rememberShelfRows` and asserts all three gates: series collapses, issues lists every publication with an empty series map, and a search or a selection lists issues under either choice. iOS's `LibraryGroupingWiringTests` asserts the same third term on `LibraryView.rows`, as source — the property needs a `LibraryModel` and a window, and the claim is which branch is taken.
- [x] 3.2 The grouping is the third term on the gate each platform already had: `rememberShelfRows(..., grouping)` and `guard grouping.isCollapsing, model.matchGroups.isEmpty, !selection.isActive`. 3.1 passes on both.
- [~] 3.3 The state is wired — `rememberSaveable` plus `chooseGrouping` in `LibraryScreen.kt`, `@AppStorage` in `LibraryView.swift` — and both platforms compile. **Nobody has relaunched either app to watch the choice come back.** That is task 7.

## 4. The control is a named choice, not a glyph

- [x] 4.1 `GroupingChip` in `LibraryControls.kt`, built from `SortChip` and not from `LayoutToggle`: a boxed `FilterChip`, a `DropdownMenu` under it, `Role.RadioButton` and `selected` on both rows. `LibraryControlsAreNamedTest` now asserts five pressable controls in the row instead of four, and that the chip reads `Grouping: Series` rather than the bare word.
- [x] 4.2 The `Picker` in `ViewMenu`, between layout and sort, with its divider. `swift build` passes and `LibraryGroupingWiringTests` asserts the picker and its label key.
- [x] 4.3 Five strings in four languages on both platforms — `library_grouping_chip`, `library_grouping_series`, `library_grouping_issues`, `library_index`, `library_index_jump`, and their iOS keys. `pnpm strings:ios` and `pnpm strings:drawn` pass, and `LibraryGroupingWiringTests` names all five keys so a missing one fails where it was added.

## 5. The index

- [x] 5.1 `LibraryRailTest` (11 cases) and `LibraryRailTests` (9 cases), over the same shelf: the five continuous sorts give no entries, a shelf at the threshold gives none, one distinct letter gives none, *The Sandman* files under S, a series sort files a series-less publication under `#` in one run at the end, a non-letter title is `#`, a repeated letter is one entry pointing at the first row, and a Turkish shelf files *ısı* under *I*. **Written with `LibraryRail` rather than before it.** Proved able to fail: changing `entries.count > 1` to `> 0` in `LibraryRail.swift` failed *One letter over the whole shelf is a label rather than an index* by name, and the guard was restored.
- [x] 5.2 `LibraryRail` in `feature/library/LibraryRail.kt` and `LibraryFeature/LibraryRail.swift` — the same name, the same `of(publications, sort, locale)`, the same three refusals.
- [x] 5.3 `LibraryRailTest` holds the item-index cases too: a grid with a leading row and two sections maps each section's first cover past its heading, and a list with neither maps position to position.
- [x] 5.4 `LibraryRail.itemIndexes` on Android only. iOS needs no twin — `ScrollViewReader` addresses a row by id — and `LibraryGroupingWiringTests` asserts there is exactly one `ScrollViewReader` around the three branches.
- [x] 5.5 `IndexRail` drawn: overlaid inside `CoverGrid.kt` and `CoverList.kt` on Android, the latter gaining a hoisted `LazyListState`; overlaid once on the `ScrollViewReader` in `LibraryContent.swift` on iOS. Both platforms compile, and an empty entry list draws nothing.
- [x] 5.6 `IndexRailIsOperableTest` (3 Robolectric cases) asks the semantics tree: every letter is a node with a click action and a content description naming where it goes, choosing one reports that letter, the rail carries one group name, and an empty index draws no pressable node at all. **iOS is asserted as source and catalogue, not as a rendered tree** — the labels are composed from the two keys 4.3 pins, and no iOS test presses one.

## 6. The compact list stops disagreeing with the grid

- [x] 6.1 `ListRowOpensTheSeriesTest` (1 Robolectric case) composes the list over a series of two and a standalone: the series row is titled *Lantern*, a tap reports the series, and the standalone row still reports the publication. iOS has no rendered twin; `LibraryGroupingWiringTests` asserts that `ListRow` declares the series pair and both of its series destinations.
- [x] 6.2 `seriesRows` and the open-a-series action added to `CoverList` on both platforms, and iOS's `CoverList` handed `shelved` where it used to be handed `shown`. Every existing list test still passes on both platforms.

## 7. Seen on a device

- [ ] 7.1 Four Android frames at `docs/designs/screenshots/issues-and-index-2026-09-11/`: the shelf in series view and in issues view, light and dark, default text size, sorted by title so the index is drawn. `pnpm capture:android`.
- [ ] 7.2 Two more Android frames at `font_scale 2.0`, and one control frame under a `Last read` sort proving the index is absent rather than inert.
- [ ] 7.3 The same seven frames from a booted iOS simulator, after `node scripts/corpus.mjs --simulator <udid>`.
- [ ] 7.4 `README.md` beside them: device, OS version, which build, what each pair proves, and the command that repeats it.

## 8. The gates

- [x] 8.1 `pnpm spec:validate` (32 passed) and `pnpm spec:guard` (15 active changes, 7 pre-existing warnings) green, and `pnpm delta:drop` reporting no collision — the three deltas holding `Presentation` now hold one identical block.
- [x] 8.2 `pnpm test:android` green, and `:feature:library:lint :core:persistence:lint` clean. `pnpm build:android:tests` compiles the instrumented suites.
- [x] 8.3 `swift test` green in `apps/ios/Packages/StoryArcKit`: 2455 tests in 324 suites. `pnpm build:ios` and `pnpm build:ios:tests` both succeed.
- [x] 8.4 `pnpm lint` green, `lines:check` and both string gates included, and `pnpm lint:ios` clean at 801 files.
