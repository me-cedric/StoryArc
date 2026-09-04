# Tasks — connected button groups

Android only. Test-first; a visible change owes a before/after capture per
[`AGENTS.md`](../../../../AGENTS.md) §6.

## 1. The component

- [x] 1.1 Re-grep for `SegmentedButtonRow` across `apps/android` and record what is found.
      **Do not trust `design.md`'s list** — the premise of this change is that nothing in
      the build tracks these, which applies to a list written by hand as much as to a
      compiler.

      `grep -rn "SegmentedButton" apps/android` matches **four** files. Two are live call
      sites, one is dead imports, one is an existing guard:

      | File | What matches |
      | --- | --- |
      | `feature/reader/.../PdfTextSheet.kt` | A live `SingleChoiceSegmentedButtonRow` over `PdfTextTab.entries`, shaped by `SegmentedButtonDefaults.itemShape(index, size)` |
      | `feature/epubreader/.../ThemeAxesScreen.kt` | A live `SingleChoiceSegmentedButtonRow` in `AlignmentControl`, over `ReaderTextAlignment.entries` |
      | `feature/epubreader/.../ThemeSheet.kt` | **Three dead imports and no usage.** `SegmentedButton`, `SegmentedButtonDefaults` and `SingleChoiceSegmentedButtonRow` are imported; the file's only controls are preset cards, a stepper and a button |
      | `feature/library/.../LibrarySearchBarTest.kt` | An `assertFalse` that the search bar has *not* acquired a segmented control. Deliberate, and the guard 2.3 generalises |

      **`design.md`'s list was wrong on both of its two entries, and right on the count of
      live sites.** It predicted "the reader's text-size control and the theme sheet's
      alignment picker".

      - There is **no segmented text-size control anywhere.** `FontSizeControl` in
        `ThemeAxesScreen.kt` is two `IconButton`s either side of a `StepDots` row, and
        always was. What `:feature:reader` actually has is `PdfTextSheet`'s Search/Marks
        **tab switcher** — a different control, in a different module, doing a different
        job.
      - The alignment picker is the right control, but it does **not** live in
        `ThemeSheet.kt`. It is `AlignmentControl` in `ThemeAxesScreen.kt` — level two of
        the sheet, not level one. `ThemeSheet.kt` matches the grep only because it still
        imports an API it no longer calls, which is exactly the residue a list written by
        hand cannot see and the 2.3 guard can.

      So: two call sites to replace, and a third file to clear of dead imports.
- [x] 1.2 `ConnectedButtonGroupTest` — a group of N options shapes its first with
      `connectedLeadingButtonShapes`, its last with `connectedTrailingButtonShapes` and
      every other with `connectedMiddleButtonShapes`, and a group of one gets a single
      shape rather than a leading one. Write it, watch it fail.

      Eight tests in
      `core/designsystem/src/test/.../control/ConnectedButtonGroupTest.kt`, Robolectric with
      `GraphicsMode.NATIVE` because the three shape helpers are `@Composable` and resolve
      against `MaterialTheme.shapes` — a value read outside a composition is not the value
      the group is drawn with. The expectations are equalities against **Material's own
      helpers**, never against corner radii written down here: a copied radius is a second
      source of truth that goes stale on the next alpha.

      Watched fail twice, on purpose, before it was allowed to pass:

      | Mutation | Result |
      | --- | --- |
      | *(no implementation yet)* | `Unresolved reference 'ConnectedButtonGroup'` ×4, `'connectedButtonShapes'` |
      | `index == count - 1` → `index == count` | 2 failed — *"The last option is not shaped with connectedTrailingButtonShapes, so the group's right end is not rounded off"* |
      | `count <= 1` → `count <= 0` | 1 failed — expected `RoundedCornerShape(50%…)`, got `topStart = 100%, topEnd = 8.0.dp` — a lone button squared off on the side where nothing follows it |

      Both reverted; the file is byte-identical to its pre-mutation state and the suite is
      back to 8 passed. One casualty on the way in: `ToggleButtonDefaults.shapes()` **does
      not resolve** — the no-argument overload and the three-defaulted-argument one beside
      it are both applicable to an empty argument list, and K2 reports it as
      `Unresolved reference`. Both the component and the test name the three values
      individually instead.
