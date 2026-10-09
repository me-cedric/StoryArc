# Finish and Next in series, iOS (wave 5)

Tasks: one-library-three-destinations 0b.3. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-home-finish-and-next | Tidal Reach #1 on its last page offers Finish and Next in series. Fine Print beside it offers Finish only. |
| ios-home-finish-no-next | Fine Print, a comic with no next issue, on its last page: Finish alone. |
| ios-home-after-finish | After Finish on Tidal Reach #1: the hero moves on to Fine Print and Up next appears. |
| ios-home-finished-section | After Finish: Tidal Reach #1 is under Finished and gone from Keep reading. |

Repeat: Reach the last page with `SweepWave5HomeTests/testSetupFinishNoNext` and `testSetupFinishAndNext`. A comic left on its end screen counts as finished at once, so the walk steps back to the last page before it closes. Then run `testCaptureFinishNoNext`, `testCaptureFinishAndNext`, `testTapFinish` and `testCaptureAfterFinish`. One run used sqlite3 to set ZISFINISHED to 0 after an earlier run had finished Fine Print.
