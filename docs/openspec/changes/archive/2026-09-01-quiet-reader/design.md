# Design — a quieter reader, and a theme sheet with two levels

## Where the guidance came from

The same 2026-08-31 research pass described in
[`quiet-shell-and-search/design.md`](../quiet-shell-and-search/design.md): Material
guidelines quoted verbatim, and the Compose API checked by `javap -v` over
`material3-1.5.0-alpha26.aar` in the Gradle cache rather than trusted from the
documentation. Where Material has nothing to say, that is stated rather than
filled in.

## The reader's chrome

**Two controls over the page, and both platforms already have the component.**

| | iOS | Android |
| --- | --- | --- |
| The pair | Two `Button`s in an overlay on a `.regularMaterial` capsule | `HorizontalFloatingToolbar`, which the reader already uses |
| Why that component | The platform's own floating treatment over content | Material sanctions exactly one floating bottom capsule — the Expressive floating toolbar — for *"contextual actions relevant to the body content"*, and the reader is the one place in this app where that fits |
| The rule it must not break | — | *Toolbars and navigation bars "should not be shown at the same time"* — which holds, because the reader covers the shell |

Everything else moves into the menu: iOS a `.sheet` with a `List`, Android a
`ModalBottomSheet` with `ListItem` rows. Both label their rows in words. That is
not decoration — eleven icons in a bar is eleven guesses, and the whole reason the
count is being cut is that recognising them was work.

## Progress

**Reflowable: one line, no slider.** The line lives on the menu's contents row, with
the coarse position drawn behind it.

- iOS: the row's background is a `Rectangle` in a `GeometryReader`, at the
  accent colour with low opacity.
- Android: `LinearProgressIndicator` — the **flat** one. Material cautions that the
  wavy variant changes the component's height and *"may not be as visible"* at small
  sizes, and says linear indicators *"shouldn't be used in any elements smaller than
  40dp"*. A thin fill behind a list row is precisely that case. The wavy indicator
  stays where the height exists: downloads and imports.
- **The text carries the meaning.** The fill is decoration and is marked as such to
  assistive technology, because a percentage announced twice is a percentage
  announced wrong.

**Fixed pages: the slider stays, in the menu.** iOS keeps its `Slider` with the
thumbnail follow; Android keeps its `Slider`. Neither is drawn over the page any
more.

### "In words" turned out to mean a band, not a second number

The spec says the line states "how much of the current chapter is left, **in words**",
and implementing it forced a decision this document did not anticipate. It is recorded
here after the fact, because the code made it and the plan should not pretend otherwise.

*42% through · Chapter Three, 63% left* is two numbers a reader has to hold at once to
learn one thing. So the remainder is a **five-band enum** — `nearly done`, `less than
half left`, `about half left`, `more than half left`, `just begun` — shared by both
platforms in `StoryArcCore` and `:core:model`.

Three reasons, in order of weight:

1. **A within-chapter percentage is not accurate enough to be one.** The renderer's
   within-resource progression moves in jumps the width of a screen, so its second
   decimal is noise presented as precision.
2. **The band is what a reader actually wants from a chapter** — whether to keep going
   before putting the book down.
3. **Five bands rather than three**, because *nearly done* and *just begun* are the two
   a reader acts on, and collapsing them into "less than half" and "more than half"
   loses exactly the decision the line exists to inform.

The type carries **no page number field at all**. The spec's *A publication that
declares no chapters* scenario forbids falling back to a page count, and a rule enforced
by a branch can be undone by an `else` — a rule enforced by the absence of a field
cannot be undone without changing the type both readers share.

The line is assembled from three localised fragments with punctuation rather than one
format string, because the chapter title is the publication's and must not be translated.

## The theme surface, and the one real platform divergence

**Level one is a sheet on both platforms.** Six preset tiles, and one full-width
action.

**Level two differs, and this is the decision worth defending.**

| | iOS | Android |
| --- | --- | --- |
| Level two | A second `.sheet` presented from the first | A **destination** — full-screen, its own top app bar, a close affordance |
| Why | Sheet-on-sheet is idiomatic on iOS and the platform animates it as a stack | Predictive back is a *component-level* contract: Material's bottom-sheet page specifies that a back swipe detaches the sheet and *"Previous screen is revealed in a preview"*. Two stacked modal sheets give the gesture two competing dismiss targets and no correct preview |

