# Android phone device run, 2026-10-10

Device: OnePlus 7T Pro (crDroid 16, Android 16), 1440 x 3120 at 560 dpi. Build: debug,
`com.mecedric.storyarc.debug`, from commit 8de722191. Default text size. The agent drove the app
with `agent-device` and `adb input`. Frames are shrunk to 1200 px on the long side.
Test publications were `scripts/corpus.mjs` output, four `packages/test-fixtures/` files, and
one 20-minute silent audiobook. The agent removed all of them after the run.

The black box in frames 14 to 16 hides the name of the owner's own server.

| Frame | Shows |
| --- | --- |
| `01-rail-drag-mid.png` | A to Z rail dragged to M: the shelf shows the M heading. |
| `02-rail-drag-end.png` | Rail dragged to the end: the shelf shows S and T. |
| `03-sleep-chips.png` | Sleep-timer chips: 5, 15, 30, 45, 60 min and End of chapter. Each chip is 48 dp high. |
| `04-compact-bar.png` | Library with the audiobook playing: the compact bar shows Long Silence and Pause. |
| `05-curl-drag.png` | A slow drag in curl mode: the back of the page shows mirrored. |
| `06-curl-turned.png` | After the release: the next page, Paper theme, Natural off (flat page). |
| `07-readaloud-playing.png` | Read-aloud playing: the sentence is highlighted, the bar shows Pause. |
| `08-readaloud-paused.png` | Read-aloud paused: the bar shows Play. |
| `09-readaloud-resumed.png` | Read-aloud resumed after the pause. |
| `10-readaloud-after-leaving.png` | Reader closed: the compact bar still shows The Long Field with Pause. |
| `11-volume-before.png` | Reader before the volume key, setting on. |
| `12-volume-down.png` | After Volume down: the next chapter. The media volume stays at 0. |
| `13-volume-up.png` | After Volume up: the page before. |
| `14-row-menu.png` | "Your libraries" row menu: Move up, Move down, Rename, Remove. |
| `15-row-moved.png` | After Move up: the mock source sits above "On this device". |
| `16-remove-confirm.png` | Remove confirmation with Cancel and Remove. |
| `17-natural-grain-reader.png` | Reader with Natural on: the page has paper grain (36 colours in a blank band). |

No frame shows the system picker. It listed files from the owner's shared Downloads folder.
