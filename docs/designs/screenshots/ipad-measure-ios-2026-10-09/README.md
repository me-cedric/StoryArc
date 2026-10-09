# iPad portrait and landscape, sidebar and Settings, iOS (wave 5)

Tasks: one-library-three-destinations 1.2 and 4.1; publication-detail 4.1. Device: iPad Pro 13-inch (M5) simulator (iOS 26.4). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-ipad-portrait-downloads | 1.2: Downloads in portrait with on-device items. |
| ios-ipad-portrait-search | 1.2: Search at rest in portrait. |
| ios-ipad-portrait-library-sidebar | 4.1: the portrait library with the sidebar drawn over it. |
| ios-ipad-landscape-library-sidebar | 4.1: the landscape library with the sidebar in its column. |
| ios-ipad-portrait-settings | 4.1: the Settings sheet in portrait. |
| ios-ipad-landscape-settings | 4.1: the Settings sheet in landscape on the 13-inch screen. It is a centred card about 840 of 2752 pixels wide. |
| ios-ipad-portrait-page-chosen | publication-detail 4.1: portrait, both panes, a page chosen. |

Repeat: Run `SweepWave5IpadTests`, host-shot.