- [x] 1.3 Build it in `core/designsystem`: a `Row` with
      `Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)` and `ToggleButton`
      children. Selection is the round-to-square shape change, **not** a fill.

      `control/ConnectedButtonGroup.kt`. Public, not `internal` as `design.md` says — Kotlin
      `internal` is Gradle-module-scoped, and both call sites are in other modules, so an
      internal composable here would be invisible to every caller it exists for. Nothing in
      it paints a container colour: `checkedShape` arrives from Material and one test asserts
      per position that it differs from `shape`, so a component that lost the distinction
      fails rather than quietly drawing a segmented button with no fill.

      Colour comes from `MaterialTheme` via `ToggleButton`'s own defaults — no brand token is
      named, so the group is unaffected by the token rename landing in parallel.
- [x] 1.4 Assert the selected option is announced as selected to assistive technology, and
      that the group is one element with N selectable children rather than N unrelated
      buttons.

      Two of the eight. **`ToggleButton` announces `role = Role.Checkbox`** — read out of
      `ToggleButtonKt`'s bytecode, not from documentation — so left alone a group of three
      would tell a screen reader that each option is checked or unchecked and that any number
      of them may be picked, when exactly one is ever true. Each child is given
      `Role.RadioButton` and a `selected` state through the caller modifier, which does win
      over Material's internal role, and the `Row` carries `selectableGroup()`. Asserted as
      `assertIsSelected` / `assertIsNotSelected`, `SemanticsProperties.SelectableGroup`
      defined on the row, and `Role.RadioButton` on all three children.

## 2. The call sites

- [x] 2.1 Replace each site found in 1.1, one commit each, ticking as it lands.
      - [x] `feature/reader/.../PdfTextSheet.kt` — the Search/Marks tab switcher.
            `:feature:reader:testDebugUnitTest` 46 passed in 10 files, `:feature:reader:lint`
            passed. The three `Segmented*` imports are gone with it.
      - [x] `feature/epubreader/.../ThemeAxesScreen.kt` — `AlignmentControl`.
            `:feature:epubreader:testDebugUnitTest` 54 passed, `:feature:epubreader:lint`
            passed. `ThemeSheetTest` asserts `AlignmentControl(` is drawn on level two and
            not on level one; both still hold, unedited.
      - [x] `feature/epubreader/.../ThemeSheet.kt` — not a call site, but the three dead
            `Segmented*` imports it carried are removed. Nothing warned about them: Kotlin
            does not report an unused import, which is the second reason this change had no
            mechanical signal behind it.
- [x] 2.2 Each site's existing behaviour test must still pass **unchanged**. If one needs
      editing, the change has altered behaviour and that is a defect, not a fixup.

      **No existing test file was edited.** The change's whole diff is two main sources, one
      import removal, one new component, two new test files and this list — nothing under an
      existing `src/test` or `src/androidTest` was touched, which is checkable from the diff
      rather than only assertable here.

      | Suite | Result |
      | --- | --- |
      | `:feature:reader:testDebugUnitTest` | 46 passed, 10 files. `ReaderMenuTest` asserts the sheet opens on the tab the menu row names |
      | `:feature:epubreader:testDebugUnitTest` | 54 passed. `ThemeSheetTest` asserts `AlignmentControl(` is on level two and not level one |
      | `:core:designsystem:testDebugUnitTest` | passed with `--rerun-tasks`, including the 8 new component tests and the 3 new guard tests |

      Not run, and named rather than skipped quietly: `ThemeSheetSemanticsTest` in
      `:feature:epubreader/src/androidTest` asserts a preset announces itself as chosen. It is
      instrumented, so no gate executes it — `pnpm build:android:tests` compiles it and
      nothing runs it. It touches presets rather than the alignment picker, so the replaced
      control is not among its claims.
