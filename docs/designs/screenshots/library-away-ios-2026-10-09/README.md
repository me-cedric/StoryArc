# A source that is away, iOS (wave 5)

Tasks: one-library-three-destinations 0b.2 and 3.3. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-home-card-library-away | Home: the Bellwether card is dimmed and reads Not on this device right now. It has no Resume button. The Pale Morning card beside it keeps its button. |
| ios-library-four-marks | Library sorted by Last read. Part-read on device (Pale Morning, 14 percent). Part-read away (Bellwether, 50 percent, label: Needs its library to be reachable). Unread on device (for example Bright Panels). Unread away (Ashfall, Cinder). The labels were read from the accessibility tree. |

Repeat: Download Bellwether and read one page with the servers running. Delete the copy from the app container. Stop the servers. Then run `SweepWave5SourcesTests/testCaptureAwayHomeAndMarks`. The frame has no drawn legend; this table is the legend.
