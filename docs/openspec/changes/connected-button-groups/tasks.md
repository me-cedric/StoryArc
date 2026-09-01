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

- [ ] 2.1 Replace each site found in 1.1, one commit each, ticking as it lands.
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
- [ ] 2.2 Each site's existing behaviour test must still pass **unchanged**. If one needs
      editing, the change has altered behaviour and that is a defect, not a fixup.
- [ ] 2.3 A source-level guard that no `SegmentedButtonRow` returns to `apps/android`.
      Mutation-check it by re-adding one.

## 3. Proof and close-out

- [ ] 3.1 Before/after captures of every replaced control, at default and largest text
      size, light and dark. The selection treatment is the whole visible change, so a
      capture that does not show a selected option proves nothing.
- [ ] 3.2 `pnpm lint`, `pnpm check`, `pnpm gradle`, `pnpm build:android:tests`.
- [ ] 3.3 `pnpm spec:guard:strict`.
- [ ] 3.4 `/opsx:verify connected-button-groups`, then `/opsx:archive` — there is no
      `/opsx:sync` step, because this change declares `skip_specs` and has no delta.
