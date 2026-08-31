# The fourth batch of 2026-08-31, before

About as it stood before `quiet-shell-and-search` section 3 — no way to what changed in a
version, because there was nothing to reach. The app had shipped page curl, five typefaces,
six reading themes, OPDS, Kavita, SMB and a reading position that survives a rename, and had
never told anybody.

## How these were taken

Both trees were at `fc38d4f2`, whose only working change was the what's-new **model** — a
value, its store and their tests, wired to nothing. Neither About screen had changed, which
is what makes these a real "before": what is in them is what the previous release drew.

```bash
pnpm capture:ios --out docs/designs/screenshots/before-2026-08-31d --only testCaptureAbout
ANDROID_SERIAL=emulator-5554 pnpm gradle :app:assembleDebug   # then adb install -r
ANDROID_SERIAL=emulator-5554 pnpm capture:android "Settings > About" --out …/android-about.png
```

Devices: `StoryArc-iPhone17Pro` (11DFC984), and the `storyarc-j6` emulator started with
`-gpu host`. **Two emulators were attached**, so every `adb` call carried `ANDROID_SERIAL`;
without it `adb` refuses, and `pnpm capture:android` inherits the variable.

`ScreenshotTests.testCaptureAbout` is new in this change and walks Home → Settings → About.
It was added and compiled *before* the About screens were touched, so the picture below is
of the old screen taken by the new walk rather than of a new screen.

## What each one shows

| Shot | What is in it |
| --- | --- |
| `ios-about.png` | The version, the author, the free-and-open sentence, five links, and the acknowledgements. **No what's-new row**, between the free sentence and Repository, is the absence this batch exists to record. |
| `android-about.png` | The same screen and the same absence, drawn Material's way. |

## The caveat worth stating, again

`pnpm capture:android` drives whatever APK is installed; it does not build or install one.
The APK was rebuilt and installed by hand before this shot, because the previous batch's
"after" photographed a stale build and read exactly like a change that did not work.
