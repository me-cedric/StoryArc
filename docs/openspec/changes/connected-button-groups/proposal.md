# The segmented buttons Material retired

## Why

Material 3 Expressive says plainly that the baseline segmented button "is no longer
recommended" and that a **connected button group** should replace it, with selection shown
by a round-to-square shape change rather than by a fill.

StoryArc themes with `MaterialExpressiveTheme`, so that guidance applies to it. It uses
`SingleChoiceSegmentedButtonRow` in at least two places — the reader's text-size control
and the theme sheet's alignment picker.

**Nothing in the build will tell anybody.** Compose has *not* deprecated
`SegmentedButton`; `javap` over `material3-1.5.0-alpha26.aar` shows no deprecation on it at
all, so the compiler is silent and will stay silent. This is a guidance change with no
mechanical signal behind it, which is exactly the kind that sits unnoticed for a year.

## What changes

Every `SingleChoiceSegmentedButtonRow` and `MultiChoiceSegmentedButtonRow` becomes a
connected button group. Nothing a reader can do changes; what changes is which component
draws it and how the selected one is distinguished.

**There is no `ConnectedButtonGroup` composable.** Verified against the artifact: no class
or function in `material3` has "Connected" in its name. It is assembled — a row with
`Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)` and `ToggleButton`
children shaped by `ButtonGroupDefaults.connectedLeadingButtonShapes`,
`connectedMiddleButtonShapes` and `connectedTrailingButtonShapes`. All of those are stable.

So this is a small reusable component plus its call sites, and it is sized honestly rather
than smuggled into a change about something else.

## Platforms

**Android only.** iOS's segmented control is current and idiomatic on that platform and is
not being replaced; [ADR-0001](../../../decisions/0001-independent-native-cores.md) means
the two are allowed to answer this differently, and here they should.

## Non-goals

- **No behaviour change.** Same options, same selection, same persistence.
- **Not the scope chips.** `quiet-shell-and-search` already narrows with `FilterChip`s and
  says why a connected group is the wrong component there: it is specified for two-to-five
  fixed views, and a reader's set of configured sources is neither fixed nor small.
- **No new axis, no new control.** This replaces what is drawn, not what is offered.

## Capabilities

None. This adds and modifies no requirement — every affected control keeps the behaviour
its capability already specifies, and `native-experience` already asks for the platform's
current idiom in general terms. `.openspec.yaml` declares `skip_specs: true` with that
reason beside it.

## Where this came from

Deferred deliberately by [`quiet-reader`](../quiet-reader/design.md)'s design, which found
it while checking the theme sheet's controls against the shipped API and recorded that it
"should be scheduled as its own task rather than smuggled into this change".
