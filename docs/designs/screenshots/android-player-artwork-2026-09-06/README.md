# The full player draws the artwork — Android, 2026-09-06

Three frames from `storyarc-j6` (1080 × 2400, 411 × 914 dp, `-gpu host`) on the `Player` route,
taken with `scripts/capture-android.mjs`. The 2026-09-05 design review's finding 8: *the Android
full player has no artwork* — transport only, the chapter name straight into the scrub bar, while
iOS draws the cover or the shared coverless well and feeds the lock screen from it.

| Frame | What it shows |
| --- | --- |
| `android-player-artwork-light.png` | *Sea Room*, an M4B with no cover: the shared `CoverlessWell` above the chapter, the well every other surface draws, not a treatment of the player's own |
| `android-player-artwork-dark.png` | The same, dark |
| `android-player-artwork-scale2.png` | Font scale 2.0: the well, the chapter, the scrub bar and the transport all still on screen |

`PlayingBook` now exposes the followed publication as state, `AppScreens` hands it and the
library's cover loader to `PlayerScreen`, and `PlayerArtwork` draws the cover or the well as the
column's first child (`42426140`). `PlayerSemanticsTest` asserts a coverless book draws the well and
a covered one its cover. The *before* is `android-player-2026-09-04/android-player-full.png`.

**Not verified here:** whether the media notification is given the same artwork, which the
`audio-playback` scenario also asks; task 4.4b keeps its `[~]` for that clause.

## How to retake them

```bash
A=docs/designs/screenshots/android-player-artwork-2026-09-06
node scripts/capture-android.mjs Player --out $A/android-player-artwork-light.png
node scripts/capture-android.mjs Player --out $A/android-player-artwork-dark.png --dark
node scripts/capture-android.mjs Player --out $A/android-player-artwork-scale2.png --font-scale 2.0
```
