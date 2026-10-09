# Publication page in its availability states, iOS (wave 5)

Tasks: publication-detail 2.1. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-page-remote-source-answering | A catalogue title that is not downloaded, with its source answering. The primary action is Download. |
| ios-page-remote-source-stopped | A catalogue title with its source stopped. The page says it cannot be opened until it is on this device, and that Attic Catalogue is not answering right now. |
| ios-page-downloaded | The downloaded copy: primary action Read, provenance On this device. |
| ios-page-downloaded-overflow-offers-download | The overflow menu before the copy is kept: Download is offered. |
| ios-page-downloaded-overflow | The overflow menu after the copy is kept: Remove download is offered. |

Repeat: With the servers running, run `SweepWave5SourcesTests/testCaptureAvailabilityStates`. Stop the servers, then run `testCaptureSourceStoppedPage`.
