# iOS — the player's artwork, its chrome and its sleep timer, 2026-09-01

Taken on the booted `StoryArc-iPhone17Pro` simulator (iOS 26.5) by
`UITests/PlayerScreenshotTests`, which walks to an audiobook and drives the player rather
than photographing whatever is in front of it.

`scripts/capture-ios.mjs` hardcodes `StoryArcUITests/ScreenshotTests`, so it cannot drive
this class. The two commands it runs, spelled out:

```bash
xcodebuild test-without-building -project apps/ios/StoryArc.xcodeproj -scheme StoryArc \
  -destination id=<udid> -only-testing:StoryArcUITests/PlayerScreenshotTests \
  -resultBundlePath /tmp/shots.xcresult
xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
```

The device needs an audiobook on its shelf first, and the walk fails by name rather than
photographing an empty one — `../after-2026-09-01-ios-player/README.md` says how to put one
there.

## The "before" is the previous folder, not a file in this one

`../after-2026-09-01-ios-player/ios-full-player.png` and its
`ios-full-player-largest-text.png` were taken from the same test on the same device before
these three changes landed, and are committed. Read them as the pair for everything below.

| Picture | What it shows |
| --- | --- |
| `ios-library-nothing-playing.png` | **The control.** The shelf with no session running. |
| `ios-compact-player.png` | The compact bar while an audiobook is loaded and paused. |
| `ios-full-player.png` | The full player: the title as artwork, no Close pill, the grabber. |
| `ios-full-player-largest-text.png` | The same at `AccessibilityXXXL`. |
| `ios-sleep-timer-set.png` | A five-minute sleep timer just chosen. `5:00 left` on the control. |
| `ios-sleep-timer-counting.png` | **The second frame**, after three seconds of playback. The value has moved. |

## What each pair settles

### The artwork is the title, not a glyph — `audiobooks-and-playback` §4.4b

`audio-playback` requires that a publication with no cover gets "the same coverless treatment
every other surface draws — the title set as artwork — rather than a generic glyph".

The before shows `Image(systemName: "headphones")` in a 320 pt well. The after shows
**`Sea Room`** set into the same well. The comment at that line claimed the glyph was "the
same placeholder the library draws", which was wrong: the library draws `CoverlessWell`.

`ios-full-player-largest-text.png` is the half a picture at the default size cannot settle.
`CoverlessWell` *drops* its title at an accessibility text size, because a `headline` in a
146 pt grid cell holds part of one word. This well is more than twice as tall and holds the
title whole at `AccessibilityXXXL` — which is why the player draws it unconditionally and the
library does not. Compare the two at that size: the transport is still on screen in both, and
removing the Close pill gave the artwork back the space the pill occupied.

**The lock screen is not photographed here, and that is a gap, not an exception.** The same
view is rendered to PNG for `MPMediaItemPropertyArtwork` — one treatment, not two — but
photographing a simulator's lock screen from a UI test is not something XCUITest can reach.
What *is* proven is that the render path runs: it crashed the app the first time (see below),
so the handler is demonstrably called.

### The Close pill gives way to the grabber — `named-failures-and-quieter-chrome` §3.2

The before has a `Close` pill top-trailing, over the artwork, and **no grabber**. The after
has the grabber and no pill.

A picture cannot prove the sheet still dismisses, so
`PlayerAuditTests.testASheetIsStillDismissibleWithoutACloseButton` does: it fails first if any
button labelled *Close* is on the player, then drags the sheet away and asserts the listener is
back on the shelf with the compact bar. The VoiceOver route is `.accessibilityAction(.escape)`
and is not walked, because XCUITest has no API for the escape gesture — said here rather than
left as a silent gap.

### The sleep timer states a remaining time, and is seen to move — `audio-playback` §5.3

`ios-sleep-timer-set.png` shows the control reading `5:00 left`, and the test asserts that same
string as the control's announced **value** while *Sleep timer* stays its name. It announced only
the number before, which is a value with no name, and `audio-playback` asks a screen reader for
both.

**Two frames, because one cannot tell the fix from the defect it replaced.** The defect §5.3
fixed was a number that *was* displayed and never moved — the control existed, the sheet offered
the durations, and nothing in the app ever ticked the countdown or stopped the book. A single
picture of `5:00 left` is exactly what that would have produced. So `ios-sleep-timer-counting.png`
is the pair, taken after three seconds of playback, and the walk **asserts** the value moved as
well as photographing it: a regression fails the build rather than waiting for somebody to
compare two PNGs by eye.

The assertion unwraps the value rather than comparing optionals, and checks its `m:ss` shape as
well as the difference. `XCTAssertNotEqual(nil, "5:00 left")` passes, so a control that stopped
announcing a value at all would have satisfied the naive form — a worse defect, reported as a
pass.

The walk plays for three seconds rather than waiting out a minute, since the value moves every
second, and deliberately does not play to the end: the audiobook fixture is six seconds long and
a finished session closes the player on purpose.

#### This pair was owed for a day, and what blocked it was a real defect

Kept because the measurements cost four runs and each one is a trap that will recur.

The countdown moves only while the book plays, and pressing any transport control inside the
player **dismissed the player**: `PlayerDock` hosted the `.sheet` on a view inside
`if let bar = centre.compact`, so the moment `CompactPlayer`'s value changed — which pressing
play does, and which crossing a chapter does — the sheet's host was rebuilt and the presentation
torn down.

1. `app.buttons["Play"].firstMatch` bound to the **compact bar behind the sheet**, which is not
   hittable, so the book never played and two frames came back byte-identical at `5:00 left`.
   Only a comparison assertion caught that; a capture filed on the strength of the eye would have
   been filed as proof. **The walk now picks the first *hittable* match**, which is why.
2. Reaching the first chapter through the chapter list fixed the starting position and exposed
   the dismissal: tapping a chapter row left the **publication page** on screen with the compact
   bar still playing.
3. A skip-back tap — one control, no sheet — did exactly the same.
4. **The same run against the pre-§3.2 `FullPlayerView`, Close pill and all, failed
   identically.** That is what proves the dismissal predated the pill's removal.

Fixed by moving the presentation to the shell's `TabView`, which outlives a session;
`PlayerSheet.swift` carries the account. The assertion that the player survives its own play
button is part of this same walk now, so the block cannot come back unnoticed.

