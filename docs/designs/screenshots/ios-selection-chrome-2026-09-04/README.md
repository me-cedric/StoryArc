# The selection chrome, photographed at last

Ten pictures, iOS only, taken on `StoryArc-iPhone17Pro`
(`11DFC984-7DF7-4E1A-99F6-B7B4BED091F8`, 402 × 874 pt at @3x) against the corpus
`scripts/corpus.mjs` builds.

This closes `named-failures-and-quieter-chrome` §3b.7. The selection chrome shipped on
2026-09-02 with **no captures at all** — both devices were sweeping every screen when it
landed, and two UI-test runs on one simulator interfere. What shipped was the Apple pattern
in three parts: the tab bar is **hidden** for the duration of the mode, the actions float as
a glass **capsule** where the tab bar was, the count moved to the navigation title and *Done*
to the toolbar's trailing slot.

All three are visible in every frame here, and the two things the pictures were asked to
settle are settled below — one of them not the way the change expected.

## The frames

| Picture | Surface | State | Appearance | Text size |
| --- | --- | --- | --- | --- |
| `ios-library-selecting-none.png` | library shelf, top | selecting, **0 picked** | light | default |
| `ios-library-selecting-none-dark.png` | library shelf, top | selecting, **0 picked** | dark | default |
| `ios-library-selecting-picked.png` | library shelf, top | selecting, **2 picked** | light | default |
| `ios-library-selecting-picked-dark.png` | library shelf, top | selecting, **2 picked** | dark | default |
| `ios-library-selecting-none-ax5.png` | library shelf, top | selecting, **0 picked** | light | `accessibility-extra-extra-extra-large` |
| `ios-library-selecting-none-ax5-dark.png` | library shelf, top | selecting, **0 picked** | dark | `accessibility-extra-extra-extra-large` |
| `ios-library-selecting-ax5.png` | library shelf, top | selecting, **2 picked** | light | `accessibility-extra-extra-extra-large` |
| `ios-library-selecting-ax5-dark.png` | library shelf, top | selecting, **2 picked** | dark | `accessibility-extra-extra-extra-large` |
| `ios-library-selecting-end.png` | library shelf, **end of scroll** | selecting, 0 picked | light | default |
| `ios-library-selecting-end-dark.png` | library shelf, **end of scroll** | selecting, 0 picked | dark | default |

Every frame is produced by a walk that proves the screen before the shutter: the navigation
bar is read back for `N selected` with the exact count the filename claims, *Done* is
confirmed present, and all three action labels are confirmed on screen. A walk that picked
nothing, or that photographed the shelf without entering the mode, now fails instead of
passing — which is what the first version of these walks did.

## The question the change recorded, answered

> The action row takes `.storyArcGlassText(.primary)`, but the automatic (borderless) button
> style may colour its own labels with the tint and win over the ancestor `foregroundStyle`.

**The ancestor wins. The labels are `.primary`, not accented.** Measured on the glyph strokes
rather than judged by eye:

| | The action capsule's glyphs | *Done*, in the same navigation bar |
| --- | --- | --- |
| light | `#000000`, saturation **0.000** | `#8a4df0`, saturation **0.679** |
| dark | `#f4f4f4`, saturation **0.000** | `#8a4df0`, saturation **0.679** |

Two controls, one screen, one moment: the toolbar's own button takes the tint and the
capsule's actions do not. Nothing tints the *material* in either case, so no rule in
`docs/design.md` is broken either way — but the outcome is now a fact rather than a
coin-flip, and it holds at both text sizes (the AX pair measures `#000000` and `#f4f4f4` on
the same 16 759 stroke pixels, the same glyph geometry inverted).

**And it reads correctly.** The accent is doing exactly one job in this mode — marking what
is picked and how to leave — while the three things a reader *could* do stay neutral on the
glass. Three violet glyphs beside a violet *Done* would have flattened that hierarchy, and
over the dark shelf in `ios-library-selecting-picked-dark.png` they would have competed with
the violet ticks a foot above them.

## Two things the pictures settled that nobody asked

### The named row is never drawn on this phone