- [x] 2.3 A source-level guard that no `SegmentedButtonRow` returns to `apps/android`.
      Mutation-check it by re-adding one.

      `core/designsystem/src/test/.../control/NoSegmentedButtonsTest.kt`. Three tests: the
      absence across every `src/main/kotlin` tree under `apps/android`, a positive control
      that the sweep found more than fifty files across more than four module trees, and the
      other direction — that `ConnectedButtonGroup(` is still called from at least two files,
      because an absence guard on its own is satisfied by deleting both controls.

      In `:core:designsystem`'s own test source set, as instructed: `:feature:library`'s
      `LibrarySearchBarTest` already guards the search bar and belongs to another agent.

      Mutation-checked three times, each reverted:

      | Mutation | Result |
      | --- | --- |
      | The dead `SegmentedButtonDefaults` import put back in `ThemeSheet.kt` — the regression that actually happened, and one Kotlin does not warn about | failed: *"The segmented button is back: ThemeSheet.kt: SegmentedButtonDefaults"* |
      | `SingleChoiceSegmentedButtonRow { SegmentedButton() }` back in `PdfTextSheet.kt` | failed, naming both tells: *"PdfTextSheet.kt: SingleChoiceSegmentedButtonRow, SegmentedButton("* |
      | One `ConnectedButtonGroup(` call removed | failed: *"the replacement is still drawn at both call sites"* |

      Two false positives were found by running it and both are fixed rather than excused: a
      test that forbids a spelling must contain it (so only `src/main/kotlin` is swept), and
      the replacement's own KDoc names what it replaces (so comments are stripped, the way
      `ThemeSheetTest` does).

      **It re-runs when another module changes, and that was checked rather than assumed.**
      The first version of this guard walked up from the module directory and carried a
      written-down limitation: no sibling module's sources are inputs of
      `:core:designsystem:testDebugUnitTest` — the dependency runs the other way — so a
      segmented button added to `:feature:reader` alone would leave the task UP-TO-DATE and
      the guard silent.

      The parent's rebase onto `main` brought the fix with it. `b7fc76d0` added
      `storyarc.android.rootDir` and an `inputs.files(fileTree(rootDir))` over every module's
      `src/main/**/*.kt` to this module's build script, for `ArcStopsAreNotChromeTest`, which
      sweeps the whole app for the same kind of reason. This guard now reads that property
      instead of climbing, and the limitation is gone rather than merely restated.

      Demonstrated: the dead import put back in `:feature:epubreader` **only**, then
      `:core:designsystem:testDebugUnitTest` run with **no** `--rerun-tasks` — the task
      re-ran and failed, 101 tests completed, 1 failed. Reverted.

## 3. Proof and close-out

- [x] 3.1 Before/after captures of every replaced control, at default and largest text
      size, light and dark. The selection treatment is the whole visible change, so a
      capture that does not show a selected option proves nothing.

      Sixteen, in
      [`docs/designs/screenshots/connected-button-groups-2026-09-01/`](../../../designs/screenshots/connected-button-groups-2026-09-01/README.md):
      two controls × before/after × light/dark × 1.0 and 2.0 font scale, every one with an
      option selected. `storyarc-j6` (API 36, 1080×2400), `-gpu host`. Device put back to
      font_scale 1.0 and light.

      Both builds are `assembleDebug` from the same tree, differing only by the two call
      sites — checked in the dex rather than assumed: the before APK holds 8 references to
      `ConnectedButtonGroupKt` (the component compiles into `:core:designsystem` either way)
      and the after APK 10, the two extra being the call sites.

      **`pnpm capture:android` could not take these.** Neither control is a listed route in
      `scripts/android-routes.mjs`, and both sit four or five taps behind a reader.
      **True as written, and half of it stopped being true on 2026-09-02**: `'EPUB reader >
      axes'` is a listed route now — Library → *Harbour Lights 01* → Read → menu → themes →
      Customise, which is where `AlignmentControl` lives. So whoever recaptures the alignment
      picker should use `pnpm capture:android` rather than a throwaway script. The PDF text
      sheet still has no route. The walk
      was driven by a throwaway script over that module's own exported `navigator`; nothing
      under `scripts/` was modified. Two things it had to learn, both recorded in the
      folder's README: the axes screen draws `AlignmentControl` only under a preset that
      turns publisher styles off, and "uiautomator found it" is not "you can photograph it" —
      the first alignment capture stopped with the picker below the fold.

      **The emulator was contended and it mattered.** A second AVD (`storyarc-api36`) was
      started to avoid disturbing another agent, wedged its shell under host memory pressure,
      and was shut down. `storyarc-j6` then went `offline` and reloaded its boot snapshot,
      silently discarding an APK whose install had reported `Success` — a capture taken
      straight afterwards was of another build, and only a dex check found it. `uiautomator
      dump` answered `null root node` on most attempts throughout.
