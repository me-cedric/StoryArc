# Pinned shelves, iOS (wave 5)

Tasks: one-library-three-destinations 2.1. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-shelf-menu-pin-to-home | The shelf menu: Pin to Home, Rename, Delete. |
| ios-shelf-menu-unpin-from-home | The same menu after pinning: Unpin from Home. |
| ios-home-pinned-collection-and-list | Home with the collection Favourites and the reading list Start here, both pinned. |
| ios-home-after-unpin | Home after both are unpinned. |

Repeat: Run `SweepWave5ShelvesTests/testSetupShelves`, then `testCapturePinMenus`, `testCaptureHomePinnedBoth` and `testCaptureHomeAfterUnpin`. Home draws a placeholder cover for each shelf, so the list order that task 2.1 asks for is not visible. That point is not proved.
