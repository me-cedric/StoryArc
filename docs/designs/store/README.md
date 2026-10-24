# Store listings

The listing texts live here. The screenshots and the Play graphics are generated into
`.build/store/`, which git ignores. Never commit a generated image.

## Run it

```bash
pnpm store:showcase      # copy the showcase library in (the owner's share must be mounted)
pnpm store:capture       # every screenshot: 6 frames, 5 device sizes, 4 languages (foldables on request)
pnpm store:graphics      # the Play icon and one feature graphic per language
pnpm store:verify        # check every file and every listing text against both stores
```

`pnpm store:capture` takes filters, so one frame in one language is a short run:
`--buckets phone,ipad-13`, `--locales fr`, `--frames 04`. Other flags: `--library corpus`
(the test corpus), `--no-build` (use the app builds that are there), `--keep-devices`
(leave booted what the run booted).

## What a run writes

The layouts are fastlane's, so an upload is one `supply` or `deliver` command.

| Store | Path |
| --- | --- |
| Play | `.build/store/play/<locale>/images/{phoneScreenshots,sevenInchScreenshots,tenInchScreenshots}/NN-name.png` |
| Play | `.build/store/play/<locale>/images/featureGraphic.png` and `icon.png` |
| App Store | `.build/store/appstore/<locale>/NN-name-<device>.png` |

The locales are `en-US`, `de-DE`, `es-ES` and `fr-FR`. The App Store takes its icon from the
binary, so `pnpm store:verify` checks `AppIcon-1024.png` instead.

## The six frames

| Frame | Screen |
| --- | --- |
| 01 library | The shelf, with series in one cell. A wide window also shows the audiobook's page |
| 02 publication | *The Boys #1*, its detail page |
| 03 comic-reader | Page 2 of *The Boys #1*, with the reader's chrome |
| 04 reading-themes | The Laura Palmer EPUB, with the reading themes open beside or under the page |
| 05 audiobook-player | *Dungeon Crawler Carl* in the full player, paused |
| 06 home | Home, with the comic, the ebook and the audiobook in *Continue reading* |

Every frame shows the app's interface. A bare page of somebody else's artwork reads as an
advertisement for that comic. Pages 3 and 4 of *The Boys #1* show gore and swearing, so
frame 03 stops at page 2. The turn counts are in `LIBRARIES` in `scripts/store-walk.mjs`.

No frame shows an error, a notice or an empty state. The run adds no library that the device
cannot reach: a source that does not answer puts *Not answering* in Settings and a notice on
Home and the shelf.

Two frames differ by window size:

- Frame 01 on the 10-inch Android window and the iPad (`split` in `scripts/store-walk.mjs`):
  the library draws an empty pane beside the shelf until a cover is chosen, so the walk opens
  the audiobook's page there.
- Frame 04 on the Android phone: the themes sheet stays at its small detent. That is the only
  height that leaves the page in view. It shows the live preview but not the six themes. The
  full height covers the page.
- Frame 04 on the 10-inch Android window and the iPad: Readium sets two columns of text, and
  one turn moves two pages. The walk turns until the first page of the foreword shows, which
  is the third turn on every device. A fourth turn there
  shows the short last page of a letter: one column of text and three empty quarters.
- Frame 04 on the tablets: the themes are a popover over the page.

## The device sizes

Play's slots are pixel sizes and a 9:16 ratio. `wm size` and `wm density` set the window in
dp, so one emulator gives all three:

| Bucket | Pixels | Density | Window |
| --- | --- | --- | --- |
| `phone` | 1080 x 1920 | 420 | 411 x 731 dp, compact |
| `tablet7` | 1080 x 1920 | 280 | 617 x 1097 dp, medium |
| `tablet10` | 1440 x 2560 | 240 | 960 x 1707 dp, expanded |

App Store Connect takes two sizes, and each is a simulator's native resolution:

| Bucket | Simulator | Pixels |
| --- | --- | --- |
| `iphone-6.9` | iPhone 17 Pro Max | 1320 x 2868 |
| `ipad-13` | iPad Pro 13-inch | 2064 x 2752 |

### Foldables

Four buckets run only when a run names them (`--buckets duo`, `--buckets fold`, or one of
the four). A run that names no bucket takes the five above. The plan is the OpenSpec change
`foldables-and-iphone-duo` (design D7, tasks 3.1 to 3.5). The App Store slot sizes are from
Apple's screenshot specifications, read on 2026-10-23.

| Bucket | Device | Pixels | Written to |
| --- | --- | --- | --- |
| `duo-outer` | iPhone Duo simulator, closed | 1398 x 2034 | `appstore/<locale>/NN-name-duo-outer.png`, App Store slot iPhone Duo outer |
| `duo-inner` | iPhone Duo simulator, open | 2007 x 2853 | `appstore/<locale>/NN-name-duo-inner.png`, App Store slot iPhone Duo inner |
| `fold-open` | Pixel Fold size, open: 2208 x 1840 at 420 (841 x 701 dp) | padded to 3271 x 1840 (16:9) | `play/<locale>/images/foldScreenshots/NN-name-fold-open.png` |
| `fold-closed` | Pixel Fold size, closed: 1080 x 2092 at 420 | padded to 1177 x 2092 (9:16) | `play/<locale>/images/foldScreenshots/NN-name-fold-closed.png` |

