# Linux wave 4 — EPUB, PDF and the player

Taken 2026-10-17 at the head of `claude/lane-linux-wave4-1025c5` by
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
| `epub-reader.png` | `fixture.epub` in the EPUB window: the header with *Read aloud*, the web view, the position line. The web view's content is white here: WebKitGTK 2.52 paints through the GPU process and the container has no GPU, so the page runs (the renderer reported `ready` and the first locator, *1 of 2*) but is not composited. A real session owes the painted page. |
| `epub-next.png` | After Right: the position line reads *2 of 2*. |
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
