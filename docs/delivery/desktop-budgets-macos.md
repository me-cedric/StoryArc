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

## The cold launch (task 5.9)

**The library.** `apps/desktop-macos/scripts/budget-library.py 5000` writes 5,000 comics into the
app's container, `tmp/budget-library-5000`: the pages of six corpus CBZ files, each with a
`ComicInfo.xml` of its own, so every file is different bytes and a different book (20 MB). The
fixture generator, `packages/test-fixtures/scripts/generate.py`, runs its whole generation when
imported, so its archive writer is not reused. Copies of one file, hard links or not, are folded
into one publication by the library, which is right for a reader and useless for a budget. The
budget walk (`Tests/BudgetWalkTests.swift`, `TEST_RUNNER_STORYARC_BUDGET=5000`) adds the folder
the way the folder chooser does, so its bookmark survives a relaunch, and waits for the scan.

**How it is measured.** The app launched with `-StoryArcBudgetProbe YES` writes each event's time
since the kernel started the process to `tmp/budget/launch.log` and as a signpost
(`App/System/LaunchClock.swift`); unarmed it writes nothing. Events: the library window's first
task (`window`), the first rows on screen (`shelf`), each thousand rows (`shelf-1000` …), and the
end of the scan (`scanned`). Three launches, each with the app not running before it
(`open -n … --args -StoryArcBudgetProbe YES`, then a quit); the file cache was warm, since a
cold disk needs `sudo purge`.

| Launch | Window | First rows | 1,000 rows | 5,000 rows |
| --- | --- | --- | --- | --- |
| 1 | 1.08 s | 14.7 s (2,808 rows) | before 14.7 s | 168.0 s |
| 2 | 0.57 s | 1.05 s (1 row) | 39.3 s | not reached in 180 s |
| 3 | 0.59 s | 22.4 s (3,576 rows) | before 22.4 s | 126.4 s |

**Result: fail.** The window is up within the second, but the library is not interactive over
5,000 publications: the rows arrive as the folder is walked again, and all 5,000 are on screen
two to three minutes after the launch. The first scan, when the folder was added, took 290
seconds, about 58 ms a publication.

