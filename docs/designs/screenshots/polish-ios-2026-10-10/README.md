# Polish wave frames, iOS, 2026-10-10

Device: iPhone 17 simulator `FAE72C22-8CCC-47A3-B114-1AE10BE48780`, iOS 26.2.
Debug build from the head of the `polish-ios` lane. Default text size only.
A file that ends in `-dark` is the dark twin.
The catalogue snapshots cover every other screen of this lane. These frames hold what a snapshot cannot draw.

## Frames

| Frame | Task | What it proves |
| --- | --- | --- |
| `your-libraries-swipe*.png` | 27.3 | A swipe on a library row shows Rename, then Remove at the screen edge. Remove is red. The row opens a confirmation before it removes anything. |

## How to repeat

1. Build for the simulator, install the app, and open Settings, then Your libraries.
2. Swipe a row left. Use `pnpm device swipe 340 790 80 790 --session <lane>` and `pnpm device screenshot <file>`.
3. Switch with `pnpm device settings appearance dark` and `light`.
