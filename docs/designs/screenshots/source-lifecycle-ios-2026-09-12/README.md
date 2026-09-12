# A source, in every state it can be in — iOS, 2026-09-12

The iOS half of `source-lifecycle` tasks 4.1, 4.3, 4.5 and 4.6. Its Android twin is
`docs/designs/screenshots/source-lifecycle-2026-09-11/`, and the two name the same libraries
on purpose, so a state can be read across the platforms.

## What made these reachable

Every state here needs registered sources, and a simulator's registry is whoever last used it
— so `testCaptureSettingsSourceDetail` photographed a different screen each week, and
`testCaptureUnreachableSourceDetail` skipped outright on a device with no unreachable
catalogue.

`MockCatalogues` in `apps/ios/UITests` is the fixture now: three OPDS catalogues injected
through `sweepLaunch(sources:)`, two answering and one pointed at a port nothing listens on.
The walk decides what it is looking at, rather than reading whatever the device holds.

```bash
node scripts/opds-server.mjs <corpus> --port 4444
node scripts/opds-server.mjs <corpus> --port 4445
pnpm build:ios:ui
pnpm capture:ios --out <dir> --device <udid> --only SweepSourceScreensTests/testCaptureSettingsSourceDetail
```

The unreachable source needs no server at all: nothing listens on 4999 by construction, so
that walk cannot be made to pass by luck. The reachable ones skip with a reason when the mock
catalogues are down, rather than photographing an unreachable source under a name saying it is
reachable.

`scripts/seed-simulator-sources.mjs` writes the same three sources into a simulator's own
defaults, for driving the app by hand.

**The walks live in `SweepSourceScreensTests`**, split out of `SweepSettingsTests` on the same
day: adding them took that file past the 400-line cap, and a file holding both the settings
screens and one library's own screens was two subjects anyway.

## The frames

| Frame | Screen | What it shows |
| --- | --- | --- |
| `ios-settings-sources-reachable-and-not{,-dark}` | *Your libraries* | *Attic* and *Loft* **Available**, *Cellar* **Not answering**, and *On this device*, in one frame at one moment |
| `ios-settings-source-detail{,-dark,-ax5,-ax5-dark}` | source detail | *Status Available*, *Last updated*, *In your library · At least 9 titles*, *Downloaded · 0 bytes*, over four actions |
| `ios-source-unreachable-detail{,-dark,-ax5,-ax5-dark}` | source detail | the same screen for a source that is not answering |
| `ios-library-sources-away{,-dark}` | the shelf | *None of the places you added can be reached right now* — the offline promise, with *Try again* under it |
| `ios-settings-source-remove{,-dark,-ax5,-ax5-dark,-ax5-scrolled,-ax5-scrolled-dark}` | removal confirmation | *This removes 9 titles from your library* — a real count |
| `ios-settings-source-remove-downloads{,-dark}` | removal confirmation | the other sentence, for a source that holds a finished download |
| `ios-search-one-title-two-sources{,-dark}` | search | one title held by two catalogues, *Attic* first, each row naming its library |
| `ios-source-reconnect-sheet{,-dark,-ax5,-ax5-dark}` | the add sheet, re-opened | the address filled, the key empty, *Connect* disabled — the state §4.2 asks for |
| `ios-library-pull-to-refresh-midgesture` | the shelf | the refresh spinner drawn in the pulled gap, mid-gesture |
| `ios-library-pull-to-refresh-settled` | the shelf | the same gesture finished: *Libraries checked just now.* |

## What the frames establish

1. **The control is in the frame, not beside it.** `source-lifecycle` §4.3 asks for a
   reachable source at the same moment as an unreachable one, because an unreachable source is
   grey and never red — and a grey row proves nothing next to no other row. The earlier attempt
   could not get the pair: every source on that simulator was unreachable, so the two frames
   were two greys.

2. **The removal confirmation states a real number.** Nine titles, from a catalogue that has
   actually answered. Nothing is confirmed in the walk, so the source survives for the walks
   after it.

3. **Precedence is the order, and each row says whose copy it is.** *Attic Catalogue* is first
   in the registry and its row is listed first. Both rows stay, because `sources` defers
   de-duplication in writing. The same frame carries two more sentences worth having:
   *Cellar Catalogue didn't answer · Try again*, and *Libraries checked just now*.

## The mid-gesture frame, and why it is not a screenshot

