# Store listings

The listing texts live here. The screenshots and the Play graphics are generated into
`.build/store/`, which git ignores. Never commit a generated image.

## Run it

```bash
pnpm store:showcase      # copy the showcase library in (the owner's share must be mounted)
pnpm store:capture       # every screenshot: 6 frames, 5 device sizes, 4 languages
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
| 01 library | The shelf, with series in one cell |
| 02 publication | *The Boys #1*, its detail page |
| 03 comic-reader | Page 2 of *The Boys #1*, with the reader's chrome |
| 04 reading-themes | The Laura Palmer EPUB, with the reading-themes panel open |
| 05 audiobook-player | *Dungeon Crawler Carl* in the full player, paused |
| 06 your-libraries | Three libraries: a share, an OPDS catalogue and a Kavita server |

Every frame shows the app's interface. A bare page of somebody else's artwork reads as an
advertisement for that comic. Pages 3 and 4 of *The Boys #1* show gore and swearing, so
frame 03 stops at page 2. The turn counts are in `LIBRARIES` in `scripts/store-walk.mjs`.

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

## How a run works

1. The run builds both apps once, then starts three lanes at the same time. Each lane has
   its own agent-device session: the Android emulator `storyarc-store` (booted with
   `-memory 2048 -no-window`, one emulator only), the iPhone and the iPad.
2. Each device gets the library once. A file that is there already is not pushed again. A
   file the library does not name moves to a parking folder; nothing is deleted.
3. For each language, the lane resets the app's state, keeps the library, and walks the
   frames in one path (`walk()` in `scripts/store-walk.mjs`). Launch A takes 01 to 04.
   Launch B adds the three libraries of frame 06 to the registry, which the app reads at
   launch only, and takes 06, then 05.
4. Each step waits for its screen before the screenshot: a selector, a text, or a quiet
   screen. Two waits on iOS are fixed, and the walk says why: agent-device does not see the
   EPUB reader's menu sheet, so the walk taps its *Reading themes* row by position.
5. Every label is the app's own word: Android `strings.xml` through `namedIn()` in
   `scripts/android-routes.mjs`, iOS `Localizable.xcstrings`. A renamed key fails the run by
   name before a device boots. `pnpm store:selftest`, part of `pnpm lint`, checks the walk.
6. The Android status bar is agent-device's demo mode. iOS shows 9:41 through
   `simctl status_bar`, cleared at the end. The run shuts down the devices it booted.

A frame that fails leaves the device's screen in `.build/store-logs/` and the run goes on
with the next language.

## How long a run takes

Measured on 2026-10-10 with the showcase library, from shut-down devices, builds included:

| Run | Frames | Time |
| --- | --- | --- |
| `pnpm store:capture` | 120 | 9 min 23 s |
| `pnpm store:capture --locales fr --frames 04` | 5 | 2 min 32 s |

The Android lane sets the pace: its three sizes share one emulator. In the full run the
iPhone lane ended at 4 min 36 s and the iPad lane at 6 min 39 s.

## The library

The frames are taken against real comics, books and an audiobook, copied from the owner's
share by `scripts/store-showcase.mjs`. Its header names each file. The copies are
third-party publications: they stay in `~/.cache/storyarc/store-showcase`, outside the
repository. Without them the run stops and says so. `--library corpus` takes the frames
against the test corpus instead, to prove the walk.
