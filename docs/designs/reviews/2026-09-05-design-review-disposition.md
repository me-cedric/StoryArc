# The 2026-09-05 design review — what became of each finding

An external design review of both apps, delivered on 2026-09-05 as a single HTML page outside
the repository, listed fifteen findings. This is their disposition as of 2026-09-06, so the
next reader does not have to rediscover which were fixed, which were decided against, and
which wait on something the harness cannot yet produce. Frames are under
`docs/designs/screenshots/`; commits are on `main`.

| # | Finding | Disposition |
| --- | --- | --- |
| 1 | Cover grids measure different things on the two platforms | **Partly true when reviewed, and the pixel was already fixed** (`9c1b50b9`, the library grid measures its pane). What disagreed was the written rule, a KDoc and a guard that accepted either shape; all three now say what the code does (`458601ba`). The one divergence left is the wide tier's threshold, 840 dp on Android and 900 pt on iOS, recorded as open in `design.md` §4 |
| 2 | The `coverGap` token was quietly abandoned by both grids | **Renamed `rowCoverGap`** for the two horizontal runs that use it; the grids stay on `md` (`65c55994`). No pixel moved |
| 3 | The detail hero swallows the screen on a bare publication | **Capped at a third of the room when the page stacks**: 477 dp → 316 dp on the bare page (`148f6b6a`; `android-detail-2026-09-05`) |
| 4 | At accessibility sizes the theme presets sit below the fold | **Decided against changing**: the sheet opens on the preview first at every size; recorded on the reader-theming change |
| 5 | Themed Android icons collapse the five faces into one | **Decided against changing, and said**: correct for a themed icon, whose point is the wallpaper's colour; the icon spec carries the qualifier |
| 6 | The Android nav bar wears two brand colours at once | **Fixed**: the selected label follows the accent on every scheme (`c1e90a70`; `android-nav-label-2026-09-06`) |
| 7 | A failed download offers only "Stop" | **Fixed on both platforms**: a failed row offers Retry and Remove, and its confirmation says nothing reached the device (Android `633382bf`, iOS `e0ab0e8b`…`3886fb74`; `downloads-retry-2026-09-05`). iOS's Retry reaches whichever live queue holds the record |
| 8 | The Android full player has no artwork | **In progress** on 2026-09-06 (`audiobooks-and-playback` 4.4b / 4.5) |
| 9 | Android still confirms "Stop" with deletion wording | **Fixed** (`f44af9a0`): stop, remove, remove an import and clear a failed transfer are four sentences |
| 10 | Library icon buttons override Material You with the brand accent | **Fixed**: chrome icons read the scheme's primary (`65af6a18`; `android-library-chrome-2026-09-06`) |
| 11 | Eight Android surfaces are off the cover-size ladder | **Fixed**: three grids ask the ladder, five surfaces step at the accessibility boundary, `design.md` §4's table says which does what (`288e8462`; `android-cover-ladder-2026-09-06`) |
| 12 | One "Zero kB" survives | **Fixed the same day** (`1871168a`; `source-lifecycle-2026-09-05`) |
| 13 | Android halves of the September captures | **Open**: the source-detail screen has Robolectric renderings and no device frame, because the generated corpus registers no source on the emulator |
| 14 | Two fixtures block whole families of proof | **Open**: a committed audiobook long enough to be part-listened, and a right-to-left publication, are both still owed in `packages/test-fixtures` |
| 15 | The grain and the glass have unmeasured branches | **Open**: the sweep launcher has no lever yet for Reduce Transparency or Increase Contrast, and the grain has no dark-appearance pair |

## Two things the review could not have known

**The review's own method found a defect it did not list.** Checking finding 1 on a device led
to `SweepIpadPanes`, which had never been run, and then to the day-old iPad split having left
every cover on the iOS Library shelf dead — a value link with no destination it could see, on
iPhone and iPad alike, with every gate green (`b37acd86`; `ios-pane-2026-09-06`). A review that
reads frames is a review of frames that were taken; the shelf's covers had not been photographed
opening anything since the split landed.

**Finding 12's fix turned up the wording defect behind it.** The removal confirmation said no
files are deleted while the app deletes a source's downloads; it now states the titles, the
downloads and the space, and fits at the largest text size (`source-lifecycle-2026-09-05`).
