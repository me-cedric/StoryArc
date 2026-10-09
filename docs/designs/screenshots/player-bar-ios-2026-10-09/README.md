# Compact player bar on a shelf, iOS (wave 4)

Task: close-the-audited-gaps 23.7 (the dock title and the chapter caption use glass text). Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark.

| Frame | What it proves |
| --- | --- |
| ios-downloads-with-player | The Downloads shelf with the compact player bar: title "Sea Room" and chapter "Two" read on the bar. |

Repeat: `node scripts/capture-ios.mjs --out <dir> --only SweepDownloadsTests/testCaptureDownloadsWithPlayer --device <id> --appearance light|dark`.
