# widgets, iOS frames, 2026-10-08

Device: iPhone 17 Pro Max simulator, iOS 26.4. Branch wave-3. Light and dark. The build is unsigned (no development team).

Task proved: close-the-audited-gaps 20.1, iOS widget on a simulator without a team.

## Frames

| Frame | What it shows |
| --- | --- |
| `ios-gallery-small-book` (+ dark) | The widget gallery: StoryArc "Continue reading", small, with the cover, the title and the progress bar. |
| `ios-gallery-medium-book` (+ dark) | The medium widget: cover, title, series, "50% read" and the bar. |
| `ios-home-small-book` (+ dark) | The small widget added to the home screen, showing "Harbour Lights" at 50%. The home screen was still in edit mode (the wallpaper and the minus badges show it). |

## What was watched

1. After the install and a launch, the app wrote `reading-snapshot.json` into the App Group container (`group.com.mecedric.storyarc`): title "Harbour Lights", `percentRead` 50, and a cover file. The unsigned build can read and write the App Group on a simulator.
2. Before that write, the gallery drew only the empty state ("No book in progress"). After it, the gallery and the home screen drew the book.
3. The widget extension is in the app bundle (`StoryArcWidget.appex`).

## Not framed

- The empty state ("No book in progress") was seen in the gallery before the snapshot existed. It was not kept; the Android set holds it.
- A tap on the widget opening the book.
- The percent after a book is read from inside the app and the app goes to the background. The reviewer found that the app does not write the snapshot then. Not tested on the simulator.

## How to repeat

Build, install and seed as in the other READMEs. Open a book in the app so the library reloads its positions. Press Home, long-press the empty home screen, tap Edit, Add Widget, search "StoryArc".
