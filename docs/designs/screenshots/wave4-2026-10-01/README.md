# Wave 4 frames, 2026-10-01

These frames come from wave 4 of `close-the-audited-gaps`. The device is the iPhone 17 Pro simulator, iOS 26.5, in light appearance. The capture tool is `scripts/capture-ios.mjs` with the 19-publication corpus.

| Frame | Task | What it shows |
| --- | --- | --- |
| `ios-skipped-list.png` | 14.4, 14.5 | "What couldn't be opened". Each file has its own reason: a password-protected CBZ, and a CB7, which is not a format StoryArc reads. |
| `ios-library-grid.png` | 14.5 | The library grid with the corpus, after wave 4. |

Not captured: the Android frames, the OPDS covers and captions, and the Kavita shelf delete actions. They need the OPDS mock or a Kavita source on the device. The reviewers listed the steps in the wave 4 results.

The simulator's SpringBoard crashed at boot 13 times during the first capture run. A restart of CoreSimulatorService fixed it. StoryArc was not the cause: the crash is in FBSDisplayMonitor at SpringBoard start.
