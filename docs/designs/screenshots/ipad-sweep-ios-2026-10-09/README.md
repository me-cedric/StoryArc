# iPad sweep, iOS (wave 5)

Tasks: the SweepIpadTests class. Device: iPad Pro 13-inch (M5) simulator (iOS 26.4). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-ipad-home, -library, -library-list, -downloads, -search, -detail, -comic-reader | One frame per walk in landscape, light and dark. ios-ipad-detail shows the hero under the sidebar. |
| ios-ipad-sidebar-dark | The sidebar open. The light run skipped this case, so there is no light frame. |

Repeat: Run `SweepIpadTests`. The XCUITest screenshot of a landscape iPad is rotated and cropped on this headless simulator. So `shutter` asks the host to take the frame with `simctl io screenshot` while `/tmp/w5hs/active` exists (see `hostShot` in SweepWalk.swift).
