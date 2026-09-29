# Wave 2 of close-the-audited-gaps, 2026-09-29

`ios-shelves.png`: the Shelves screen on an iPhone 17 Pro simulator (iOS 26.5), light, taken by `SweepHomeTests/testCaptureShelves` after wave 2 landed. Wave 2 changed how server shelf covers are cached and the long press on shelf cards.

**The frame shows an open defect.** The empty collection "Lantern Run" draws a blank white card, with no placeholder and no name inside the frame. That is task 7.11 (decision D1: draw the coverless well, with the first member's format or none, and the shelf name). It runs in wave 3. Keep this frame as the "before" for that task.

The frame also shows Shelves on the Library stack, with a back button, which task 21.2 asked for. The settled-curl capture (`CurlWalkTests/testCaptureCurlSettled`) attached nothing on this run.
