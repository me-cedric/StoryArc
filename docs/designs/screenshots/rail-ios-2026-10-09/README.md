# A to Z rail, iOS (wave 4)

Task: close-the-audited-gaps 24.6. Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark. Also the iPad Pro 11-inch (M5) simulator (iPadOS 26.2) for the ipad- frames. The shelf is the 19-title corpus (`node scripts/corpus.mjs --simulator <id>`), sorted by Title.

| Frame | What it proves |
| --- | --- |
| ios-library-rail-rest | The rail at rest on the trailing edge. Every letter that names a section is drawn. |
| ios-library-rail-drag-0, -1 | A finger held part-way down the rail (two moments, 2 s and 3 s into the hold). The circle bubble with the letter "P" shows to the left of the finger. |
| ios-library-rail-landscape | A phone on its side. The short window thins the drawn letters to seven. The file is the raw screen buffer turned a quarter circle with `sips -r -90`, because the raw buffer arrives sideways. |
| ios-ipad-library-rail-rest, ios-ipad-library-rail-drag-0, -1 | The same on an iPad in landscape, with the sidebar. |

Repeat: `node scripts/capture-ios.mjs --out <dir> --only SweepRailTests/<test> --device <id> --appearance light|dark`.
Tests: testCaptureRailAtRest, testCaptureRailDuringADrag, testCaptureRailInLandscape, testCaptureIpadRailAtRest, testCaptureIpadRailDuringADrag. The drag frame is taken from a second thread while the gesture holds. Run the landscape file through `sips -r -90` after the capture.

Other things the frames show: the "2 couldn't be opened" notice with its taller bordered capsule (task 24.3).
