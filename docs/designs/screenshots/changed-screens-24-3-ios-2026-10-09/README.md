# Changed screens of 24.3, iOS (wave 5, partial)

Tasks: close-the-audited-gaps 24.3. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-search-at-rest | Search at rest, with the recent searches. |
| ios-home-top | The top of Home, with its section headings. |
| ios-home-lower | Home scrolled down, with its section headings. |

Repeat: Owed: reader selection menus, Library sidebar series list, More from this library, catalogue More link and Undo bars. Run `SweepSearchTests/testCaptureSearchAtRest`, `SweepHomeTests/testCaptureHomeTop` and `testCaptureHomeLower`.
