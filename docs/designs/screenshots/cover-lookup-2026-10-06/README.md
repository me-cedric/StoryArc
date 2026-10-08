# The cover-lookup setting, 2026-10-06

Topic evidence for `cover-for-every-publication`, sections 3 to 5. Keep these until that
change archives.

## What is here

| Frame | Condition |
| --- | --- |
| `ios-settings-privacy.png` | iPhone 17 Pro, light, default text |
| `ios-settings-privacy-dark.png` | iPhone 17 Pro, dark, default text |

All four were taken by `node scripts/capture-ios.mjs --only
SweepSettingsTests/testCaptureSettingsPrivacy` and
`…/testCaptureSettingsPrivacyAtLargestText`, which walk to the screen and prove the
navigation title before the shutter.

## What they show

The cover lookup, on the Privacy screen, **off**. The row names all three catalogues —
Open Library, Cover Art Archive, Audnexus — and the paragraph under it states that one
identifier and nothing else leaves the device. That is `cover-art`'s requirement that the
app "name the provider it would ask" before a reader turns the lookup on.

The two largest-text frames are the ones that matter for layout: the row is a label, a
provider list and a switch, and the switch does not grow while the text does. They are
scrolled to the row deliberately, because a frame of the top of that list would be a
picture of the part that did not change.

## What is missing, and why

**No Android frame.** The Pixel_7_Pro emulator on this machine would not stay responsive
long enough to walk to the screen: three cold boots each ended in *System UI isn't
responding* or in `uiautomator` answering `null root node returned by
UiTestAutomationBridge`, with the route harness stopping at Settings. The Android row is
drawn by `CoverLookupRow.kt`, which uses the repository's own `SettingsSwitchRow` plus one
`Text`, and `CoverLookupRowTest` asserts the default and the provider list — but neither is
a photograph. **Task 3.6 stays `[~]` until somebody takes one.**

**No frame of the candidate chooser, the web hand-off or the write-back confirmation.**
All three are built and tested, and none is reachable: the coverless well that opens them
is task 2.3, which another agent owns. Their commits carry `Visual-proof: flag`.
