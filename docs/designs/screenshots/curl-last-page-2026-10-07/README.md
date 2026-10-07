# A curl on the last page reveals the end screen, 2026-10-07

Task 8.5 of `close-the-audited-gaps`, decision D10. Nothing lifts into empty space. The end
screen is the next sheet.

Comic: `Tidal Reach 01.cbz` (Android, 8 pages, from the share) and `Fine Print.cbz` (iOS, 3
pages). Page turn: Curl.

## Android, emulator `storyarc-ci`

| Frame | What it proves |
| --- | --- |
| `android-curl-last-page-held-near.png` | A held drag (`adb shell input motionevent`, finger at x = 650 of 1080). The last page lifts. The end screen shows right of the fold. |
| `android-curl-last-page-held-far.png` | The finger at x = 320. The end screen ("Finished", Back to the last page, Library) shows under the lifted sheet. No blank sheet shows. |
| `android-curl-last-page-landed.png` | After release. The end screen is up. |

The dark appearance gave frames that are identical byte for byte. The comic reader's matte
and the end screen do not follow the system appearance, so no dark frame is kept.

## iOS, simulator iPhone 17 Pro Max, iOS 26.4

A tap on the trailing third of the last page, recorded with `xcrun simctl io recordVideo`
(`CurlWalkTests/testCaptureCurlLastPageTapped`). The recorder kept 12 frames of the roll.

| Frame | What it proves |
| --- | --- |
| `ios-curl-last-page-tap-0-flat.png` | The last page, before the tap. |
| `ios-curl-last-page-tap-1-fold-at-the-right-edge.png` | The turn has begun. The end screen shows right of the fold. |
| `ios-curl-last-page-tap-2-rolled-off-at-the-left-edge.png` | The sheet has rolled off. The end screen is under it. |
| `ios-curl-last-page-tap-3-landed.png` | The end screen is up. In all 12 recorded frames, the last page does not show again after the sheet leaves (commit a42e3319). |

## Owed: an iOS held drag

XCUITest cannot keep a touch down across a screenshot. `press(forDuration:thenDragTo:...)`
held at 66 percent of the width gave a recording with no fold frame: the end screen shows at
once. A held iOS frame needs a touch source the harness does not have. The Android frames above
are the held-drag proof, and the iOS tap frames show the same end screen under the sheet.

## How to repeat

```bash
# iOS
xcrun simctl io <udid> recordVideo --codec h264 --force /tmp/tap.mov &
node scripts/capture-ios.mjs --out /tmp/shots --only CurlWalkTests/testCaptureCurlLastPageTapped --device <udid>
# then stop the recording and cut the frames with ffmpeg
# Android
adb shell input motionevent DOWN 1000 1200   # then MOVE steps to x = 320, screencap, UP
```