`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` returns after the **whole**
gesture, the lift included, so a shutter fired after it photographs a settled screen. That
mistake was made once in this repository, on the page curl, and the two frames it produced were
read as a shader that did not track the finger before the arithmetic gave the harness away.
`CurlWalkTests` records the episode.

So the gesture is recorded and the frame is pulled from the video, which is what that walk
settled on:

```bash
UDID=2AEEE794-5E99-4EDC-A888-6FD69D458C17
xcrun simctl io $UDID recordVideo --codec h264 --force /tmp/refresh.mov &
REC=$!
pnpm capture:ios --out <dir> --device $UDID \
  --only SweepSourceScreensTests/testCapturePullToRefreshSettled
kill -INT $REC
ffmpeg -ss 25 -i /tmp/refresh.mov -vf fps=10 -pix_fmt rgb24 /tmp/frames/f%04d.png
```

Finding the frame is arithmetic rather than scrolling through 216 of them: crop a band where a
pulled shelf shows its spinner, scale each crop to one pixel, and sort by distance from the
settled frame. The pull lasts about a second, so eight or nine frames differ; the spinner is
fully drawn in the middle of them.

## The refused credential, reached without a server

§4.2 sat open because its state was a race: a mock served with a rotated key answers 401 on one
launch and a connection failure on the next, and only the first offers *Sign in again*.

`LibrarySourceHealth` has a second route to the same state, and it cannot flicker — its last
line reads "neither page could be built, so the secret this source needs has gone" and returns
`.unauthorized`. So `MockCatalogues.refusedKavita` is a Kavita source whose
`credentialReference` names a secret the keychain does not hold. Nothing is asked of the
network, and the screen is the one a refusal reaches.

The walk asserts *Sign-in needed* is on screen **before** it taps, so a source that had quietly
become unreachable cannot pass it and photograph a sheet raised for another reason.

## The library-wide away notice, and the device it needs

This was the last frame §4.3 owed, and it was owed for a reason no fixture could remove: the
shelf reaches `LibraryAway` only after the *narrowed to nothing* branch, which is taken
whenever the device holds a publication of its own. `MockCatalogues.everythingAway` supplies
the other half — one catalogue, pointed at a port nothing listens on, so
`LibraryAway.everythingAway(in:)` is true — but no launch argument empties `Documents`.

So the device's own books are moved aside for the two shutters and moved back after:

```bash
UDID=2AEEE794-5E99-4EDC-A888-6FD69D458C17
C=$(xcrun simctl get_app_container $UDID com.mecedric.storyarc data)
mkdir -p /tmp/away-backup && mv "$C/Documents/"* /tmp/away-backup/
mv "$C/Library/Caches/library.json" /tmp/away-backup/
pnpm capture:ios --out <dir> --device $UDID --only SweepSourcesTests/testCaptureAwayNotice
mv /tmp/away-backup/* "$C/Documents/"        # library.json back to Library/Caches
```

The cache file goes with them. `restoreCachedLibrary` keeps any cached row that recorded no
location — that is a server publication, and its absence from the device is the point of it —
so last session's catalogue rows would have filled the shelf on their own.

`testCaptureAwayNotice` skips with those three commands in its message when the device is
seeded, rather than photographing the filter sentence under a name saying *away*.

## Offline is not an error, measured

`AGENTS.md` §2 says an unreachable source is grey and never red. These two frames say whether
it is, by arithmetic rather than by eye — the most saturated pixel in each band, ignoring
anything darker than a quarter brightness, where a hue reading means nothing:

| Frame | the notice — icon, heading, sentence | the action — *Try again* |
| --- | --- | --- |
| `ios-library-sources-away` | **0.029** | 0.679 |
| `ios-library-sources-away-dark` | **0.057** | 0.680 |

The sentence carries no colour at all. The only saturated thing in either frame is the way out
of the state, which is the point: offline is a normal thing to be, and the app's answer to it
is an action rather than an alarm.

The largest-text frames say the same and go further: across the **whole** of
`ios-source-unreachable-detail-ax5`, at every pixel, the maximum saturation is 0.250 — at
`AccessibilityXXXL` the screen holds no colour whatsoever, only *Not answering* in grey, *Last
error · No answer since Sep 12, 2026 at 10:49* wrapped to three lines, and a title truncated to
*Cellar Catal…*.
