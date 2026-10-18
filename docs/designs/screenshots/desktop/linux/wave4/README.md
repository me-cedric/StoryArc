# Linux wave 4 — EPUB, PDF and the player

Taken 2026-10-17 (the EPUB frames 2026-10-18, see below) at the head of `claude/lane-linux-wave4-1025c5` by
`apps/desktop-linux/scripts/headless-proof.sh --walk docs/designs/screenshots/desktop/linux/wave4`:
the debug build under cage 0.1.5 (headless wlroots, 1280 by 720, pixman) in the Ubuntu 24.04
container (GTK 4.14.5, libadwaita 1.5.0, WebKitGTK 2.52.6, GStreamer 1.24.2), driven by `wtype`
and `gapplication action`, captured by `grim`, in the light style, with a session bus, an
accessibility bus and no sound device. The library is the corpus `packages/test-fixtures/comics`;
the EPUB, the PDF and the audiobook open by path, as a drop or the command line would open them.
Tasks 4.10 to 4.15 of `desktop-clients`. The walks that read these frames are
[`desktop-spike-audio-linux.md`](../../../../../delivery/desktop-spike-audio-linux.md) and
[`desktop-a11y-linux.md`](../../../../../delivery/desktop-a11y-linux.md).

| Frame | What it shows |
| --- | --- |
| `library.png` | The library over the corpus comics, as the walk starts. |
| `epub-reader.png` | `fixture.epub` in the EPUB window, retaken 2026-10-18 after two host fixes: the chapters were fetched relative to the manifest's folder and answered 404, and the chapter documents (`blob:`) inherit the page's policy, which had no `blob:` for the navigator's own stylesheets. The page now paints in the container, paginated, in the *Paper* colours. |
| `epub-next.png` | After Right: the second page of the first chapter, and no *Back*, because a turn is not a jump. |
| `epub-paper.png` | The EPUB surfaces walk (`scripts/wave4-epub-walk.sh`, 2026-10-18) opens the book: the contents, bookmark and marks buttons at the start of the header; read aloud, the theme surface and search at its end; the progress line in the foot. |
| `epub-theme.png` | The theme surface: six named swatches with an *Aa* specimen in their own colours, *Paper* checked, *Customise*, the brightness and *Follow the system's appearance*. Cage does not slide a popover back inside the output, so its right edge runs off the frame. |
| `epub-contents.png` | The contents: *Chapter One* and *Chapter Two* from the manifest. |
| `epub-search.png` | Search for *paragraph 3*: the hits in context, the match in bold, the chapter under each. |
| `epub-marks.png` | After `win.bookmark`: the bookmark button filled, and the marks list with the bookmark under its chapter and the empty highlights line. Its left edge runs off the frame for the same reason. |
| `epub-jump.png` | *Chapter Two* chosen from the contents: the foot offers *Back*. |
| `epub-back.png` | After *Back*: the first chapter again, the bookmark filled at that page, *Back* gone. |
| `epub-fixed.png` | `fixed-layout.epub`: the renderer lays the first page out as one fixed page at its declared size, centred in its frame. The fixture's page image is one pixel, so the page is empty. |
| `pdf-reader.png` | `text-pages.pdf` in the reader window: the page text pane toggle and the outline button at the start of the header, *Read aloud* at its end, page 1 of 3 at one pixel per point. |
| `pdf-search.png` | The search bar opened through the `reader-action` walk hook (a `wtype` Control chord was not delivered under cage), *chapter two* typed into it, the hit count beside it. |
| `pdf-search-hit.png` | Return: the reader jumps to the hit's page, *2 of 3*. |
| `player-bar.png` | `id3-chapters.mp3` playing on a null sink: the mini player revealed at the foot of the library with the title, the clock, the slider and the transport. |
| `player-paused.png` | After `playerctl play-pause` and `playerctl position 2` from outside the app: the bar shows *Play* again and the clock the new position. |
| `a11y-*.txt` | The accessibility tree of each screen as Orca would read it, from `scripts/a11y-tree.py` over AT-SPI. |
| `playerctl.txt` | What `playerctl` read and did over the session bus while the audiobook played. |
| `storyarc.log` | The app's own output during the walk. |

The dark style and the two text sizes are not captured: the walk has no settings portal and GTK
takes the text size from it. The Mac waves capture four variants per screen; the Linux host walk at
the end of the waves owes them.
