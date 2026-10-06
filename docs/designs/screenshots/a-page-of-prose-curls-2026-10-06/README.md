# A page of prose curls — 2026-10-06

Task 8.12 of `close-the-audited-gaps`, which closes
`reader-theming-and-page-transitions` 4.3b. The curl was refused over reflowable text on both
platforms: it needs the incoming page as a second texture and nothing had taken one, so the
picker listed Curl with *"Not available for books whose text resizes."* and a reader who chose
it got a Slide.

| Frame | What it shows |
| --- | --- |
| `ios-epub-curl-light.png` | The fold mid-roll over a page of body text, with no finger on the screen. |
| `ios-epub-curl-dark.png` | The same roll one turn later, with the device in its dark appearance. |
| `ios-epub-curl-settled-light.png` | The page the roll landed on, which is what proves the turn happened. |
| `ios-epub-curl-settled-dark.png` | The same, in the dark appearance. |

## What the mid-roll frames prove, and how to read them

Four things are visible in `ios-epub-curl-light.png`, and each is a separate claim:

1. **The outgoing page is a texture, and it is the right one.** The left of the frame is the
   page the reader was on, lying flat — *Chapter 1* and its first paragraphs.
2. **The turned sheet shows that page's back.** The word *Sentence* appears **mirrored** and
   dimmed across the roll. That is the shader's back face, which samples the outgoing raster
   reflected about the fold. A sheet that was not a raster could not do this, and a mirrored
   image at full brightness would read as a reflection rather than as paper.
3. **The incoming page is a second texture, not a copy of the first.** The right of the frame
   is already the next page: its lines break in different places from the ones on the left.
   This is the whole of 4.3b — before this change there was no second raster to reveal.
4. **The fold is a curve.** The crease leaves the head of the page almost vertical and
   steepens towards the foot, which is decision D12's bend, running here over text rather than
   over a comic page. `../a-tap-that-curls-2026-10-06/README.md` measures the same curve.

**No finger is on the screen in either mid-roll frame.** The turn was asked for by a tap on
the trailing third, and the roll is the animation `EpubReaderModel.turnWithCurl(forward:)`
runs after it. A curl at rest is a page — `CurlWalk.swift` carries the long version of that
argument — so a settled frame alone could not tell Curl from Slide. The settled frames are
here for a different reason: they show the live web content back on screen, on the page the
roll landed on, with no raster and no chrome baked into it.

## The device, and what was on it

An `iPhone 17 Pro` simulator on iOS 26.5, seeded by `pnpm seed:ios:ui`. The publication is
*The Long Field*, named rather than reached for: a cover says `EPUB` whether the book reflows
or is pre-paginated, two of the corpus's four EPUBs are fixed-layout, and a fixed-layout book
opens in the *comic* reader. `SweepEpubReaderTests.openReader` names the same book for the
same reason.

## How they were taken

`EpubCurlWalk.swift` is the walk. It opens the book, reaches *Page turn* — which on the
reflowable reader is a section of the axes screen, three sheets deep behind the menu and
*Reading themes* and *Customise* — chooses Curl, and taps the trailing third.

XCUITest has no primitive that leaves a touch down across a screenshot, and a screenshot taken
after a tap is a picture of the settled page, so the mid-roll frames come from a screen
recording around the walk. That is the method `CurlWalk.swift` already records for iOS:

```bash
xcrun simctl io <udid> recordVideo --codec h264 /tmp/ios-curl.mov &
pnpm capture:ios --out /tmp/shots --only EpubCurlWalkTests --device <udid>
# then, after stopping the recording:
ffmpeg -i /tmp/ios-curl.mov -ss <t> -t 1 -vf fps=60 f%03d.png
```

`--appearance dark` takes the dark pair, and puts the simulator back afterwards.

## What is **not** photographed here, and why

**A dark *page*.** The two appearances differ in the chrome and not in the page: an EPUB's
reading theme is the reader's own — *Paper*, here — and follows the device only for a reader
who linked the two. The chrome is hidden in a mid-roll frame, so the dark frame shows the same
cream page as the light one. It is here because §6 of `AGENTS.md` asks for both, and this
paragraph is what it tells you.

**The text size.** The walk photographs the roll, and the roll is a texture of whatever the
page was. A larger text size changes what is printed on the sheet and nothing about how the
sheet moves.

**Android.** `EpubPageTurns.withCurl` is the twin and is asserted by `ReflowableCurlTest`, and
it is **unphotographed**. The `Pixel_7_Pro` emulator on this machine spent this session
raising *"System UI isn't responding"* under the capture harness — on the launcher as well as
in the app, and before any curl could run — so nothing photographed there would be evidence of
anything. The Android frame is owed, and `close-the-audited-gaps`' `tasks.md` records it as
owed rather than taken.
