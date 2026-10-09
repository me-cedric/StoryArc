# iPad window resize sequence, iOS (wave 5)

Tasks: one-library-three-destinations 4.1 and 4.3; publication-detail 4.1 (partial). Device: iPad Pro 13-inch (M5) simulator (iOS 26.4). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-ipad-slot-1-wide | A wide window: the list shelf and the page of Fine Print, both panes. |
| ios-ipad-slot-2-narrow | The window dragged narrow: the page fills it and the tab bar sits at the foot. |
| ios-ipad-slot-3-widened | Widened again: both panes are back and Fine Print is still the page shown. |

Repeat: This is not Split View beside another app. The simulator runs iPadOS 26 windowed apps. The window was resized by dragging its corner with the simulator control tool, in light only. The narrow window gets the compact width class, which is the layout question of 4.1 and 4.3. Split View beside a second app was not reached.
