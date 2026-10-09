# Publication page under Reduce Transparency, iOS (wave 5)

Tasks: publication-detail 1.4 (iOS half). Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-page-wash-standard | Control: Tidal Reach #1 with Reduce Transparency off. |
| ios-page-wash-reduced | Reduce Transparency on, set through the Settings app: the page shows a plain ground. The cover-tinted wash is gone. |

Repeat: Run `SweepWave5TransparencyTests/testCapturePageWashStandard` and `testCapturePageWashReduced`. The test sets the switch back in its teardown.
