# The UI revamp, photographed — 2026-08-30

138 captures, 90 iOS and 48 Android, taken as the slices of
[`ui-revamp-2026-08.md`](../../ui-revamp-2026-08.md) landed over one day. Its companion is
`before-2026-08-30/`, which holds the same screens as they were before the revamp began.

This README was written a day later, because the directory did not have one and its two
siblings did — so 138 files were identified by filename alone, and one convention in those
filenames is genuinely ambiguous. That is recorded below rather than left to be rediscovered.

## How they were taken

iOS: a booted iPhone 17 Pro or iPad Pro 13-inch simulator, `xcrun simctl io booted
screenshot`. Android: an emulator at 1080 × 2400, `adb exec-out screencap -p`. Appearance
and text size were set with `xcrun simctl ui` and `adb shell settings put system font_scale`
respectively — never by driving the Settings app, so nothing was measured at the default
size first.

## The naming convention

`<platform>-<subject>-<state>-<appearance>[-<text size>].png`

- **platform** — `ios` or `android`.
- **subject** — what screen it is. The 16 subjects here, by count: `detail` 27, `shell` 18,
  `library` 16, `home` 15, `search` 13, `shelves` 10, `downloads` 9, `iphone` 7, `ipad` 7,
  `shelf` 5, `phone` 4, `type` 2, `cover` 2, and one each of `wave3`, `settings`, `firstrun`.
- **state** — what is being shown: `empty`, `hero`, `two-panes`, `no-history`, `up-next`,
  `overflow`, `late-and-silent`, and so on. This is the part that carries the meaning, and
  it is the part a reader has to guess at without this file.
- **appearance** — `light` or `dark`. Absent where the capture is of a control or a menu
  whose appearance is not the point.
- **text size** — `largest-text`, `ax5` (iOS's `accessibility-extra-extra-extra-large`),
  `ax3`, or `scale2` (Android's `font_scale 2.0`). Absent means the default size.

## One ambiguity worth naming

**`ios-detail-iphone-contrast-{light,dark}-{top,foot}`** reads as *increased contrast* by
convention alone — nothing in the name says so, and `contrast` could as easily have meant a
contrast *measurement*. They are the publication page under **Increase Contrast**, which is
one of the two settings `storyArcGlass` falls back to an opaque surface for. Its sibling
`ios-detail-iphone-bare-*` is a publication with no series, no year and no description; and
`ios-detail-iphone-nocover-*` is one with no cover art.

**`-top` and `-foot`** are the same screen scrolled to each end, not two different screens.
The publication page is taller than a phone, and the wash, the hero and the title block are
at one end while the actions, the description and the series shelf are at the other.

## What the contrast pair proves, read off the pixels — added 2026-09-05

The section above says these four are *increased contrast*. This says how a reader can check
that without taking the author's word for it, because `publication-detail`'s delta rests on
them: the wash is "replaced by a plain surface rather than being softened", and softening is
how a screen ends up marginally below the contrast floor instead of clearly above it.

Compare **`ios-detail-iphone-light-top`** against **`ios-detail-iphone-contrast-light-top`** —
the same device, the same publication, four minutes apart (21:12 against 21:08 on the status
bar):

- **Without the setting**, the page ground is a pink wash pulled out of the red cover,
  strongest behind the artwork and falling away toward the description.
- **With it**, the ground is the palette's plain light surface, edge to edge. Not a paler
  wash — no wash. The dark pair is the same story against near-black.
- **And the control is in the frame.** `AGENTS.md` §6 asks for one whenever a capture could
  look the same for a boring reason, and a neutral page on its own would prove only that the
  app had no cover to sample. Here the cover, the `Read` button and the overflow circle all
  carry the platform's increased-contrast hairline border, which the plain captures do not.

## The Android detail captures, and what is not recorded about them

`android-detail-overflow`, `android-detail-phone-{dark,light}`,
`android-detail-provenance-and-series`, `android-detail-tablet-two-panes`, from `a836e8a2`.

That commit's message is a subject line and nothing else, so the appearance in the two
`phone-` files comes from their own names and the other three are unkeyed. **None of the five
is keyed to a text size**, and none is keyed to the three states `publication-detail` tasks
2.1 and 2.2 ask for — a downloaded local publication, a cached remote one, and one whose
source is unreachable. Those frames are still owed on both platforms; the tasks name each by
state and walk.

## What this set does not contain

Nothing from the reader, and nothing of the accessibility audit — both of which were only
reachable a day later, once the UI-test target could be built at all. See
`after-2026-08-31/` for those, and for the before/after pairs of the defects these captures
turned out to be hiding in plain sight: a caption printing its title twice, and a
fixed-layout book that could not be opened.
