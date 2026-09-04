# Four findings from the iOS sweep, fixed — 2026-09-04

The *after* for four of the items in
[`../ios-sweep-2026-09-02/README.md`](../ios-sweep-2026-09-02/README.md)'s *What looked
wrong*. Every frame here has a same-named frame in that folder to hold it against, except
`ios-comic-reader-fit-picker.png`, which is the one the sweep could not take.

Taken with `node scripts/capture-ios.mjs --out … --only <Class>/<test> --appearance light|dark`
on `StoryArc-iPhone17Pro`, iOS 26.5, at the default text size unless the filename says
otherwise. `-dark` means the **device** was dark for that run, which is what
`capture-ios.mjs --appearance` sets and what the `-dark` suffix is filed from.

## 1. The reader's menu is no longer written in the accent

| Before | After | What changed |
| --- | --- | --- |
| `ios-comic-reader-menu.png` | `ios-comic-reader-menu.png` | *Contents*, *Appearance*, *Transition* were purple on a material the salmon page had tinted warm brown. They are the hierarchical primary now, which is what `storyArcGlassText` resolves on a live material — and the palette's own neutral once Reduce Transparency makes the ground knowable. |
| `ios-comic-reader-menu-dark.png` | same | The dark half of the pair. The material still picks up the page; the words are white on it rather than purple. |
| `ios-comic-reader-menu-ax5.png` | same | Largest accessibility text size, because the sheet's rows grow and the rule must hold at every size. |
| `ios-comic-reader-menu-expanded.png` | same | At `.large`, where the material is opaque — the control frame. *Transition* used to be the only purple row in a section whose other two rows were already primary; now the three read as one section. |
| `ios-epub-reader-menu.png` | same | The same defect in the other reader — nine purple rows — and the same fix. `ReaderMenuEntry` gives the two readers one menu, so a fix to one that missed the other would be the drift the type exists to prevent. |
| `ios-epub-reader-menu-dark.png` | same | |

*Done* is still drawn in the accent. It sits in a toolbar glass pill of its own rather than
directly on the page-tinted material, and it is the one control on the sheet the platform
expects to be tinted.

## 2. The *Fit* row opens, and the row opens it

The sweep asked for a finger before this was called a defect. Three taps on a booted
iPhone 17 Pro settled it:

| Where the tap landed | What happened |
| --- | --- |
| On the trailing value, `Screen ⌄` | The picker opened, with all four options |
| On the middle of the row | Nothing |
| On the word *Fit* | Nothing |

So the control worked and the row did not, which is worse than either a broken control or a
broken test: a reader who taps the name of the setting they want gets no feedback, and the
row directly above — same section, same shape — opens from its label. *Fit* and *Reading
direction* were menu-styled `Picker`s, whose button is the trailing value alone; *Transition*
is a `Menu`, whose label is the button and therefore fills the row.

`XCUIElement.tap()` lands on an element's centre, which is exactly where a reader's tap
misses. The walk was not the artefact.

All three are `Menu`s now, and all three draw the up/down chevron the pickers carried — it is
the only thing on a row of two plain sentences that says the row opens something.

`ios-comic-reader-fit-picker.png` and `-dark` are the frames the sweep reported it could not
take. `ios-comic-reader-transition-picker.png` is the control: the row that always worked,
still working, from the same lookup and the same tap.

## 3. An audiobook's progress — no frame, and why

**Not photographed, and this is not an exception under §6 — it is a gap, named.**

Home's *Continue reading* hero should no longer say `2 pages left` for a publication that is
listened to, because a listening position is not a page count and the app has no duration to
convert it into. The rule is asserted in `HomeRemainderTests`.

The surface cannot be reached on the committed corpus. Every audio fixture runs about two
seconds, so listening to one at all finishes it, and a finished publication leaves *Keep
reading* by design. Driven by hand: opening `The Peregrine` and pressing *Listen* moved it
from the shelf to *Finished* between one screenshot and the next.

**That is also why the sweep's own report is wrong about which frame shows this.** It
attributes `2 pages left` for `Sea Room` to `ios-home-top.png`, and no home frame in that
folder draws a *Continue reading* hero at all — `Sea Room` is under *Finished* in every one of
them. The defect was real and is fixed; the citation was not.

A fixture long enough to be part-listened-to would make this photographable, and would also
give the player, the sleep timer and the chapter list something to run against. That is
`packages/test-fixtures`, which this change did not touch.

## 4. One coverless treatment, on every surface that has a well

A publication with no artwork had three unrelated fallbacks, and one of them said the title
twice. `CoverlessWell` moved to `DesignSystem` — the home `audiobooks-and-playback` §4.4b
named for it — and every surface asks it for the same thing: the format's own symbol over the
format's name.

| Before | After | What changed |
| --- | --- | --- |
| `ios-library-grid.png` | `ios-library-grid.png` | `Foreign Codec` was its own title inside the well **and** its own title in the caption eight points below. The well draws a document glyph over `CBZ` now, and the caption is the only place the title appears. |
| `ios-library-grid-dark.png` | same | |
| `ios-detail-no-cover.png` | `ios-detail-no-cover.png` | **Deliberately unchanged.** This page's glyph-and-format is the treatment the other surfaces adopted, so this frame is the reference rather than the fix. What changed underneath it is that the glyph is no longer hard-coded `book.closed`. |
| `ios-detail-audiobook.png` | `ios-detail-audiobook.png` | Which is what that hard-coding cost: an audiobook was drawn as a book. It is headphones over `Audiobook` now. |
| `ios-detail-audiobook-dark.png` | same | |
| `ios-player-sleep-sheet.png` | `ios-player-full.png` | The player drew a flat square with the title set into it — a second implementation of the treatment, which `audiobooks-and-playback` §4.4b recorded as a compromise forced by the module boundary. It draws the shared well now, and `PlayerArtworkImage` renders that same view for the lock screen. |
| `ios-player-full-dark.png` | same | |
| `ios-home-top.png` | `ios-home-top.png` | Home's shelves take the same well: `Foreign Codec` on *Recently added*, and the audio publications under *Finished* with headphones rather than nothing. Home's own well used to pass no format at all, while the grid cell of the same size named it. |
| `ios-home-lower.png` | same | |

`audio-playback`'s *A publication with no cover* scenario is amended in the same change: the
clause it carried — "the title set as artwork" — named the treatment that was replaced.

## What is here that is not a fix

`ios-comic-reader-page.png`, `ios-comic-reader-chrome-revealed.png`,
`ios-comic-reader-adjustments.png` and `ios-pdf-find-sheet.png` came along with the comic
reader suite. They are unchanged surfaces and they are the control for the run: a menu that
looks different in a run where the page, the chrome and the adjustment sheet look the same is
a menu that changed, rather than a device that did.
