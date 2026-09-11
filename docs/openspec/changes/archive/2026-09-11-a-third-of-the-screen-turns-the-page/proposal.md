# A third of the screen turns the page

**Platforms: both.** The zone is one fraction in one constant per platform, and
the setting is one field on the settings value both apps already share in shape.

## Why

The reader asked for the tap zones to be thirds, and for a way to turn them off.

Most of it is already built and was not obvious from the outside: a tap in the
leading or trailing zone turns the page in every transition mode including the
curl, and a tap in the middle toggles the chrome. What is wrong is the size and
what is missing is the switch.

**The zone is a quarter, and a quarter is too small.** `EDGE_ZONE_FRACTION` is
`0.25`, so half the screen does nothing but toggle chrome. On a phone held in
one hand the thumb lands near the middle, which is the half that toggles —
so the gesture a reader uses most is the one they hit least reliably.

**There is no way to turn it off.** A reader who zooms and pans a large page,
or who reads with a stylus, taps the page for reasons that are not "turn". The
volume-button turn is a setting for the same class of reason and says so.

## What Changes

- **The zones are thirds.** Leading third turns back, trailing third turns
  forward, middle third toggles the chrome. Mirrored in right-to-left, as they
  already are.
- **A setting turns them off, and it is on by default.** With it off the whole
  screen toggles the chrome, and the page turns by swipe, by keyboard, by
  controller and by the volume buttons where those are enabled — every trigger
  `page-transitions` already names.
- **The zones keep working in every transition mode**, which they already do and
  which no requirement currently says out loud. Said out loud, because it is the
  thing the reader asked to be sure of.

## Capabilities

### Modified Capabilities

- `page-transitions`: *Turn triggers* gains the zone's size, the setting, and
  what the screen does when the setting is off.
- `comic-reader`: *Edge taps turn pages* says the same thing about the same
  gesture and must not disagree with it.

## Impact

- `apps/android/feature/reader`: `ReaderScreen`'s `EDGE_ZONE_FRACTION`,
  `handleTap` and `isEdgeTap`.
- `apps/ios/Packages/StoryArcKit/Sources/ReaderFeature`: the same two.
- `:core:model` / `Sources/StoryArcCore`: one field on `AppSettings`.
- The settings screen on both platforms: one row beside the volume-buttons row,
  which is the setting this one is a sibling of.

## Non-goals

- **No configurable zone size.** A third is a decision, not a slider: a reader
  who wants a different one wants the gesture off, which is the setting this
  change adds.
- **No new gesture.** Swipe, keyboard, controller and volume are unchanged.
- **Not the double-tap zoom**, which is `comic-reader`'s and keeps its own
  handling of the same taps.
