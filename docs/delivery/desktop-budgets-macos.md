# macOS budgets — the curl, the cold launch and the library grid

Tasks 5.1, 5.9 and 5.10 of `desktop-clients`, measured on the Mac app of
`claude/lane-macos-wave56-7be24f` on 2026-10-18.

| Machine | Value |
| --- | --- |
| Model | MacBook Pro, Apple M1 Pro, 32 GB |
| System | macOS 27.0.1 |
| Display | the built-in panel, 120 Hz (ProMotion) |
| Build | Xcode 27.1, Debug, the ad-hoc signed sandboxed app |

The owner's budgets are in `design.md`, Open Question 3: the library is interactive within
1 second of a cold launch, with 5,000 publications, on a mid-range laptop. An M1 Pro is above
mid-range, so a pass here is necessary and not sufficient; the number to carry to a slower Mac
is the margin.

## The curl (task 5.1)

The curl is the phone's `PageCurl.metal`, from `StoryArcKit_ReaderFeature.bundle/default.metallib`
in the app (`MacCurlTests` holds that the library is there and holds `pageCurl`). A turn by key,
click or wheel runs it for `CurlTurn.settleDuration`, 0.30 seconds; a drag follows the pointer.

**How it is measured.** `CurlWalkTests` opens `natural-sort.cbz` in Curl, one page a slot, and
presses the right arrow three times. During each settle a `CADisplayLink` on the window's screen
ticks once a refresh; a tick after which the curl drew a new body is a frame presented, and the
time between two such ticks is a frame time (`MacCurlProbe`). The walk writes the result to the
container's `tmp/conformance/wave5.log`.

| Run | Frames in 3 settles | Median | 95th | Worst | Refreshes missed |
| --- | --- | --- | --- | --- | --- |
| 1 | 102 | 8.3 ms | 8.3 ms | 8.3 ms | 0 |
| 2 | 103 | 8.3 ms | 8.3 ms | 8.3 ms | 0 |
| 3 | 103 | 8.3 ms | 8.3 ms | 8.3 ms | 0 |

The curl holds the display's 120 Hz with no refresh missed. A run that also images the window
mid-turn for the wave 5 frame misses refreshes while the window server copies the window; those
runs are not counted.

**What it does not measure.** A Release build, a 60 Hz external display, a Mac with an Intel
GPU, and a curl over a page larger than the fixtures' 1,000-pixel pages. The Mac stores no
per-device verdict as the phone's `CurlCapability` does: the curl is offered wherever the shader
library is present.
