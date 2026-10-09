# iPad panes, iOS (wave 5)

Tasks: the SweepIpadPaneTests class; publication-detail 4.1. Device: iPad Pro 13-inch (M5) simulator (iOS 26.4). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-ipad-empty-pane | Landscape: the shelf with the empty detail pane. |
| ios-ipad-empty-pane-portrait | Portrait: the empty pane. |
| ios-ipad-page-beside-shelf | Landscape: a page chosen, the shelf still beside it. |
| ios-ipad-second-choice | A second choice leaves the shelf still. |

Repeat: Run `SweepIpadPaneTests`, host-shot as for the iPad sweep.
