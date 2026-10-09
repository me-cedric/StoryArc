# No origin on browse surfaces, iOS (wave 5)

Tasks: publication-detail 3.4. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-no-origin-home | Home with source-attributed titles present: no library name on any card. |
| ios-no-origin-library-list | Library in list layout: each row shows format and author only. |
| ios-no-origin-downloads | The Downloads destination with a source-attributed copy: no library name. |
| ios-origin-named-in-search | Search for Slow Transfer: two rows, each naming its library. This is the one exception. |

Repeat: With the servers running, run `SweepWave5SourcesTests/testCaptureNoOriginOnBrowse`.
