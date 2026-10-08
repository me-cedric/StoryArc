# Home-screen widget, Android, 2026-10-08

Visual proof for `close-the-audited-gaps` task 20.1, Android half. The iOS half is in `../widgets-ios-2026-10-08/`.

Device: emulator `storyarc-ci` (API 35, google_apis, arm64), run headless with `-memory 2048`. Debug build `com.mecedric.storyarc.debug` at commit `62eba386`.

## Frames

| Frame | What it proves |
| --- | --- |
| `android-widget-picker.png` | The widget picker lists StoryArc "Continue reading", 2 x 2. The card shows the app icon, because the widget declares no preview image. |
| `android-widget-picker-dark.png` | The same picker in dark. The StoryArc row is closed in this frame, so it shows the row but not the preview card. |
| `android-widget-no-book.png`, `-dark` | With no book in progress, the widget says "No book in progress". The resize handles show because the widget was just placed. |
| `android-widget-2x2-book.png`, `-dark` | After "Blue Harbour 02" is opened and closed, the 2 x 2 widget shows the cover, the title and a progress bar. |
| `android-widget-3-wide-book.png`, `-dark` | At 3 cells wide, the widget also shows the series and "40% read". |

Largest text size is not framed. A widget does not follow the app text size.

## Emulator proof of the device step

The widget runs on the emulator. The app wrote the snapshot, the launcher drew the widget, and the widget showed the right title, cover and percent for the book last read. The owner still checks the step on a real phone. See `device-checklist.md`.

## How to repeat

1. `pnpm build:android`, then `adb install -r apps/android/app/build/outputs/apk/debug/app-debug.apk`.
2. Long-press the home screen, open Widgets, search "StoryArc", and place "Continue reading".
3. `pnpm capture:android "Widget > open Blue Harbour 02" --out /tmp/x.png` opens the book. Press Home.
4. Set the look with `adb shell cmd uimode night yes|no`.

## Known gaps, not fixed here

- The widget shows the book at the last close or app start, not at each page turn. A reader who presses Home from inside a book sees the old percent. The reviewer reported this as a code gap.
