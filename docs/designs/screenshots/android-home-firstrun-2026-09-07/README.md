# Android home, first run, 2026-09-07

A physical OnePlus 7T Pro (`HD1911`), Android 14, API 34, 1440 by 3120. StoryArc built from
this worktree and installed with `:app:installDebug`. The app's data was cleared with
`adb shell pm clear app.storyarc.debug` before each frame, so each one is a genuine first
launch and not a library that happens to be empty.

Captured with `node scripts/capture-android.mjs Home --out <path> [--font-scale 2.0]`, which
walks to the screen, sets the condition and puts the device back.

| Frame | Condition |
| --- | --- |
| `android-home-firstrun-light.png` | Default text size |
| `android-home-firstrun-largest.png` | `font_scale 2.0` |

## What they show

Home offers **Open a comic** and **Add books**. The second is the menu that names the four
source kinds, which is what `sources` asks a first-run screen for and what home did not offer
until 2026-09-07. Task R.3 of `one-library-three-destinations` is that change; these frames are
task R.4.

**Both actions stay clear of the navigation bar at `font_scale 2.0`.** That is the whole
reason R.4 exists: the iOS half of this state once put its secondary action *behind* the tab
bar at the largest accessibility size, on the one screen whose job is to be reachable.

**The colours are the device's, not the brand's.** `AppSettings.useDynamicColor` defaults to
`true`, so Material You takes the wallpaper. The blue here is this phone's wallpaper and not a
theming defect. A frame of the brand palette needs that setting turned off.
