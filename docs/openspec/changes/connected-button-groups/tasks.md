# Tasks — connected button groups

Android only. Test-first; a visible change owes a before/after capture per
[`AGENTS.md`](../../../../AGENTS.md) §6.

## 1. The component

- [ ] 1.1 Re-grep for `SegmentedButtonRow` across `apps/android` and record what is found.
      **Do not trust `design.md`'s list** — the premise of this change is that nothing in
      the build tracks these, which applies to a list written by hand as much as to a
      compiler.
- [ ] 1.2 `ConnectedButtonGroupTest` — a group of N options shapes its first with
      `connectedLeadingButtonShapes`, its last with `connectedTrailingButtonShapes` and
      every other with `connectedMiddleButtonShapes`, and a group of one gets a single
      shape rather than a leading one. Write it, watch it fail.
- [ ] 1.3 Build it in `core/designsystem`: a `Row` with
      `Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)` and `ToggleButton`
      children. Selection is the round-to-square shape change, **not** a fill.
- [ ] 1.4 Assert the selected option is announced as selected to assistive technology, and
      that the group is one element with N selectable children rather than N unrelated
      buttons.

## 2. The call sites

- [ ] 2.1 Replace each site found in 1.1, one commit each, ticking as it lands.
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