- **The iPhone Duo set is optional today and required from April 2027** for every app built
  with the iOS 27.1 SDK or later, which StoryArc is. `pnpm store:verify` with no buckets
  checks it: a missing frame is a warning before 2027-03-01 and a failure from that day.
  `pnpm store:publish --platform appstore` applies the same date.
- **Only Xcode's Device Hub opens the simulated iPhone Duo.** `simctl` has no hinge
  command. Capture `duo-outer` with the device closed. For `duo-inner`, open the device in
  Device Hub (Xcode, Window, Devices), then run `pnpm store:capture --buckets duo-inner
  --duo-open`. Without `--duo-open` the lane stops and says so. A frame taken from the wrong
  display has the other display's size, and `pnpm store:verify` refuses it.
- **Play has no foldable slot**, and its large screen slots take 9:16 or 16:9 only and eight
  images each. So the fold frames are padded with black to that ratio and go to
  `foldScreenshots`, a folder `supply` does not read. Pick up to eight for the large screen
  slot and move them to `tenInchScreenshots` by hand.
- `fold-open` sets the window with `wm size` on the store emulator, as the other Play buckets
  do. It shows the wide layout of the open display. The half-open postures need the Pixel
  Fold emulator profile: `pnpm capture:matrix --devices fold`.

## How a run works

1. The run builds both apps once, then starts three lanes at the same time. Each lane has
   its own agent-device session: the Android emulator `storyarc-store` (booted with
   `-memory 2048 -no-window`, one emulator only), the iPhone and the iPad.
2. Each device gets the library once. A file that is there already is not pushed again. A
   file the library does not name moves to a parking folder; nothing is deleted.
3. For each language, the lane resets the app's state, keeps the library, and walks the
   frames in one path (`walk()` in `scripts/store-walk.mjs`). After frame 04 the walk starts
   the app again, because no step can close the iOS themes sheet. Before that launch, the iOS
   lane deletes the app's registry of libraries. The registry records when the libraries last
   answered, and after a new launch the iPad library shows that line beside the player of
   frame 05. Frame 05 opens the audiobook. Frame 06 then goes to Home, so *Continue reading*
   holds the three books that the walk opened. `--frames 06` alone still opens all three first.
4. Each page turn waits until the screen is still: after quick turns, the Android EPUB reader
   did not record the position, and the ebook was missing from *Continue reading*. The iOS
   EPUB reader shows its chrome about two seconds before the book, under a spinner, so the
   first turn waits until the spinner is gone. A reader can still drop a turn, so the walk
   turns until the words of the foreword show. The Android emulator has no sound device, and
   its player can stand at 0:00 for half a minute. A pause there records no position, and the
   audiobook then misses *Continue reading*. So after frame 05 the walk taps the middle of the
   scrub bar, which moves the book and records it.
5. Each step waits for its screen before the screenshot: a selector, a text, or a quiet
   screen. Two waits on iOS are fixed, and the walk says why: agent-device does not see the
   EPUB reader's menu sheet, so the walk taps its *Reading themes* row by position. The iOS
   runner can refuse steps while a slow accessibility capture still runs (seen once on the
   iPad player). The walk then goes on from the refused step every three seconds, for half
   a minute at most.
6. Every label is the app's own word: Android `strings.xml` through `namedIn()` in
   `scripts/android-routes.mjs`, iOS `Localizable.xcstrings`. A renamed key fails the run by
   name before a device boots. `pnpm store:selftest`, part of `pnpm lint`, checks the walk.
7. The Android status bar is agent-device's demo mode. iOS shows 9:41 through
   `simctl status_bar`, cleared at the end. The time is a full ISO date, so the iPad shows
   Sun 9 Jan and not the date of the run. The date is a Tuesday: simctl draws the wrong
   weekday. The run shuts down the devices it booted.

A frame that fails leaves the device's screen in `.build/store-logs/` and the run goes on
with the next language.

## How long a run takes

Measured on 2026-10-11 with the showcase library, from shut-down devices, builds included:

| Run | Frames | Time |
| --- | --- | --- |
| `pnpm store:capture` | 120 | 11 min 2 s |

The Android lane sets the pace: its three sizes share one emulator. In the full run the
iPhone lane ended at 6 min 5 s and the iPad lane at 7 min 47 s. A filtered run still pays for
the boots and the builds, about one minute.

## The library

The frames are taken against real comics, books and an audiobook, copied from the owner's
share by `scripts/store-showcase.mjs`. Its header names each file. The copies are
third-party publications: they stay in `~/.cache/storyarc/store-showcase`, outside the
repository. Without them the run stops and says so. `--library corpus` takes the frames
against the test corpus instead, to prove the walk.
