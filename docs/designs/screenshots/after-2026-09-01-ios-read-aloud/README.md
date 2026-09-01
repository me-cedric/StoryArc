# iOS — the voice driving the player, 2026-09-01

Taken on the booted `StoryArc-iPhone17Pro` simulator (iOS 26.5) by
`UITests/ReadAloudPlayerTests`, which walks to a reflowable EPUB, opens the reader's menu,
starts read-aloud, pauses it, closes the reader, and photographs what is left.

```bash
xcodebuild test -project apps/ios/StoryArc.xcodeproj -scheme StoryArc \
  -destination id=<udid> -only-testing:StoryArcUITests/ReadAloudPlayerTests \
  -resultBundlePath /tmp/shots.xcresult
xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
```

`scripts/capture-ios.mjs` hardcodes `StoryArcUITests/ScreenshotTests`, so it cannot drive
this class. The two commands above are what it does, spelled out.

| Picture | What it shows |
| --- | --- |
| `ios-read-aloud-compact-bar.png` | The publication page with the voice still going behind it, carried by the **shared** compact bar. |
| `ios-read-aloud-full-player.png` | The full player, driven by the voice rather than by a file. |

## What these settle, and why they could not be taken before

`audiobooks-and-playback` §4.2 asked for **one** compact bar behind both sources. There
were two: `PlayerDock` for a narrated audiobook and a `ReadAloudDock` of its own for a
voice, because a read-aloud session driving `PlayerCentre` would have offered a speed
control that did nothing — Readium 3.11.0 sets no rate on a synthesised utterance — and
`audio-playback` forbids a control that is "present and refusing".

`SpeechRate` and `SpokenVoice` answer that through the `AVTTSEngineDelegate` Readium points
the caller at, so the second bar is gone. **`ios-read-aloud-full-player.png` is the proof
the control is real**: it shows `1×` beside the chapter list and the sleep timer, on a
session produced by the speech synthesizer.

**`ios-read-aloud-compact-bar.png`** — one bar, above the four destinations, which sit
where they sit in `after-2026-09-01-ios-player/ios-library-nothing-playing.png` (the
control for the same claim). It names *Harbour Lights 01* and the chapter *Chapter 1* —
read from the publication's own navigation through `SpokenParts`, not from the file name.
Its three controls are the chevron that opens the player, pause, and stop: the row itself
is *Back to the book*, which is `ebook-reader`'s "the compact bar is how the reader gets
back to it", and the chevron is `audio-playback`'s "a way to open the full player". A
narrated audiobook gets no chevron, because there its row **is** the player —
`CompactPlayer.wayBack`.

**`ios-read-aloud-full-player.png`** — and the important thing here is what is **absent**.
There is no scrub control. In its place the line reads *Part 1 of 4*, because a synthesised
voice has no duration and `design.md` requires a source that does not know to show
"position without a total rather than inventing one". The same view draws a scrubber with
`0:00 / 0:02` for the M4B fixture in the sibling folder: one file, one branch, and the
branch asks the *time* whether it has a total rather than asking which source is playing.

The skip glyphs are the sentence pair rather than `gobackward.15`/`goforward.30`, which is
`SkipUnit.sentence` reaching a pixel.

## What these do not show

The session is **paused** in both, for the reason the sibling folder gives: a capture that
let it run would photograph one chapter and then another.

Neither is dark, and neither is at the largest text size. The player's layout at
`AccessibilityXXXL` is photographed in the sibling folder and is the same view.

Nothing here has been through VoiceOver by a person. What it has been through is the
platform's own audit — `UITests/PlayerAuditTests`, six surfaces, run on the same simulator
the same day. **No unlabelled control anywhere, and no findings at all at
`AccessibilityXXXL`.** The findings it did return, and the element each names, are in
`tasks.md` §8.1; the one that belongs to the player rather than to the screen behind it is
in §8.4, and it is that the compact bar truncates its title where `audio-playback` asks it
to grow. That is not fixed here: the accessory slot's height belongs to the system.

## One thing the walk cost, recorded because it will happen again

The read-aloud row is the last row of the reader's menu and sits **below the fold** on an
iPhone. A SwiftUI `List` is lazy, so a row that has never been on screen is in no
accessibility tree at all: `app.buttons["Read aloud"]` came back empty and the walk read
that as *this publication cannot be spoken*, which is a state `ebook-reader` genuinely
allows. It looked exactly like a defect in the publication. Forcing the row to render
unconditionally and finding the query still empty is what ruled the app out and left the
query — the walk swipes now.