**Why.** On a launch the Mac re-adds each remembered folder and walks it
(`MacLibrary.restore`). The phone shows the shelf it cached at the last scan first:
`LibraryModel.restoreFolders()` calls `restoreCachedLibrary()` before the walk. The Mac cannot
call that function, which is internal to StoryArcKit's `LibraryFeature`, and the Mac's folders come
from its own security-scoped bookmarks rather than the model's. Making the cached shelf reachable
is a parent change under `apps/ios` (task 1.30's kind), outside this lane. The walk's 58 ms a
publication is a second finding: the scan indexes each archive, and nothing here measured where
that time goes.

## Scroll, resize and frame rate (task 5.10)

**How it is measured.** The same budget walk, with the library window on the library's grid. A
`CADisplayLink` on the window's screen calls back on the main run loop once a refresh; at each
callback the walk moves the grid 60 points down (7,200 points a second), or sets the window's
width along a sine between 900 and 1,400 points. Work that keeps the main thread past the next
refresh, SwiftUI laying out cells or a cover being decoded, delays the next callback, so the gaps
between callbacks are the frame times a reader sees (`FrameDriver` in
`Tests/BudgetWalkTests.swift`). One run of each, 3 seconds of scroll and 2 of resize. The
library held the budget folder and the walks' 5 fixture comics.

| Library | Motion | Frames | Rate | Median | 95th | Worst | Refreshes missed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 5,005 | scroll | 133 in 2.99 s | 45 fps | 8.3 ms | 95.8 ms | 176.8 ms | 225 |
| 5,005 | resize | 15 in 1.40 s | 11 fps | 25.0 ms | 474.5 ms | 474.5 ms | 154 |
| 10,005 | scroll | 76 in 2.53 s | 30 fps | 8.3 ms | 167.7 ms | 321.9 ms | 227 |
| 10,005 | resize | 12 in 1.02 s | 12 fps | 28.4 ms | 594.0 ms | 594.0 ms | 110 |

The first scan of the 10,000 folder took 835 seconds.

**Result: fail.** `desktop-experience`, *Resizing and scrolling*, asks the grid to keep up. Half
of the scroll's frames come at the display's 8.3 ms, and the rest stall for one to three tenths
of a second as new rows come in; a resize relays out the whole grid at each step, at about 12
frames a second, and gets worse with the library's size. Nothing here says which part of
`CoverGridView` pays: an Instruments trace of the SwiftUI and Time Profiler templates over the same
walk is the next step, and the owner's Mac or a slower one gives the number that matters.

**What it does not measure.** A Release build, a trackpad's own scroll with momentum, the list
layout, and a library a user grew over time rather than one folder of one size.

## After the fixes, 2026-10-18

Three causes, each found by sampling the main thread or by reading what the grid recomputes,
and each fixed where it lives. Measured on the same Mac and the same 5,027-publication library.

**1. The shelf waited for the walk.** The Mac now calls StoryArcKit's
`restoreCachedLibrary()`, made public for it, in `MacLibrary.init`, before the library window's
first frame, as a phone does at launch. The walks that follow append to that shelf and remove
only what they prove gone.

**2. The walk's merge was quadratic.** `LibraryModel.adopt(_:from:)` looked each found book up
with `PublicationIdentity.matches` over the whole shelf, and `matches` parsed an app-container
path out of both sides on every call: 25 million parses on the main actor, 36 seconds. A
`PublicationIdentity.Matcher` works the found book's side out once; on a Mac, where no path is
inside an iOS container, the parse is skipped for the whole search. `ContainerPathIdentityTests`
holds that the matcher answers as `matches` does, each way round.

**3. A resumed walk dropped the journal's rows.** A scan stopped by a quit writes a journal;
the next walk put those rows back and skipped their files, and the reconcile then removed every
row the walk had not met. With the cached shelf restored first, 4,536 of 5,027 books left the
shelf after one quit mid-scan. The rows the journal puts back are now marked met
(`LibraryShelfLifecycleTests`, *A walk resumed from the journal keeps the rows the journal put
back*). The same code runs on a phone.

**4. The grid redrew for nothing.** A rescan met every row again and assigned each its equal
merge, and every assignment redrew the grid; it now writes a row only when the merge changed it.
The grid also computed its section index, its division and the selection order of the whole
shelf on every pass, and once per cell for the order: `ShelfLayoutMemo` keeps the last answer
for a shelf, a sort and a width. The sections are one `LazyVGrid` with pinned headers rather
than a grid per section inside a stack, which laid a whole section out when it came into view.

| Measure | Before | After |
| --- | --- | --- |
| Cold launch, shelf on screen (Release, 3 launches) | 126 to 168 s for all rows | 0.75 to 0.78 s, all 5,027 rows with the window (1.23 s on the first launch after a build) |
| Cold launch, quit mid-scan, next launch | — | all 5,027 rows kept |
| Grid scroll at 5,027 (Debug) | 45 to 46 fps, 95th 95 ms | 93 fps, median 8.3 ms, 95th 20 ms, during the launch's rescan |
| Grid resize at 5,027 (Debug) | 4 to 11 fps | 19 fps, median 42 ms |

**Result.** Task 5.9 holds on this Mac: the library is interactive within one second of a cold
launch. Task 5.10 scrolls near the display's rate and still resizes at 19 frames a second: each
width step relays out the visible cells of flexible columns, which is SwiftUI's own layout and
the next thing to trace. The 10,000-publication library was not measured again.

**Still slow.** A launch rescans the whole folder, about eight minutes for 5,027 archives (58 to
95 ms each). The shelf is usable throughout; nothing caches a file's metadata by modification
time and size, which the core's scanner does on Linux and Windows (task 2.2).

## Cleaning up

The budget folders stay in the app's container until the owner deletes them:
`~/Library/Containers/com.mecedric.storyarc/Data/tmp/budget-library-5000`, `…-10000`, and
`…/tmp/budget-5000` from a first try with hard links. `TEST_RUNNER_STORYARC_BUDGET=remove` on the
budget walk forgets the folders in the library and leaves the files.
