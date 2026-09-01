# A failure names its publication — before and after, 2026-09-01

`named-failures-and-quieter-chrome` §1. Ten pictures' worth of claim in five files per
platform, and the *before* is the load-bearing half: on iOS the thing being replaced lived
six seconds, so a capture taken any later is a picture of a shelf.

## What is here

| Picture | Platform | What it shows |
| --- | --- | --- |
| `ios-skipped-toast-before.png` | iOS | `ScanSummary` — a Liquid Glass capsule reading *"2 couldn't be opened"*, floating above the tab bar with a cover's title showing through it. |
| `ios-skipped-toast-before-ax5.png` | iOS | The same at the largest text size, where the capsule sits **over** a cover. |
| `ios-skipped-notice.png` | iOS | `SkippedNotice` — the count, a named control leading to the list, and a dismissal, inline above the shelf and opaque. |
| `ios-skipped-notice-ax5.png` | iOS | The same at `accessibility-extra-extra-extra-large`. |
| `ios-skipped-list.png` | iOS | The list: two publications, **two different reasons**. |
| `android-skipped-count-before.png` | Android | The bare count at the foot of the shelf, in the `bottomBar`. |
| `android-skipped-count-before-ax.png` | Android | The same at `font_scale 2.0`. |
| `android-skipped-notice.png` | Android | The notice above the shelf, with the same two controls. |
| `android-skipped-notice-ax.png` | Android | The same at `font_scale 2.0`, where the `FlowRow` wraps the controls onto two lines and both keep their names. |
| `android-skipped-list.png` | Android | The bottom sheet, with the same two reasons kept apart. |

## What they settle

**The reasons were never missing — they were thrown away.** `LibraryScanner` on both
platforms has always emitted `skipped(path, reason)`, worded by `publication-formats`. The
before pictures are what a count looks like when it has eaten two sentences: *"2 couldn't be
opened"* is the same message whether a file is a container StoryArc does not read or a ZIP it
cannot decrypt. The list pictures are the same two files saying different things.

**The iOS before also settles the *obscures a cover* clause.** At the largest text size the
capsule lands squarely on the artwork with the cover showing through the material — which is
what `library-browsing` means by a notice that "does not float over the shelf's content in a
way that obscures a cover", and what the removed view's own doc comment described happening
without drawing the conclusion.

**Two defects were found by these captures and fixed before they were filed.** At the largest
text size the named control read *"What couldn't be open…"* — the controls sat beside the
sentence, and a row measures its unweighted children first. And the iOS list's large
navigation title truncated the same way. Neither is visible to a unit test: the width that
did the truncating belongs to the window.

## How to retake them

The device needs two publications that fail **differently**, and
`node scripts/corpus.mjs` writes them: `Sealed Archive.cb7` is a container StoryArc does not
read, `Locked Vault.cbz` is a ZIP it reads and cannot decrypt.

```bash
# iOS
node scripts/corpus.mjs --simulator
node scripts/capture-ios.mjs --out <dir> --only testCaptureSkippedNotice
node scripts/capture-ios.mjs --out <dir> --only testCaptureSkippedNoticeAtLargestText
node scripts/capture-ios.mjs --out <dir> --only testCaptureSkippedList

# Android
node scripts/corpus.mjs /tmp/corpus
# adb push one file at a time: a whole-directory push fails on the emulator's
# ext_data_rw mount with "stat failed … Input/output error".
adb push "/tmp/corpus/<file>" /sdcard/Android/data/app.storyarc.debug/files/<file>
node scripts/capture-android.mjs Library --out <dir>/android-skipped-notice.png
node scripts/capture-android.mjs Library --out <dir>/android-skipped-notice-ax.png --font-scale 2.0
```

The *before* pictures were taken by restoring the pre-change sources over the working tree
(`git checkout <base> -- apps/ios/Packages/StoryArcKit/Sources apps/ios/App`), capturing, and
putting them back. There is no capture route for Android's bottom sheet; that one was driven
by `adb shell input tap` against a `uiautomator dump`.

## Two things about the devices, recorded because both cost time

**The emulator's `/sdcard` FUSE mount had failed** — every `adb push` and `ls` answered
*"Transport endpoint is not connected"*, and `adb reboot` fixed it. It looks exactly like a
permissions problem and is not one.

**The emulator is shared between parallel agents.** An APK installed from another checkout
landed between one capture and the next, and the picture that came back showed the *old*
build with no error anywhere. `adb shell dumpsys package app.storyarc.debug | grep
lastUpdateTime` is what says which build is actually on the device — check it before
believing a capture that disagrees with the code.