**Material does not answer this question directly, and the delta says so.** The
bottom-sheet and accessibility pages never mention a nested or stacked sheet, so
claiming Material "discourages" it would be inventing a citation. What Material
*does* say all leans one way: the Dialogs page makes the full-screen variant *"the
only dialogs over which other dialogs can appear"*; the bottom-sheets page pushes
*"more complex tasks and flows"* off transient surfaces; the lists page says a
compact-window second level *"should open a page with the details"*. Three adjacent
rules pointing the same direction is the honest basis for the decision, and it is
recorded as that rather than as a quotation.

## The controls on level two

| Control | Decision | Why |
| --- | --- | --- |
| Preset tile | `Modifier.selectable(role = Role.RadioButton)` on a card-shaped `Surface`, with a hand-drawn outline and tick. **No elevation change** | `Card` has no `selected` parameter and `CardColors` has no selected role — verified by `javap`. The nearest Material rule that exists is the list one: the selected state covers the whole item, single-select uses a radio-button role. Material says card variants differ *"on style alone"* and reserves elevation change for pick-up-and-move |
| Not a `FilterChip` | Rejected | Material caps chip labels at 20 characters and wants an inline row; a chip cannot render `Aa` in six typefaces |
| Sliders | Value stated in a row beside the track | There is **no value-label API** in `SliderDefaults` at all, and Material independently sanctions the arrangement: *"If the value is shown elsewhere, the indicator is not required."* Guidance and the API agree with the design by coincidence |
| Mid-default axes | `SliderDefaults.CenteredTrack` for character spacing, word spacing and margins | Their defaults sit mid-range, which is what the centred variant is for. Stable API |
| Slider icons | Outside the track | The Expressive inset icon has no API, and Material forbids it below a 40dp track and on centred sliders anyway |
| Bold | `ListItem(content =, supportingContent =, trailingContent = Switch)`, `toggleable` on the item | Material authorises the supporting line on a list item; the Switch page requires only an inline label and says nothing about supporting text |
| Reset | A plain low-emphasis `TextButton` / `.borderless` `Button` | **Material has nothing to say about reset-to-defaults** — no component, no pattern. The Dialogs page's discard-unsaved-changes prompt is about abandoning edits, not restoring defaults, and dressing it up as one would be a false citation. No confirmation, because the reset is immediately reversible by picking the preset again |

## Two API facts that change the plan, not the code

- **`rememberModalBottomSheetState` is deprecated** in 1.5.0-alpha26, with an exact
  `replaceWith` pointing at `rememberBottomSheetState(initialValue, enabledValues,
  confirmValueChange)`. `ThemeSheet.kt` currently calls neither — it passes a bare
  `ModalBottomSheet(onDismissRequest =)` — so this is a migration to make while the
  file is open, not a bug being carried.
- **Since alpha21 the `PartiallyExpanded` anchor is no longer removed for you.**
  Opening at Material's 50% cap, or skipping partial expansion, is now an explicit
  `enabledValues` decision. Level one opens partially expanded and expands; level
  two is a destination and does not care.

## Two gaps that are Material's, and are ours to fill

- **The drag handle is not clickable.** Zero `clickable` calls across the whole sheet
  implementation. Material says *"selecting the drag handle should toggle through
  preset heights"* and specifies a Space/Enter contract, so a multi-height sheet
  **owes a hand-built single-pointer alternative that Material explicitly requires**.
  Level one is multi-height, so this is in scope: the header row gets the toggle.
- **The text-size segment is off-guidance.** Expressive retired the baseline segmented
  button in favour of a connected button group, and Compose ships no
  `ConnectedButtonGroup` — only `ButtonGroupDefaults.ConnectedSpaceBetween` and the
  three `connected*ButtonShapes` helpers to assemble one from `ToggleButton`s. The
  compiler will not warn, so nothing in the build stops the wrong choice. **Deferred
  to its own change**, sized honestly, rather than smuggled in here.

## The 800-line ratchet

Level two becoming a new file on both platforms is the natural way off it:
`ThemeSheet.kt` and the iOS theme sheet both split at the level boundary, which is
where they should have split anyway.
