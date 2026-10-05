# Library browsing and server-shelf pins, 2026-10-05

Frames for tasks 17.7 and 17.10 of `close-the-audited-gaps`. The device is the iPhone 17 Pro
simulator on iOS 26.2, in light appearance, at the default text size.

| Frame | Task | What it shows |
| --- | --- | --- |
| `ios-library-more-from-footer.png` | 17.7 | *More from All publications* at the foot of the shelf, under the last section of a partial source. |
| `ios-source-shelf.png` | 17.7 | What the footer now opens: that source's own rows, drawn by the library's `CoverGrid` and its own cells. It used to open the source's catalogue browser, which draws cells of its own. |
| `ios-shelves-pin-a-server-shelf.png` | 17.10 | A server-backed collection's context menu, which now offers *Pin to Home* above *Delete*. It carried only *Delete* before. |
| `ios-home-pinned-server-shelf-leads.png` | 17.10 | The pinned server collection *Staff picks* leading the home surface's Collections shelf, ahead of the unpinned *Long reads*. |
| `ios-home-pinned-server-list-is-a-shelf.png` | 17.10 | The pinned server reading list *Start here* as a shelf of its own, drawn from the membership `ShelfSync` cached. The pinned *collection* draws no such row, because nothing caches a collection's membership. |

## How the state was reached

The device had no server, so one was added by hand through the app's own flow. Both servers
are this repository's own mocks:

```bash
node scripts/kavita-server.mjs ~/StoryArcCorpus --port 5001   # key: storyarc-test-key
node scripts/opds-server.mjs <a corpus of ~1500 files> --port 4444
```

Settings › Your libraries › Add a library › Kavita library, then the same menu's Online
library for the OPDS catalogue. **The OPDS corpus has to be large.** *More from this library*
is drawn only while a source still holds more, and the continued read adopts a 19-publication
corpus faster than a screenshot can be taken; about 1500 entries at six per page keeps the
source partial long enough to photograph.

`AddMockKavitaTests` walks the same route and stops at the *Add a library* menu, which opens
under a finger and not under its synthetic tap. It skips rather than fails, and says so.

## Not captured

- **Android.** This machine has no emulator and no `adb` on the path.
- **Dark appearance and the largest text size.** Neither screen introduces a colour or a
  string of its own: the source shelf is `CoverGrid`, and the pin is a context-menu row
  beside the delete that was already photographed.
