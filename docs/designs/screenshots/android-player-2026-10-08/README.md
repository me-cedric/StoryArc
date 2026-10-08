# Android player, 2026-10-08

Visual proof and emulator proofs for `close-the-audited-gaps` 23.6 and `audiobooks-and-playback` 4.4b, 3.6, 7.3, 17.3 and 8.1. The iOS half is in `../player-ios-2026-10-08/`.

Device: emulator `storyarc-ci` (API 35, google_apis, arm64), headless. Debug build `com.mecedric.storyarc.debug` at commit `62eba386`. The task text names the package `app.storyarc.debug`. That name is old. Use `com.mecedric.storyarc.debug`.

## Frames

| Frame | What it proves |
| --- | --- |
| `android-player-damaged-before.png`, `-dark` | Task 23.6. A book that ended on a damaged part shows "Nothing is playing.", "1 part could not be played" and the button "Mark as finished". Book: "Cut Short" (`truncated.m4b`). |
| `android-player-damaged-after.png`, `-dark` | Task 23.6. After the tap, the line "Marked as finished" replaces the button. |
| `android-player-finished-next-row.png` | Task 7.3. A finished audiobook in a series ("Dawn Road #1") shows the button "Next: Dawn Road #2". |
| `android-shade-coverless-closed-player.png`, `-dark` | Task 4.4b. A coverless audiobook plays and the full player is closed. The notification shade shows the drawn well (headphones glyph and "M4B"), not a blank square. |
| `android-shade-resumed-after-kill.png` | Task 3.6. After the process was killed and a media key pressed, the shade shows "Sea Room" playing again, with a pause button. The row has no picture. See the defects below. |

## Emulator proofs

### 3.6, resume after process death

1. Play "Sea Room" (six seconds, three chapters), jump to chapter two, pause. The media session reports `PAUSED, position=2000`. `shared_prefs/app.storyarc.playback.memory.xml` holds `position=2000`, `index=1`.
2. `adb shell am force-stop com.mecedric.storyarc.debug`. `pidof` is empty and `dumpsys media_session` lists no session for the app.
3. `adb shell cmd media_session dispatch play`. A new process starts. `dumpsys media_session` reports `active=true`, `PLAYING, position=2043, speed=1.0`. Playback began at the saved 2000 ms. "Last MediaButtonReceiver" names `androidx.media3.session.MediaButtonReceiver`.
4. The shade frame was taken 1.2 s after the key press. The script `resume-after-kill.sh` in this folder runs all four steps: `./resume-after-kill.sh out.png`. It needs the routes `Player > Sea Room paused` and a booted emulator.

### 7.3, finished audiobook

Route `Player > finished series audiobook` plays "Dawn Road 01" (six seconds) to the end. Results:

- The finished mark: all three chapters of "Dawn Road #1" show "Finished" on the page.
- The next row: the finished screen shows "Next: Dawn Road #2" (frame above), and the page lists "Other issues in this series: #2".
- The sweep with the setting on: not run on the emulator. The sweep removes only a downloaded book, and neither mock server (Kavita, OPDS) serves audio. The host test in the lane covers it.

To make two audiobooks in one series with different content, copy `chaptered.m4b` and append one empty `free` box to the first copy and two to the second. Two files with the same bytes are one publication, so the second one never shows.

### 17.3, deferred chapter seek and migration

- `pnpm gradle :core:persistence:connectedDebugAndroidTest` on the emulator: 67 tests, 0 failures. `ProgressMigrationTest` ran 10 of 10, including `theUpgradedTableTakesAListeningPosition` and `aPlaceInTheFirstPartKeepsItsOffset`. `MIGRATION_3_4` ran under a real SQLite for the first time.
- Play "Dawn Road #2" into chapter three, pause, force-stop. `progress.db` holds `part_index=2, offset_millis=0, is_finished=0` (4000 ms). After the restart, the book page shows chapters One and Two "Finished" and Three "In progress". "Listen" then resumed at the saved place and played to the end (offset 2106, finished).
- The task text says the `storyarc-ci` image does not show MP4 chapters. It does here: the player listed chapters One, Two and Three.
- A book already marked finished starts again from its beginning on "Listen". The proof therefore used a book never finished.

### 8.1, accessibility scan on the player routes

The scan found 4 problems on each of the routes `Player` and `Player > Sea Room playing`:

```
SMALL  View 67.0x37.3dp "5 min"
SMALL  View 74.7x37.3dp "15 min"
SMALL  View 74.7x37.3dp "30 min"
SMALL  View 74.7x37.3dp "45 min"
```

The sleep-timer chips are 37.3 dp high. The floor is 48 dp. The routes `Player > chapters`, `Player > compact bar` and `Player > finished series audiobook` report 0 problems. I did not change product code. The command `node scripts/smoke-android.mjs --a11y Player` did not finish within 300 s after I added routes to the map, so I ran each route alone with the scan from `scripts/a11y-scan.mjs`. The first run printed 2 problems on `Player` and 4 on `Player > Sea Room playing`. The count on `Player` changes with how much of the chip row is on screen.

## Defects found, not fixed

1. Sleep-timer chips below 48 dp (task 8.1). See above.
2. A book resumed after process death has no drawn artwork in the shade (task 4.4b, `shade-resumed` frame). `PlaybackMemory` keeps only the artwork address of the book. The reviewer proposed `PlaybackMemory.rememberArtwork` and a call at the end of `PlaybackHost.setArtwork`.
3. The finished screen of a series book says "Nothing is playing." above "Next: ...". This is the existing heading for a listener's own stop, kept on purpose by the worker.

## Owed

- Task 4.4b, the shade after a car start (Desktop Head Unit). No head unit is installed on this machine.
- Task 7.3, the sweep with the setting on, end to end. See above.

## How to repeat

1. `pnpm build:android`, `adb install -r`, and push the fixtures into `/sdcard/Android/data/com.mecedric.storyarc.debug/files/`: `Sea Room.m4b` (copy of `chaptered.m4b`), `Cut Short.m4b` (copy of `truncated.m4b`), `Dawn Road 01.m4b` and `Dawn Road 02.m4b` (as above).
2. `pnpm capture:android "Player > finished with a damaged part" --out f.png [--dark]`, then `Player > damaged mark as finished`.
3. `pnpm capture:android "Player > finished series audiobook" --out f.png`.
4. For the shade: start "Sea Room", press Back and Home, then `adb shell cmd statusbar expand-notifications` and `adb exec-out screencap -p`. Use `adb shell cmd uimode night yes` for dark.
