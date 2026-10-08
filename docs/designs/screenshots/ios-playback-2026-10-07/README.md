# iOS playback proofs — 2026-10-07

| Frame | Task | What it proves |
| --- | --- | --- |
| `ios-player-finished-damaged*.png` | audiobooks-and-playback 2.5 | A cut-short audiobook (*Cut Short*, `truncated.m4b`) plays what it can. The finished surface states "Finished" and "1 part could not be played". |
| `ios-compact-bar-long-title*.png`, `-ax5` | audiobooks-and-playback 8.4 | The compact bar over the shelf, for a title that does not fit. The title is cut with an ellipsis, and the bar keeps its controls, at the default size and at AccessibilityXXXL. |

Device: iPhone 17 Pro Max simulator, iOS 26.4. Light and dark each.

**CarPlay (12.6) has no frame.** Xcode 27.0 on the build machine has no `Simulator.app`, so
I/O > External Displays > CarPlay cannot be opened. The scene and the manifest are built and
guarded by `CarSimulatorOnlyTests`. See task 12.6 in `audiobooks-and-playback/tasks.md`.

## How to repeat

```bash
node scripts/install-and-seed-simulator.mjs <udid>
node scripts/capture-ios.mjs --out <dir> --only PlayerDamageTests --device <udid> --appearance light   # then dark
node scripts/capture-ios.mjs --out <dir> --only PlayerBarLongTitleTests --device <udid> --appearance light   # then dark
```