- [x] 3.2 `pnpm lint`, `pnpm check`, `pnpm gradle`, `pnpm build:android:tests` — all green on
      2026-09-04, on `main` with the change's commits merged. 1855 iOS tests in 235 suites,
      SwiftLint 0 violations in 657 files, `pnpm gradle` and `assembleAndroidTest` clean.
      `pnpm check` runs `swiftlint lint --strict` *with* its cache, so the strict no-cache run
      this change's siblings ask for was made separately and read the same 657 files. That
      count matters more than the verdict: SwiftLint silently reads no config when the working
      directory has drifted into `apps/ios/Packages/StoryArcKit`, and reports 759 files and
      hundreds of phantom violations. A file count that does not match the last run is
      measuring a different thing.
      **Re-run after the verify pass's two code changes landed**, because a gate run before the
      last edit is a claim rather than a record: the guard's fifth retired spelling, its
      depth-independent input globs, and the `clearAndSetSemantics` that drops
      `ToggleButton`'s spare checkbox state. Green again on the same counts.
- [x] 3.3 `pnpm spec:guard:strict` — 0 errors, 1 warning, and that warning is the
      pre-existing orphan list (six main specs named by no change).
- [x] 3.4 `/opsx:verify connected-button-groups`, then `/opsx:archive` — there is no
      `/opsx:sync` step, because this change declares `skip_specs` and has no delta.
      Verified and archived on 2026-09-04. The verify pass reported no critical issue in what
      shipped: the component is assembled from `ConnectedSpaceBetween`, `ToggleButton` and the
      three positional shape helpers with no reproduced fill, both call sites are replaced, no
      `SegmentedButtonRow` remains in any Android source, the guard demonstrably works against
      354 files in 13 module trees, and four of the sixteen captures were opened rather than
      counted. Its two criticals were this section's own gate runs. Its documentation findings
      are recorded above; two of its suggestions were taken as code.
      **The skip is machine-accepted, not merely asserted**: the guard errors on a missing skip
      declaration and warns on a reason under 20 characters, `openspec status` reports
      `specs: skipped`, and there is no `specs/` directory to merge. `native-experience`
      already carries the general ask that Android uses Material 3 Expressive components, which
      is what makes the skip sound rather than convenient.

## Artifact corrections, 2026-09-04 — from `/opsx:verify`

The verify pass before archiving found nothing wrong with what shipped and two documentation
errors, both in artifacts that archiving freezes:

- **`design.md` named two call sites that never held the control.** "The reader's text-size
  control and the theme sheet's alignment picker" — task 1.1 disproved both, and the plan had
  pre-authorised its own inaccuracy ("the implementation should re-grep rather than trust this
  list"). The two real files are now named there, and in `proposal.md`, which carried the same
  pair. The sentence is left standing beside the correction because being unable to name its
  own call sites *is* the argument for the change.
- **`design.md` said "one internal composable"**, and Kotlin's `internal` is Gradle-module
  scoped, so an internal composable in `:core:designsystem` is invisible to the only two
  modules that call it. Corrected with the reason.
- **All three artifacts said selection is shown "not by a fill"**, which is true of what this
  component paints — there is no `colors` argument anywhere in it — and not of what a reader
  sees: `ToggleButton`'s own Material default changes container colour when checked, and in the
  captures that reads louder at a glance than the shape does. The screenshot README already had
  the honest version; the three artifacts that archive did not.
- **`STATUS.md` said three call sites.** Two, plus a third file cleared of dead imports.

Two suggestions were taken as code rather than as notes, and are in
`fix(android): the connected group announces one radio button and nothing else`: the guard
gained a fifth retired spelling, because a bare `material3.SegmentedButton` import with no call
passed all four it listed — the exact residue this change cleaned by hand — and its Gradle
input globs went depth-independent, because they matched one directory level while the sweep
matches none. The verify pass also flagged, unconfirmed, that overriding `ToggleButton`'s role
might leave its checkbox state behind. It does, and that is fixed and asserted there.

