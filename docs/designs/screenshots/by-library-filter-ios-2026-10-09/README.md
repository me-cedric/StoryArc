# By-library filter, iOS (wave 5)

Tasks: one-library-three-destinations 3.2 and item 12 of the task 6.5 table. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-filter-which-library | The filter menu open on Which library, with Attic and Loft Catalogue listed. |
| ios-filtered-to-one-library | The shelf narrowed to Attic Catalogue. The Filter control reads 1 filter active (asserted by the test). |
| ios-clear-filters-offered | The filter menu while narrowed: Clear filters is offered. |
| ios-home-shelf-filtered-keep-reading-present | Home after the shelf is narrowed to one library: Keep reading still shows. The filter stops at the shelf. |

Repeat: The mock catalogues run on ports 4444 and 4447 and serve five titles (Ashfall, Bellwether, Cinder, Driftwood, Evergreen). Run `SweepWave5LibraryTests/testCaptureByLibraryFilter` and `testCaptureHomeFilteredToOneLibrary`.
