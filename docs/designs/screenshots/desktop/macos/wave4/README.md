# macOS wave 4 — EPUB, PDF text and the player

Taken 2026-10-17 at the head of the Mac wave 4 lane from the ad-hoc build of
`apps/desktop-macos` (macOS 27.0.1, Xcode 27.1). The screens are the three wave 4 added to
`Tests/MacCatalogue.swift`. The EPUB and the audiobook are corpus fixtures copied into the
app's container under a fixed name (`walk-ebooks/fixture.epub`, `walk-audiobooks/catalogue.m4b`),
opened straight from the file rather than from the library, so the library screens of waves 2
and 3 draw as before. The PDF is `text-pages.pdf`, which the library already holds. Tasks 4.5
to 4.8 of `desktop-clients`.

Every screen has four frames: light and dark, each at the default text size and at the
app's own **Largest** text size (Settings > Appearance > Text Size).

| Frame | What it shows |
| --- | --- |
| `epub-reader-<variant>.png` | `fixture.epub` in the Mac's web view, through the pinned Readium bundle on the app's own scheme, with the chrome up: the theme menu (the six presets of `reading-themes`, *Paper* in force), search in the book, Read Aloud where a voice exists, and the foot with Previous Page, the position (1 of 2) and Next Page. The page keeps the reading theme in dark mode: the theme is the reader's, not the system's. |
| `pdf-selection-<variant>.png` | `text-pages.pdf` with its first page's words selected by a drag: the selection in the system's selection colour over the page, the selection menu on glass at the foot (five highlight colours, note, copy, search for the selection, deselect), the search-in-document control in the head cluster, and the outline's three chapters as ticks on the slider. |
| `player-<variant>.png` | `chaptered.m4b` paused at its start: the cover slot (the fixture has no cover, so the headphones placeholder), the title and the chapter (*One*), the position slider with elapsed and total, back 15 and forward 30, play, and the Chapters and Speed menus. |

`<variant>` is `light`, `dark`, `light-largest` or `dark-largest`.

## How they were taken

As for waves 2 and 3, `screencapture` has no Screen Recording grant in an agent session, so
the frames come from `Wave4CaptureTests` inside the app, which asks the window server for the
app's own windows:

```bash
cd apps/desktop-macos
TEST_RUNNER_STORYARC_CAPTURE=1 xcodebuild test -project StoryArcMac.xcodeproj -scheme StoryArc \
  -destination 'platform=macOS' -only-testing:StoryArcMacTests/WindowWalks/Wave4CaptureTests
# frames: ~/Library/Containers/com.mecedric.storyarc/Data/tmp/captures/wave4/
pnpm frames:shrink <copied folder>
```

`method.txt` in the capture folder names the method of each frame.

## Limits, read with the frames

- **The web view's page is the renderer's.** The EPUB frame shows the book as the pinned
  bundle lays it out at 980 × 820 points; a different window shape paginates differently.
  The snapshot references in `Tests/__Snapshots__/` draw the same page in-process.
- **Read Aloud shows only where the Mac has a voice.** On a Mac with no speech voice the
  control is absent, as `desktop-experience` asks; the capture Mac has the system voices.
- **The PDF selection is made by the catalogue**, from the page's top left to its bottom
  right, not by a pointer drag, so the frame shows what a drag ends in.
- **The player is paused at zero.** The fixture is six seconds long; playing it during a
  capture would run it out. Its cover slot is the placeholder because the fixture has no
  artwork.
- **Fixed sizes.** The reader windows are held at 980 × 820 points and the player at
  420 × 620, as the catalogue holds them for the snapshots.
