# Android EPUB end card at the last page, 2026-10-08

Tasks 23.4 and 9.7 (Android half) of `close-the-audited-gaps`.

| Frame | What it proves |
| --- | --- |
| `android-epub-end-card.png`, `-dark.png` | The end card shows at the last page of *Blue Harbour 01*. The next-book button takes the adjusted blue of the cover (#255B97), with its chosen label colour. The page chrome stays untinted. |
| `android-epub-end-card-no-cover.png`, `-dark.png` | The control. *Harbour Lights 01* has no cover. Its button keeps the brand purple with white text. |

Cause of 23.4: the card waited for the locator progression to reach 0.999. Readium names where the
visible page starts, so a short last page never reached it. The card now also shows when Readium
reports the last page of the last resource (`EpubReaderViewModel.atLastPage`).
Before the fix, the same books showed no card at the last page.

Device: Pixel 6a emulator, API 33, debug build, 1080x2400 at 420 dpi.
"Dark" is the system dark setting. The reader page keeps its own cream theme.

How to repeat: build the two blue books from `Harbour Lights 01.epub` (flat #255B97 cover, series
*Blue Harbour*), push them with the `node scripts/corpus.mjs` output into
`/sdcard/Android/data/com.mecedric.storyarc.debug/files/`, then run
`node scripts/capture-android.mjs "EPUB reader > end card coloured cover" --out <png> [--dark]`
and `"EPUB reader > end card no cover"` on a fresh install.
