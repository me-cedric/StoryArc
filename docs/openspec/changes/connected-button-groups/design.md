# Design — connected button groups

## What the API actually offers

Checked on 2026-08-31 by `javap -v` over `material3-1.5.0-alpha26.aar` in the Gradle cache,
not read from documentation:

| Thing | State |
| --- | --- |
| `SingleChoiceSegmentedButtonRow`, `MultiChoiceSegmentedButtonRow`, `SegmentedButton` | **Stable and not deprecated.** No `Deprecated` annotation anywhere in `SegmentedButtonKt`. The compiler will never warn |
| A `ConnectedButtonGroup` composable | **Does not exist.** No class or function in `material3` has "Connected" in its name |
| `ButtonGroupDefaults.ConnectedSpaceBetween` | Stable |
| `ButtonGroupDefaults.connectedLeadingButtonShapes` / `connectedMiddleButtonShapes` / `connectedTrailingButtonShapes` | Stable |
| `ToggleButton` and its variants | Stable — promoted in 1.5.0-alpha19 |

So the replacement is assembled rather than called: a `Row` with
`Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)` and `ToggleButton`
children, each shaped by whichever of the three helpers matches its index.

**That asymmetry is the whole reason this is its own change.** A one-line component swap
would belong wherever the control lives; a component that has to be built, given a shape
per position, and then rolled out to every call site is a piece of work with a size.

## The shape

One composable in `core/designsystem`, taking the options and the selected index, because
there are at least two call sites and a third would otherwise copy the shape logic.

**This paragraph said `internal`, and the implementation had to make it public.** Kotlin's
`internal` is scoped to the Gradle module, so an `internal` composable in `:core:designsystem`
is invisible to `:feature:reader` and `:feature:epubreader` — which are the only two things
that call it. Recorded at task 1.7.

Selection is shown by Material's own round-to-square change rather than by a fill of ours —
that is the distinction the Expressive guidance makes, and reproducing the old fill inside a
new component would be the change without the point.

**What shipped still changes colour, and the artifacts should not be read as saying it does
not.** The component passes no `colors` argument at all, so nothing here paints a container:
but `ToggleButton`'s own Material default *does* change container colour when checked, and in
`after-pdf-light-default.png` that reads louder at a glance than the shape does. "Not by a
fill" is a statement about what this component adds, not about what a reader sees.

## Where it goes

The `SingleChoiceSegmentedButtonRow` call sites, found by grep at the time of writing rather
than assumed: the reader's text-size control and the theme sheet's alignment picker. The
implementation should re-grep rather than trust this list — the whole premise of the change
is that nothing in the build tracks these.

**It re-grepped, and both names above were wrong.** Task 1.1 has the detail; the two real
sites are `feature/reader/.../PdfTextSheet.kt` (the PDF text sheet's *Search* / *Highlights*
tabs) and `feature/epubreader/.../ThemeAxesScreen.kt` (`AlignmentControl`). There is no
segmented text-size control anywhere in the app — `FontSizeControl` is two `IconButton`s
around a `StepDots` row — and the alignment picker is not in `ThemeSheet.kt`, which only held
the imports. These two lines are here because archiving freezes this file beside the task
list, and a reader who opens the plan first would go looking for a control that never existed.

## What is deliberately not touched

**The search scope chips.** `quiet-shell-and-search` narrows with `FilterChip`s and its
design says why: a connected group is specified for two-to-five toggleable views, and a
reader's set of configured sources is neither fixed nor small. Swapping those would be
following the letter of "replace segmented buttons" past the point where it is true.

**iOS.** Its segmented control is current and idiomatic there, and
[ADR-0001](../../../decisions/0001-independent-native-cores.md) is why the two platforms
are allowed to answer this differently. This change is Android-only and its task list says
so at every step.

## Risk

Low, and worth stating anyway: the shapes are per-position, so a group whose options are
reordered or filtered at run time has to recompute them. Any call site that builds its
options dynamically needs the index passed through rather than captured.
