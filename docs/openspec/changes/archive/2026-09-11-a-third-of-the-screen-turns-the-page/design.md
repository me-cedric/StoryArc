## Context

See proposal.md — Why. What matters here is that almost all of it exists.

`ReaderScreen.handleTap` already reads the tap's x against
`EDGE_ZONE_FRACTION = 0.25` and answers *back*, *forward* or *toggle the
chrome*; `isEdgeTap` uses the same constant to decide whether a press should be
allowed to become a double-tap zoom. Both are already reached from every
transition mode — the curl passes `onTap = ::handleTap`, the paged modes pass it
through `SinglePage`, and a two-page spread rescales the point so the zones are
measured against the whole spread rather than each half. iOS mirrors it.

So this change is one constant, one setting, and one branch.

## Goals / Non-Goals

**Goals:**

- One fraction, named once per platform, so the two cannot drift.
- The setting reads like its sibling: `turnPagesWithVolumeButtons` is the
  existing precedent for "a tap-like input a reader may want back".

**Non-Goals:**

- Design-level: no per-publication override, no zone editor, no separate
  setting per transition mode.

## Decisions

**A third, as a named constant, not a number at the call site.**
`EDGE_ZONE_FRACTION` becomes `1f / 3f` and keeps its name, because what it means
did not change. The two call sites are unchanged, which is the argument for the
constant having existed in the first place.

**The setting is on `AppSettings`, beside the volume one.** It is the same kind
of thing — an input a reader may want to stop the reader interpreting — and
`AppSettings`' own header says a screen that reads five settings to draw one row
should read them together. Alternative considered: a reading preference beside
the transition mode, since that is where a reader might look. Rejected because
the transition preferences are per-publication in shape and this is not: a
reader who turns tap zones off means it everywhere.

**Off means the whole screen toggles the chrome.** Not "off means taps do
nothing": a reader who turns page-turning off still needs the way back to the
menu, and the middle third would otherwise be the only live part of a screen
whose other two thirds had just gone dead.

**`isEdgeTap` follows the setting too.** It exists so a press in a turn zone is
not held waiting for a second tap; with the zones off there is no turn to
protect, and every tap should be free to become a double-tap zoom.

**Platform APIs.** Nothing new: Compose `pointerInput` and SwiftUI's existing
tap handling, both already in place. No new dependency on either side.

**Accessibility.** The zones are a convenience over actions that already exist
elsewhere — the menu, the keyboard, the volume buttons — so turning them off
removes no capability. The setting's row carries a full sentence rather than a
bare word, as the volume row does, because "Tap zones" alone does not say what
happens when they are off.

## Risks / Trade-offs

- **A third is a big target, and the reader may hit it while panning a zoomed
  page.** → The zoomed case already routes through the same gesture handling
  that distinguishes a pan from a tap, and this change does not touch it. If it
  proves wrong the answer is the new setting, which is the point of adding one.
- **Two constants, two platforms.** → One name on each side and a test on each
  that pins the fraction, so a change to one that is not made to the other fails
  rather than drifts quietly.

## Migration Plan

None. A reader who has never chosen gets the zones on, which is what they have
today; the only difference they will notice is that the zone is larger.
