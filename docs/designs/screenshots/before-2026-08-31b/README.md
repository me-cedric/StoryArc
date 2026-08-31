# The second batch of 2026-08-31, before

A second set the same day, so the pair beside `before-2026-08-31/` and `after-2026-08-31/`
is not disturbed: those record the morning's fixes, and the app in *this* set is already
built from them. Same date, later build, separate pair.

Two devices. iOS is the booted iPhone 17 Pro simulator (`11DFC984`, iOS 26.5, 402 pt wide);
Android is the `storyarc-j6` emulator (1080×2400 at density 420, so 411 dp wide) except
where a shot says tablet, which is the same emulator under `wm size 1600x2560` and
`wm density 240` — 1067 dp, past `design.md` §4's 840 dp breakpoint.

Every Android shot was taken with `pnpm capture:android`, every iOS shot with
`pnpm capture:ios`. Both walk to the screen rather than photographing whatever was in
front of them, which is the whole reason they exist — see the note on the wrong screen
below.

## What each shot is for

| Shot | What it shows |
| --- | --- |
| `ios-downloads` | **Foreign Codec, Harbour Lights 01 and 02 drawn as black rectangles.** The publications have no cover art and the downloads shelf drew nothing in their place. |
| `ios-library` | The same three publications on the library shelf **one tab away, in the same build, in the same second** — each drawing a well with its title and its format. This is the control, and without it the first shot is not evidence: a black rectangle could be a cover that had not decoded yet. |
| `ios-home` | The third surface that draws a well, included because the fix unified all three and this one had to be checked for a regression. |
| `android-downloads-phone` | The same defect on the other platform: nine of twelve fixtures are blank cards. |
| `android-epub-chrome-oled` | **The EPUB reader's chrome in cream while the app is set to OLED Dark.** |
| `android-library-oled-control` | Its control: the library on the same device at the same moment, drawn true black. The reader shot alone proves nothing — the app might simply not have been set to a dark appearance, and nobody could tell from the picture. |
| `android-downloads-tablet` | Five columns of 175 dp covers at a 1067 dp window. `COVER_MAXIMUM_WIDTH` is 168 dp. |
| `android-library-tablet` | One 168 dp cover in a 360 dp list pane at the same window, on the same device. |

## The two tablet shots are a measurement, not an impression

Both numbers above were read out of the live accessibility tree rather than off the
picture, and that mattered twice.

The first time, the density was read as the *physical* 420 rather than the *override* 240,
which scaled every figure by 0.571 and reported a 168 dp cover as 96 dp.

The second time, the correction mattered more. The library's single column in a 360 dp pane
looks like a shelf that could hold two, and that is what was nearly written down. It cannot:
the cover tier is taken from the **window** width, a 1067 dp window is expanded, its tier is
158 dp, and `2 × 158 + 12` is 328 against 320 dp of available pane. The arithmetic is right.
The open question is the *input* — measuring the window rather than the pane is a recorded
decision, and on a two-pane tablet it costs half the pane, because there the window is four
times what the shelf actually gets.

Neither of those is visible in a screenshot. That is the argument for measuring.

## The picture of the wrong screen

The first attempt at the iOS captures drove the Simulator with synthetic clicks at computed
window coordinates. The click missed the tab bar, the screenshot was taken anyway, and the
result was a picture of **Home** filed as **Downloads** — which is exactly the failure
`AuditWalk.swift` describes: a check that can silently measure the wrong screen is worse than
no check, because its green is worth nothing and its red sends you to the wrong file.

`UITests/ScreenshotTests.swift` reuses the walk the accessibility audit already uses, so the
capture and the audit cannot come to disagree about how to reach a screen.
