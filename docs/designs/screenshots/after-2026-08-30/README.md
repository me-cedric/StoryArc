# The publication page, 2026-08-30

**This README covers the `*-detail-*` captures in this directory and nothing else.** The
folder holds 139 files from several slices of that day's wave; the rest are still identified
by filename alone, which is a gap `publication-detail` task 5.5 records and does not close.

The reason these needed writing down: four of them are read as *increased contrast* by
convention, and until now nothing outside a commit message said so. A filename that means one
thing to the person who typed it and another to the next reader is not evidence.

## iOS — `ios-detail-*`, from `82ad1d92`

Booted iPhone 17 Pro and iPad simulators, StoryArc built from `main`. The source commit
records the conditions: "iPhone and iPad, light and dark, largest text, increased contrast, a
publication with no series or year, and one with no cover at all". Each screen is two files —
`-top` and `-foot` — because the page is taller than the window.

| Files | What is set | What it shows |
| --- | --- | --- |
| `ios-detail-iphone-{light,dark}-{top,foot}` | Default text size | The ordinary page. *The Ridge Road*, `Ashfall #1`, a red cover, one `Read` button and the overflow beside it. |
| `ios-detail-iphone-{light,dark}-ax5-{top,foot}` | Largest text size | The same page at AX5. |
| `ios-detail-iphone-contrast-{light,dark}-{top,foot}` | **Increase Contrast on**, default text size | The wash is **gone**, not softened. |
| `ios-detail-iphone-bare-{light,dark}-{top,foot}` | Default | A publication with no series and no year — the lines are absent rather than empty. |
| `ios-detail-iphone-nocover-dark-{top,foot}` | Dark | A publication with no cover: the placeholder well, and no derived colour taken from it. |
| `ios-detail-ipad-{light,dark}-{top,foot}` | Default | The same page on iPad, with the content capped to a measure. |

### What the contrast pair actually proves, read off the pixels

`publication-detail` requires the wash "replaced by a plain surface rather than being
softened", and this is the pair that shows it. Compare
`ios-detail-iphone-light-top` against `ios-detail-iphone-contrast-light-top` — the same
device, the same publication, four minutes apart (21:12 against 21:08 on the status bar):

- **Without the setting**, the page ground is a pink wash pulled out of the red cover. It is
  strongest behind the artwork and falls away toward the description.
- **With it**, the ground is the palette's plain light surface, edge to edge. Not a paler
  wash — no wash. The dark pair is the same story against near-black.
- **And the platform's own increased-contrast treatment is visible beside it**: the cover, the
  `Read` button and the overflow circle all gain a hairline border that the plain captures do
  not have. That border is the control. A screenshot of a neutral page proves nothing on its
  own — the app might simply have had no cover to sample — and the borders are what say the
  setting was on when the shutter fired.

## Android — `android-detail-*`, from `a836e8a2`

`android-detail-overflow`, `android-detail-phone-{dark,light}`,
`android-detail-provenance-and-series`, `android-detail-tablet-two-panes`.

**The source commit recorded no conditions beyond its subject line**, so the appearance in the
two `phone-` files is taken from their filenames and the rest are unkeyed. Nothing here is
keyed to a text size, and none of the five is keyed to the three states — a downloaded local
publication, a cached remote one, one whose source is unreachable — that tasks 2.1 and 2.2
ask for. Those captures are still owed on both platforms.

## Still owed, and not in this directory

Increased contrast is captured on iOS only; **Android's high-contrast branch has no capture at
all**, and **reduced transparency is captured nowhere on either platform** — a `find` under
`docs/designs/screenshots/` for `*transp*` and `*reduce*` returns nothing. The Android half is
answered rather than missing: `DetailAccent.kt` returns no accent under `rememberHighContrast`
and the platform ships no transparency switch, which the delta now carries as a clause rather
than leaving in a code comment. The picture of it is still owed.
