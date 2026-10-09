# Pale hero and the two paths from Home, iOS (wave 5)

Tasks: one-library-three-destinations 0b.1 (pale cover); publication-detail 2.3. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-home-hero-pale | The Keep reading hero of Pale Morning (cover near 246, 240, 224 RGB), with the author and the progress bar over the scrim. The Resume button is legible. |
| ios-home-shelf-card | Home with the Recently added shelf, before a card is chosen. |
| ios-home-shelf-card-opens-page | Path 1: a shelf card opens the publication page. |
| ios-home-hero | Path 2, before: the hero on Home. |
| ios-home-hero-opens-reader | Path 2, after: the hero opens the reader with no page between. The page is flat colour because the fixture pages are flat colour. |

Repeat: First run `SweepWave5HomeTests/testSetupPale` after adding the pale comic (one eight-page comic with a ComicInfo author) to the simulator corpus. Then run `testCapturePaleHero`, `testCaptureShelfCardPath` and `testCaptureHeroPath`.
