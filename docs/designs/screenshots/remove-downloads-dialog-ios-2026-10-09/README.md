# Remove downloads dialog, iOS (wave 5)

Tasks: one-vocabulary-in-four-languages 4.2 and close-the-audited-gaps 15.11. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-settings-source-remove-downloads-only | The dialog Remove downloads from Harbour OPDS? with its body and the Remove downloads action, over the source detail screen. |

Repeat: Run `SweepSourceRemovalTests/testCaptureRemoveDownloadsConfirmation`. The Downloaded row behind the dialog reads 2,1 MB with a decimal comma in an English interface. See the report.