`BulkActionBar`'s `ViewThatFits` offers `.labelStyle(.titleAndIcon)` first and falls back to
`.iconOnly`. Its own doc comment says the fallback is reached "at a width that cannot hold
the names — which on a phone is the accessibility text sizes", and §3b.5 says glyph-only
"survives in exactly two places, both on Android's top bar".

**Neither is true on a 402 pt iPhone.** The fallback is already taken at the **default** text
size: every frame here, at both sizes, shows three bare glyphs. The arithmetic is not close —
the capsule gets 402 − 2 × 20 pt of gutter − 2 × 12 pt of its own padding = 338 pt, and *Add
to…* · *Download* · *Mark as read* at `.controlSize(.large)` with their icons and two 12 pt
gaps need appreciably more than that.

So the design review's objection — three unlabelled glyphs — is live on iOS after all, one
surface over from the toolbar that was cut down to answer it. The names survive for VoiceOver
(`Label` keeps its title whichever style draws it, and the walks assert all three by name at
both text sizes), so this is a legibility question rather than an accessibility one. It is
**not fixed here**: this was a capture job, and the fix is a behaviour change that wants its
own task — fewer actions in the capsule, an overflow menu, or a two-line capsule.

`BulkSelectionChromeTests.theNamesAreDrawnWhereThereIsRoom` did not catch it and could not:
it greps the source for `.titleAndIcon` and `ViewThatFits`. That proves the fallback is
*declared*. Only a picture says which branch a phone takes, which is the argument §3b.7 made
about the AX size and which turns out to apply at the default one.

### The inert capsule is pixel-identical to the live one

§3b.4 chose to show the actions at nought picked rather than hide them, so that the chrome
does not arrive under a thumb mid-tap. The actions are `.disabled(selection.ids.isEmpty)`.

**The disabled state is invisible.** Comparing the capsule's rectangle between the 0-picked
and 2-picked frames of the same appearance and text size:

```
capsule, light,     0 vs 2 picked : 0 of  27 900 pixels differ, worst channel delta 0
capsule, dark,      0 vs 2 picked : 0 of  27 900 pixels differ, worst channel delta 0
capsule, light AX5, 0 vs 2 picked : 0 of 110 500 pixels differ, worst channel delta 1
capsule, dark AX5,  0 vs 2 picked : 0 of 110 500 pixels differ, worst channel delta 2
```

All four pairs, so this is not one appearance's accident. The control says the two frames
really are two different states: over the first cover's tick the light default pair differs
on **45 %** of pixels with a worst channel delta of 202, and whole-frame the four pairs
differ on 0.25 %, 0.29 %, 1.40 % and 1.46 % of pixels with worst deltas of 255, 234, 255 and
234. So the frames are not duplicates and the capsule inside them is unchanged.

The likely cause — stated as an inference, not a measurement — is the same modifier the
question above is about: `.storyArcGlassText(.primary)` sets an explicit `foregroundStyle`
outside the `.disabled(…)`, and an explicit foreground style defeats the dimming SwiftUI
would otherwise apply to a disabled label. So the mode is inert in behaviour and says so
nowhere. Also **not fixed here**, for the same reason.

## What the end-of-scroll pair says

The last row of covers and its captions are **fully clear** of the capsule in both
appearances — `Tidal Reach #2` and `#3` sit above it with the shelf's own background between.
So the bottom inset is right, and it was right before: `BulkActionBar`'s doc comment already
recorded that "the last row of covers *did* clear the bar, so the inset was never the defect;
the shape was". These two frames are what makes that a measurement on the shipped chrome
rather than a claim about the one it replaced.

At the top of the shelf the capsule *does* overlap the third row's captions
(`ios-library-selecting-picked.png`) — which is what Liquid Glass is for, and is not a defect
precisely because the end-of-scroll pair shows the row can be scrolled clear.

## The dark half is not decoration

The capsule is glass, and a capsule photographed only on paper says nothing about what it
does. Measured off-glyph inside the capsule and on the shelf immediately beside it, at the
same height:

