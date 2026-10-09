# A sectioned list on a shelf of 200, iOS (wave 5)

Tasks: one-library-three-destinations 3.4b. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-library-list | The compact list with letter headings A, B and C and the A to Z rail. The library cache holds 200 publications (`Library/Caches/library.json`). |

Repeat: Run `node scripts/corpus.mjs --simulator <id> --count 200`, then `SweepLibraryTests/testCaptureCompactList`.
