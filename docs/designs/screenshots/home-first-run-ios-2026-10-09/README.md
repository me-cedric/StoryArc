# Home first run, iOS (wave 5)

Tasks: one-library-three-destinations R.4. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-empty-home | Home on a device with no library: the empty-library view that replaced HomeEmpty. The app was uninstalled and installed again first. |

Repeat: Uninstall the app, then run `SweepEmptyTests/testCaptureEmptyHome`. The largest-text frame is not taken (owner rule of 2026-10-08).
