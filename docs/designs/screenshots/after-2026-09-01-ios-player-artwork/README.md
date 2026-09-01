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

### The sleep timer states a remaining time — `audiobooks-and-playback` §5.3

`ios-sleep-timer-set.png` shows the control reading `5:00 left`, and the test asserts the same
string as the control's announced **value** while *Sleep timer* remains its name. It announced
only the number before, which is a value with no name, and `audio-playback` asks a screen
reader for both.

**This is one frame, and the requirement wants two — said plainly rather than dressed up as an
exception.** The defect §5.3 fixed was a number that *was* displayed and never moved, so a
single picture of `5:00 left` cannot tell the fix from the bug. What proves the moving is
`SleepTimerRunningTests`: the count going down, the hold while paused, the ramp reaching the
source's volume, the elapsing, and the rewind — with the paused hold, the ramp shape and the
end-of-chapter re-read each mutation-checked.

**Why the second frame could not be taken, which turned out to be a defect rather than a limit
of the capture.** The countdown moves only while the book plays, and the walk leaves the session
paused on purpose. Pressing any transport control inside the player **dismisses the player**:
`PlayerDock` hosts the player's `.sheet` on a view inside `if let bar = centre.compact`, so the
moment `CompactPlayer`'s value changes — which pressing play does, and which crossing a chapter
does — the sheet's host is rebuilt and the presentation is torn down.

Measured rather than guessed, over four runs:

1. `app.buttons["Play"].firstMatch` bound to the **compact bar behind the sheet**, which is not
   hittable, so the book never played and two frames came back byte-identical at `5:00 left`.
   Only a comparison assertion caught that; a capture filed on the strength of the eye would
   have been filed as proof.
2. Reaching the first chapter through the chapter list fixed the starting position and exposed
   the dismissal: tapping a chapter row left the **publication page** on screen with the compact
   bar still playing.
3. A skip-back tap — one control, no sheet — did exactly the same.
4. **The same run against the pre-§3.2 `FullPlayerView`, Close pill and all, failed
   identically.** That is what proves the dismissal predates this change rather than being
   caused by it.

Two frames become possible as soon as that host is stabilised. It is out of this change's scope
and is reported as a separate defect.
