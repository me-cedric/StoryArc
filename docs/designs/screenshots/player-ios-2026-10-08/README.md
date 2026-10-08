# player, iOS frames, 2026-10-08

Device: iPhone 17 Pro Max simulator, iOS 26.4. Branch wave-3. Light and dark, default text size.

Capture: `PlayerDamageTests/testCaptureDamagedEndingBeforeAndAfterMarking` and `PlayerDamageTests/testCaptureFinishedAudiobook` in `apps/ios/UITests/PlayerDamageTests.swift`. Run each with `xcodebuild test -only-testing:StoryArcUITests/PlayerDamageTests/<method>` after `node scripts/install-and-seed-simulator.mjs <id>`, once per appearance (`xcrun simctl ui <id> appearance light|dark`).

## Frames

| Frame | What it shows |
| --- | --- |
| `ios-player-damaged-before` (+ dark) | `truncated.m4b` played to its end. The player says "Finished" and "1 part could not be played". It offers no "Mark as finished" button and no "Playback stopped" heading. |
| `ios-player-finished-audiobook` (+ dark) | `chaptered.m4b` ("Sea Room") played to its end. The player says "Finished". There is no "Next:" row, because the book is in no series. |

## Task 23.6, iOS: NOT proved

The reviewer expected "Playback stopped", the damage line and "Mark as finished" for this walk. The product does not do that for `truncated.m4b`. The engine reports the damage early, carries on, and the item plays to its nominal end through the normal end path. `NarratedSource.fileFailed()` sets `endedOnFailure` only in the `.end` response, which a carry-on file never reaches. The normal end path (`NarratedSource.swift:190-194`) calls `ended?()` with `endedOnFailure` still false. So the book ends as "Finished", and the damaged ending is not held back from "finished". The "after the tap" frame does not exist because the button does not exist. See the report.

## Task 7.3, iOS: partly proved

The finished surface appears at the end of a six-second book. The "Next:" row was not reached: no seeded audiobook is in a series, and the series for an audiobook comes from library metadata that the fixture does not carry. The download sweep (remove downloads after finishing) was not run on the simulator.
