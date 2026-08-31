# Tasks — a quieter reader, and a theme sheet with two levels

Test-first throughout. A visible change owes a before/after screenshot pair per
[`AGENTS.md`](../../../../AGENTS.md) §6.

## 1. Two controls over the page

- [x] 1.1 iOS: `ReaderChromeTests` — with chrome revealed, exactly two controls are
      hittable over the page, and neither a title, a page number, a percentage nor a
      slider is among them. Fails against today's three bars.
- [x] 1.2 iOS: collapse the reader's top bar, bottom bar and slider into one overlay
      of two buttons on `.regularMaterial`.
- [x] 1.3 Android: `ReaderChromeTest` — the same two-control assertion against the
      `HorizontalFloatingToolbar` the reader already uses.
- [x] 1.4 Android: collapse the same three surfaces.
- [x] 1.5 Both: `ReaderMenuTests` / `ReaderMenuTest` — the menu offers contents,
      bookmarks, search-in-publication, themes and settings, each with a text label,
      and every control reachable before this change is reachable in one action.
      This is the test that stops the declutter from removing a capability.
- [x] 1.6 Both: assert every pre-existing gesture still behaves — edge tap, swipe,
      pinch, drag-zoom, and the right-to-left mirroring. Fewer controls must not
      mean fewer ways in.
- [ ] 1.7 Both: capture the reader before and after, at default and largest text
      size, into `docs/designs/screenshots/`.

## 2. Progress sized to the format

- [x] 2.1 Both: `ReaderProgressTests` / `ReaderProgressTest` — a reflowable
      publication offers **no slider**, and one line stating progress and what is
      left of the chapter, in words.
- [x] 2.2 Both: a reflowable publication that declares no navigation states progress
      alone and never falls back to a page count.
- [x] 2.3 Both: build the line on the menu's contents row.
- [x] 2.4 iOS: the coarse fill behind the row as a `Rectangle` in a `GeometryReader`.
- [x] 2.5 Android: the fill as a flat `LinearProgressIndicator`. Not the wavy one:
      Material says linear indicators "shouldn't be used in any elements smaller
      than 40dp" and cautions the wavy variant is less visible small.
- [x] 2.6 Both: assert the fill is decorative to assistive technology and the text
      carries the meaning — a percentage announced twice is announced wrong.
- [x] 2.7 Both: a fixed-page publication keeps its slider, in the menu, with the
      thumbnail follow intact. Assert releasing dismisses the menu and offers the
      return-to-previous-position control.

## 3. The theme surface splits in two

- [x] 3.1 Both: `ThemeSheetTests` / `ThemeSheetTest` — level one shows six presets
      and **no axis control**, and one action of equal prominence opens the axes.
- [x] 3.2 Both: picking a preset applies it and dismisses level one.
- [x] 3.3 iOS: level two as a second `.sheet` from the first.
- [x] 3.4 Android: level two as a **destination** with its own top app bar and close
      affordance — not a nested `ModalBottomSheet`. Predictive back is a
      component-level contract and two stacked modal sheets give it two competing
      dismiss targets and no correct preview. `design.md` records that Material does
      not answer this directly and which three adjacent rules it was decided from.
- [x] 3.5 Both: level two draws a live specimen of the publication's own text in the
      active theme, updating as an axis changes.
- [x] 3.6 Both: `ThemeAxisTests` / `ThemeAxisTest` — every axis states its current
      value beside its control, and the value is part of the control for assistive
      technology rather than a separate unlabelled element.
- [x] 3.7 Android: `SliderDefaults.CenteredTrack` for character spacing, word spacing
      and margins, whose defaults sit mid-range. Slider icons outside the track — the
      Expressive inset icon has no API and is forbidden below a 40dp track anyway.
- [x] 3.8 Android: preset tile as `Modifier.selectable(role = Role.RadioButton)` on
      a card-shaped `Surface`, with a hand-drawn outline and tick and **no elevation
      change**. `Card` has no `selected` parameter and Material reserves elevation
      change for pick-up-and-move.
- [x] 3.9 Android: Bold as a `ListItem` with `supportingContent` and a trailing
      `Switch`, `toggleable` on the item.
- [x] 3.10 Both: split level two into its own file. This is also the way off the
      800-line ratchet for `ThemeSheet.kt`.
- [x] 3.11 Both: assert both levels at the largest accessibility text size — no label
      truncated to fit its value, the surface scrolls, the action opening the axes
      stays reachable. **Asserted at the source, not photographed.** The scroll, the
      absence of a line limit on the axis rows and the minimum gap between a name and
      its value are what a guard can check; that nothing *looks* truncated at 200% is
      what a screenshot proves, and 1.7 still owes that.

## 4. Reset by name

- [x] 4.1 Both: `ThemeResetTests` / `ThemeResetTest` — resetting a modified preset
      names it, returns **every** axis to that preset's published value including
      untouched ones, and leaves the other five presets, the custom colour slot, the
      per-series memory and the global default alone.
- [x] 4.2 Both: the reset action is **absent** for an unmodified preset, not present
      and inert.
- [x] 4.3 Both: reset preserves the reading position to the paragraph across the
      repagination, and is visible behind the sheet without dismissing it.
- [x] 4.4 Both: a plain low-emphasis text button, no confirmation. Material has no
      reset-to-defaults pattern; `design.md` says so rather than miscasting the
      discard-unsaved-changes prompt as one.

## 5. The two Material gaps in scope

- [x] 5.1 Android: migrate off the deprecated `rememberModalBottomSheetState` to
      `rememberBottomSheetState(initialValue, enabledValues, confirmValueChange)`,
      and decide `enabledValues` explicitly — the `PartiallyExpanded` anchor is no
      longer removed for you since alpha21.
- [x] 5.2 Android: give level one's header row a single-pointer height toggle.
      Material requires selecting the drag handle to toggle preset heights with a
      Space/Enter contract, and the handle has **no** `onClick` — zero `clickable`
      calls in the whole sheet implementation.

## 6. Docs and close-out

- [ ] 6.1 Update `docs/designs/ui-revamp-2026-08.md` and `docs/openspec/STATUS.md`.
- [ ] 6.2 Record the connected-button-group replacement for the retired segmented
      text-size control as its own proposal rather than absorbing it here.
- [ ] 6.3 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 6.4 `agent-compass openspec-guard . --strict`.
- [ ] 6.5 `/opsx:verify quiet-reader`, then `/opsx:sync`.
