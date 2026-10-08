# Android: a book that ends on a failed part — 2026-10-07

Task 2.5 of `audiobooks-and-playback`. `PlayerFinishedScreen` states how much could not be played.

| Frame | What it proves |
| --- | --- |
| `android-player-finished-damaged*.png` | After `truncated.m4b` (pushed as *Cut Short*) plays to its end, the player reads "Nothing is playing." and "1 part could not be played", with "Back to the book". Light and dark, font scale 1.0 and 2.0 (`-ax`). |

**What ExoPlayer reports for this file.** media3 1.11.0 on the API 35 emulator raises
`ExoPlaybackException: Source error`, caused by `java.io.EOFException`, a few seconds after the
file starts. The app counts one failed part and shows the surface above. This is the Android
engine report that the task owed.

## How to repeat

Push `packages/test-fixtures/audiobooks/truncated.m4b` as `Cut Short.m4b` into
`/sdcard/Android/data/com.mecedric.storyarc.debug/files/`. Then run
`node scripts/capture-android.mjs "Player > finished with a damaged part" --out <file>.png`.
The app reopens on the finished surface, so later conditions can use
`node scripts/capture-android.mjs Home --out <file>.png [--dark] [--font-scale 2.0]`.