| | Capsule fill | Shelf beside it | Relative luminance |
| --- | --- | --- | --- |
| light | `#fcfaf9` (lum 250.4) | `#f5f3f1` (lum 244.3) | **1.03 ×** |
| dark | `#181715` (lum 22.4) | `#0f0d0b` (lum 12.5) | **1.79 ×** |

So the two appearances are not the same picture twice. On paper the fill is within seven
units per channel of the shelf and it is the shadow and the border that separate them; over
the dark shelf the same material nearly **doubles** the ground's luminance and reads as a
plainly lifted surface. A reviewer who saw only the light frame would have no evidence about
the half of the app where this control is most visible. Same walk, same moment in the run,
two device appearances — which is the control `AGENTS.md` §6 asks for.

**The appearance in these filenames is trustworthy, and it was not before.** All three
pre-existing walks launched with `AuditWalk.launch()`, which sets a content-size category and
nothing else. The app's *stored* appearance outranks the simulator's, this device has carried
`oledDark`, and `SweepLibraryTests.testCaptureCoverGrid` already records a light capture that
came back true black for exactly that reason. The walks now use `sweepLaunch`, which pins the
appearance to `system` and every shelf key besides, so `--appearance` is the only lever.

## What is deliberately not here

- **Android's half of §3b.7.** The contextual `TopAppBar` at 0 and at many, light and dark,
  default and largest text, still has no walk. An Android agent was on the emulator while
  these were taken; this job was iOS only, and §3b.7 stays open until that half exists.
- **The undo capsule.** `BulkUndoBar` stacks above the action capsule inside one
  `GlassEffectContainer` so their edges morph, and §3b.6 floated a second instance of it one
  screen over. Raising it means actually running *Mark as read* on the picks, which writes
  progress that persists on the device and would pollute every later capture on this
  simulator — and the offer lives for ten seconds. It needs its own walk with a restore step,
  not a shutter bolted onto these.
- **`ShelfBulkActions`, §3b.6's second home.** It is applied in `ShelfDetail`, which needs a
  collection or a reading list with members. `scripts/corpus.mjs` builds neither, and
  `sweepLaunch` has no lever for one — so reaching it means creating a collection through the
  UI, which persists. Same objection as the undo bar.
- **The *Add to…* menu open.** Uncaptured before this change and uncaptured after. The walks
  assert the control by name; nothing opens it. It is the same `AddToShelfMenu` a long press
  on one cover gives, and `ios-sweep-2026-09-02` flagged it as owed to whichever walk owns
  the capsule — that is these walks, and it is still owed.
- **Reduce Transparency and Increased Contrast.** `GlassText` has a whole other branch for
  those two, resolving to the palette's `textPrimary` instead of `.primary` — so the answer
  to the glass-label question above is the answer for the *default* accessibility settings
  only. `sweepLaunch` has no lever for either setting, and neither is reachable by launch
  argument.
- **iPad.** `SweepIpad.swift` exists and the selection chrome on a wide sidebar layout is a
  different composition. Out of scope: this was asked on the phone.

## How to retake them

```bash
node scripts/corpus.mjs --simulator     # once, if the shelf is empty

for appearance in light dark; do
  for walk in testCaptureLibrarySelectingEmpty \
              testCaptureLibrarySelectingWithPicks \
              testCaptureLibrarySelectingEmptyAtLargestText \
              testCaptureLibrarySelectingAtLargestText \
              testCaptureLibrarySelectingAtTheEnd; do
    node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-selection-chrome-2026-09-04 \
      --only "ScreenshotTests/$walk" --appearance $appearance
  done
done
```

**Read the run summary, not the exit code.** `xcodebuild` exits 0 when a `-only-testing:`
filter matches nothing, and the four walks in `LibrarySelectionCapture.swift` are an extension
on `ScreenshotTests` — so the class-qualified name above is load-bearing. Each run should print
`1 test case(s): 1 passed, 0 failed, 0 skipped`. A `0 skipped` matters as much as the `1
passed`: a walk that skips passes and photographs nothing.

The pixel figures in this file were measured with a throwaway PNG reader over the frames
themselves, not with a tool in this repository. Any of them can be re-derived from the
committed frames.
