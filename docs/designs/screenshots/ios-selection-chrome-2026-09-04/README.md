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
| `ios-library-selecting-picked-de.png` | library shelf, top | selecting, **2 picked**, **German** | light | default |

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

## Two things the pictures settled that nobody asked — both now fixed

These frames were **retaken on 2026-09-04** after both were fixed. The originals are what
found them, and the account below is what they showed then and what they show now.

### The named row was never drawn on this phone

The `ViewThatFits` offered one row twice — every name or no name — and three names at
`.controlSize(.large)` need more than the 338 pt the capsule is offered
(402 − 2 × gutter − 2 × md). So the `.iconOnly` branch was taken at the **default** text
size, not only at the accessibility sizes as the source comment and §3b.5 both claimed. Every
original frame showed three bare glyphs: `text.badge.plus`, `arrow.down.circle`,
`checkmark.circle`.

That was not only ugly, it broke a sentence this change had already written.
*Every action names itself* requires a glyph standing alone to be "one whose meaning the
platform already establishes, **not one chosen to save room**" — and a `ViewThatFits` fallback
is a room-saving mechanism by construction. Two of the three glyphs failed the first half too:

- **`text.badge.plus`** reads as a plus badge on ruled lines. Apple uses it for *Add to
  Playlist* — always as a named row inside a menu, never bare in a toolbar — and the action
  opens a chooser rather than doing something.
- **`checkmark.circle`** is well established in general and **not established here**: forty
  points above the capsule the picked covers carry a filled disc with a white check and the
  unpicked carry an empty ring, so a ring-with-a-check in the same frame is the visual union of
  the two selection states. One mark, two meanings, one screen.
- **`arrow.down.circle`** is fine bare, and stays so.

**What it draws now**, degrading by control rather than by label style — and each row below was
photographed rather than predicted:

| tier | draws | proved by |
| --- | --- | --- |
| 1 | `⬇ Download`  `✓ Mark as read`  `⋯` | `ios-library-selecting-picked.png` — English, default size |
| 2 | `⬇`  `✓ Als gelesen markieren`  `⋯` | `ios-library-selecting-picked-de.png` — German, default size |
| 3 | `⬇`  `⋯` | `ios-library-selecting-ax5.png` — `AccessibilityXXXL` |

German is why tier 2 exists: *Als gelesen markieren* is 21 characters against *Mark as read*'s
12, so English draws both names and German draws one. Shortening the English copy was rejected
outright — it cannot reach German, and `library.bulk.download` and `library.mark.read` are also
used by the download confirmation dialog, `AddToShelfMenu` and `KavitaChapterList`, so it would
have rewritten four surfaces that have no layout problem.

**Tier 3 loses no action.** *Mark as read* is `AddToShelfMenu`'s own first row, so where the
button will not fit the action is still there, named. *Add to…* is in that menu at every tier.

### The inert capsule was pixel-identical to the live one

Cropping the capsule out of the 0-picked and 2-picked frames at the same appearance and text
size gave **0 differing pixels** — in light, in dark, and at AX5 where the worst channel delta
was 1. The control proves the frames were genuinely two states: over the first cover's tick the
same pair differs on 45 % of pixels with a worst delta of 202.

The cause is `.storyArcGlassText(.primary)` setting an explicit `foregroundStyle` *after*
`.disabled(…)`; an explicit foreground style defeats the dimming `.disabled` would otherwise
apply. So `.disabled` was doing its behavioural half and nothing visual, and §3b.4's whole
argument — that a shown, inert capsule "says what the mode is for before anything is picked" —
held only for a reader who tried one of the actions.

Since the glass text takes the system's dimming away, the dimming is now the capsule's own: one
`.opacity` tied to the same expression `.disabled` reads. Measured after the fix, on the same
four pairs:

| pair | before | after |
| --- | --- | --- |
| light, default | 0 of 27 900 | **3 100** differing |
| dark, default | 0 of 27 900 | **3 084** differing |
| light, AX5 | 0 of 110 500 (worst delta 1) | **26 426** differing |
| dark, AX5 | — | **26 407** differing |

**A device check now guards it**, because none of the above is visible to a host test:
`ScreenshotTests/testTheInertCapsuleIsDimmerThanTheLiveOne` photographs each control with
`XCUIElement.screenshot()` — the element, not a rectangle, so there is no scale arithmetic and
no rect to get silently wrong — and measures *ink mass*, the mean distance of the crop's pixels
from its own median luma. Since `.opacity` composites as `α·ink + (1 − α)·background`, the
ratio of the two masses lands on α itself: measured **0.4129** against an `inertOpacity` of
0.4, in both appearances. The band is two-sided — under 0.75 so an undimmed control fails
(deleting the line returns exactly 1.000), over 0.10 so a hidden one fails too, because §3b.4
wants the actions present and inert rather than absent.

In light at the default size the glyph strokes go from `rgb(0,0,0)` to `rgb(148,146,146)`,
which is what `0.4 × 0 + 0.6 × 245` predicts against the glass ground — so the remedy is
measured rather than assumed. **Android had the same defect from the mirror-image cause**: an
`IconButton` dims a disabled child by lowering `LocalContentColor`, and every `Icon` there
passed `tint = palette.accent`, which never reads it. Two platforms, two explicit colours, one
bug, and one rule: state the colour where the control can still take it away.

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

The German frame is light-only and runs once, outside that loop — the tier it proves is a
function of the language, not the appearance:

```bash
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-selection-chrome-2026-09-04 \
  --only "ScreenshotTests/testCaptureLibrarySelectingInGerman" --appearance light
```

**Read the run summary, not the exit code.** `xcodebuild` exits 0 when a `-only-testing:`
filter matches nothing, and the four walks in `LibrarySelectionCapture.swift` are an extension
on `ScreenshotTests` — so the class-qualified name above is load-bearing. Each run should print
`1 test case(s): 1 passed, 0 failed, 0 skipped`. A `0 skipped` matters as much as the `1
passed`: a walk that skips passes and photographs nothing.

The pixel figures in this file were measured with a throwaway PNG reader over the frames
themselves, not with a tool in this repository. Any of them can be re-derived from the
committed frames.
