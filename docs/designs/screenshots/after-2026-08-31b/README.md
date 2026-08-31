# The second batch of 2026-08-31, after

Same devices and same commands as [`before-2026-08-31b/`](../before-2026-08-31b/README.md),
which carries the setup and the caveats. This is what changed.

## What each pair proves

| Pair | Before | After |
| --- | --- | --- |
| `ios-downloads` | Foreign Codec, Harbour Lights 01 and Harbour Lights 02 are black rectangles. Three of the nine cells on screen say nothing about the book they stand for. | Each draws the well the library has drawn all along: the title as stand-in artwork, the format underneath. `Foreign Codec` and `CBZ`, exactly as the library shows them one tab away. |
| `ios-library` | — | Unchanged, and that is the point. The library's cell now asks for a shared well instead of writing its own, and the two shots differ only in the clock. |
| `ios-home` | — | Unchanged too. Home's well lost its own copy of the same code; its padding is now derived from whether a format is named rather than set separately, and the visible result is the same. |

## What was actually wrong

Three surfaces draw a cover-shaped well: the library's grid, Home's shelf, and the downloads
destination. `CoverlessWell.swift` already shared **the rule** about what a well does as the
reader's text grows — its own comment calls the two copies it replaced "two wells, one
defect" — but it shared only the rule. The view was still written out twice, and the third
surface had never had one at all.

So the file now owns the well itself, and the surfaces ask for it. The one thing that
genuinely differs between them is whether the format is named, and the layout follows from
that rather than from three separate opinions: a well that names a format keeps its title
clear of the label at the bottom, and a well that does not simply centres it.

## Why nothing caught this

Worth writing down, because the same blind spot will produce the same kind of defect again.

The well is `accessibilityHidden` and the caption below the cell carries the title, so the
screen reads correctly to VoiceOver whether or not anything is drawn in the box. Apple's
audit has exactly one finding on Downloads and it is about contrast. This paragraph first claimed Android's own
scanner had seen it, naming `UNNAMED View` and `SMALL View 114.3x14.1dp` from
`pnpm smoke:android:a11y`. **That was not verified and is probably wrong**: 14 dp is a tenth
the height of a cover cell, so whatever those two were, they were not a well. A reviewer
declined to repeat the claim, which was the right call — and the whole walk now reports 16 of
16 routes with no accessibility findings at all, so they cannot be identified after the fact
either.

A defect invisible to every automated check and obvious to anyone looking at the screen is
the case §6 of [`AGENTS.md`](../../../AGENTS.md) asks for a screenshot to catch. It went
unnoticed until someone photographed the screen for an unrelated reason.

## The Android half, closed — and it was larger than this note said

This section used to name one Android surface, `OnDeviceCover` in
`apps/android/app/src/main/kotlin/app/storyarc/DownloadsParts.kt`, as the whole of the
remaining work. It was three. Android has **four** cover-shaped cells holding a
`Publication`, not iOS's three, and only the library's drew a well:

| Surface | Before | Now |
| --- | --- | --- |
| `CoverGrid`'s cell — the library shelf | The well, written out inline. | Asks `CoverlessWell`. |
| `OnDeviceCover` — the Downloads shelf | Empty rectangle. | The title, with the format beneath it, as the library shows them one destination away. |
| `HomeCoverArt` — Home's hero and shelf cells | Empty rectangle. **Not named in this note.** | The title. No format: nothing on Home names one. |
| `DetailSeriesCell` — a publication page's series shelf | Empty rectangle. **Not named in this note.** | The title. No format: the shelf's captions are the volume number and the read state. |

`android-downloads-tablet-default-light.png` in this directory is the before picture, taken
for an unrelated reason: five of the twenty-five cells fully on screen — `no-pages` and four
of the six `rar4`/`rar5` fixtures — are bare `surfaceSunken` cream, near-indistinguishable
from the page behind them, while every cell around them carries artwork.

`android-home-default-light.png` is **not** a picture of the Home defect, and it is worth
saying so because it looks like one. Its three cells are blue-grey where the Downloads
capture's same publications are solid blue: that is cover art at `AWAY_ALPHA` 0.45, because
all three read *Can't be opened right …*, not an empty well. No committed capture happens to
show Home or a series shelf holding a coverless publication, which is a good part of why
neither was noticed.

The view lives in `:core:designsystem`'s new `cover/` package — public API, beside the `grid/`
package `rememberCoverColumns` moved into the same afternoon, for the same structural reason:
`CoverGrid`'s cell is private to `:feature:library`, so `:app` could not call it however much
it should. One parameter, `format: String?`, is the only thing that genuinely differs between
the four.

Four further wells are deliberately untouched and named in `cover/CoverlessWell.kt`:
`DetailHero`'s hero draws a book glyph and no title, because a publication page reads its
title out of the app bar; and `CatalogueEntryCell`, `KavitaSeriesGrid` and
`CatalogueDetailScreen` stand for an OPDS entry or a Kavita series rather than a
`Publication`, so they have no format to name. **Two** text roles between the three, not
three, and an earlier draft of this line said three: `CatalogueEntryCell` and
`KavitaSeriesGrid` are the same well twice over — `bodySmall`, `textSecondary`, centred,
`maxLines = 4`, ellipsised, `StoryArcSpace.sm` either side, differing only in whether the
title comes off an entry or a series — and `CatalogueDetailScreen`'s is `titleMedium`. That
makes them *more* consolidatable than the line claimed, not less. Converting them still
changes what three remote-browsing screens look like and still belongs with its own capture.

## Two defects this change introduced, and what closed them

Neither was visible in this note's first version, and both were found by review rather than
by a gate.

**The Downloads cell announced its title twice.** `OnDeviceCover` wraps its cell in a
`combinedClickable`, which merges the whole cell into one spoken node, and the caption at the
foot of that cell is what labels it. A well drawn inside the box therefore *added* to the
label: `Foreign Codec, CBZ, Foreign Codec` — the title twice and a format the caption does
not carry. iOS never had this because `.accessibilityHidden(true)` has sat on that box all
along, and the first draft of `CoverlessWell.kt` cited that iOS fact without applying it.
`CoverlessWell` now clears its own semantics for every caller, which is where the rule
belongs: it was four callers' business before the view was shared and three of them got it
wrong by not writing it at all.

The other three surfaces were checked one at a time rather than given the same answer by
assumption, because what is right depends on whether the cell already speaks for its
children:

| Surface | What labels the cell | Effect of the clear |
| --- | --- | --- |
| `OnDeviceCover` — Downloads | a caption `Text` under the box, inside the merging node | **load-bearing.** Removes a duplicate title and a format that was never spoken. |
| `CoverGrid`'s cell — the library shelf | an explicit `contentDescription` on the same merging node, which TalkBack prefers over descendant text | inert; the label was already correct. |
| `HomeCoverArt` — Home | `Modifier.homeCardSemantics`, which ends in `clearAndSetSemantics` on the whole card | inert; an ancestor already cleared it. |
| `DetailSeriesCell` — a series shelf | a `contentDescription` on the cell's `Column`, naming title, volume and read state | restores the state before this change. The inner `Surface(onClick)` is an unlabelled button either way — pre-existing, and not this change's to fix or to paper over with a second copy of the title. |

**The title's fourth line was drawn under the format label from `font_scale 1.5` up.** This
one was inherited from the library shelf, not invented — the title was centred in the whole
well with the label laid on top of it — and sharing the view spread it to Downloads, which is
a screen this batch photographs at exactly that scale
(`android-downloads-tablet-scale15-light.png`). Measured at a 104 dp well: the title ran to
142 px against a label starting at 128. The well is a column now, so the label's height is
reserved rather than drawn over and the title has a box of its own to wrap and truncate
inside. `maxLines` stays at 4 — Compose lays a `Text` out inside the height it is given, so
the box caps the line count without being told to, and a conditional there killed no mutation
the box did not already kill.

It costs the title about half the label's height at the default size, where it is now centred
in the space above the label rather than in the whole well. **That is a visible change on the
two surfaces that name a format** — the library shelf and Downloads — including the library
shelf, which was not broken.

**This still owes an Android after-picture, and now owes more of one.** What the tests prove:
`:app`'s `DownloadsCoverlessWellTest` composes the Downloads cell and asserts both that the
well is drawn and that the cell announces the title once with no format;
`:feature:library`'s `CoverlessWellTest` composes `CoverlessWell` and `HomeCoverArt` — in
isolation, not inside `HomeKeepReadingCard` or `HomeShelfCell`, and an earlier version of this
line said "composes Home's card", which overstated it. In the real tree Home's card is wrapped
in `clearAndSetSemantics`, so a text lookup finds nothing there; what that test proves is that
the composable draws the title, not that Home's card does. `ShelvesDrawOneWellTest` reads all
four call sites and their `format` arguments. Every one of those was re-run against a hand
reverted fix and observed to fail.

What none of them proves is what the four screens look like. §6 of
[`AGENTS.md`](../../../AGENTS.md) asks for a photograph of Downloads and Home from a booted
emulator, light and dark, and the title's new position on the library shelf and Downloads now
asks for one at `font_scale 1.5` as well. Nothing in this directory is that yet.

## The iOS mirror of Android's chip row, settled

`ios-library-ax5` is the library at `AccessibilityXXXL`. It is here to answer a question
asked of the Android chip-row work: does iOS's equivalent row overflow the window at the
largest text size, the way Android's did at `font_scale 2.0`?

It does not, and the reason is that the two platforms do not draw the same control. Both
offer the same three choices — narrow to what is on this device, choose an order, filter —
and iOS puts them in a toolbar as **icons**, which do not grow with the reader's text. The
toolbar capsule is the same width at AX5 as at the default size. Android draws them as
**labelled chips**, which do, which is why that row had to learn to wrap.

So there is no iOS half of that defect to fix. The shelf below drops to two columns and the
titles read in full.

One thing the picture also shows, not fixed here: the author line truncates to `Ada Lov…`
while the title above it wraps to two lines and reads whole. That is a `lineLimit`, not a
clip, and the identifying half of the caption survives — but it is the kind of thing
`design.md` §3's "no clipping" rule is worth being asked about, and nobody has.

---

# The three Android fixes of 2026-08-31, second batch

`storyarc-j6` emulator. Phone shots at its own 1080×2400 / density 420 (411 dp wide); tablet
shots at `wm size 1600x2560` and `wm density 240` (1067 dp, past `design.md` §4's 840 dp
breakpoint). Every shot taken with `pnpm capture:android`, which walks to the screen, sets the
condition, and puts the device back.

**Every number below was read out of the live accessibility tree, not off the picture.** The
practice earned itself twice in one afternoon: once when the density regex took the *physical*
420 instead of the *override* 240 and reported a 168 dp cover as 96, and once when a
one-column tablet pane looked like it had room for two and the arithmetic said 328 dp wanted
against 320 available.

## The cover-width rule, one home

| Claim | Measured before | Measured after |
| --- | --- | --- |
| Downloads honours the 168 dp maximum at a 1067 dp window | **5 columns, 175 dp**, shelf running to x=1047 | **5 columns, 168 dp**, shelf ending at x=1004 with the leftover as trailing margin |
| Downloads takes the accessibility step | — | **4 columns, 224 dp** at `font_scale 1.5` |
| Home's shelves widen with the reader's text | 130 dp at any text size | **130 dp → 182 dp** from `font_scale 1.0` to `1.5` |

`android-downloads-tablet-default-light` / `-dark` and `-scale15-light` are the first two rows;
`android-home-default-light` and `android-home-scale15-light` / `-dark` are the third.

**What could not be photographed, and why.** The keep-reading *hero* — `homeHeroWidth`, the
200/240/280 ladder this batch also put on the step — is not on any of these shots, because
this corpus produces no Keep reading section: `LibraryIndex.continueReading` selects on
`ReadState.IN_PROGRESS`, and the fixtures that carry progress do not reach that state. Its
arithmetic is pinned by six unit tests whose mutations were re-run and killed, and the shelf
half of the same commit is measured above. The hero itself is unphotographed and this says so
rather than implying the row above covers it.

## The reader's chrome follows the appearance the reader chose

`android-epub-chrome-oled` and `android-epub-chrome-light`, both with the **device in light
mode** and only the app's own setting changed. The chrome band sampled out of the PNG:

| App appearance | Reader chrome |
| --- | --- |
| OLED Dark | `#0E0E0E` |
| Light | `#F4EEE4` |

Before the fix both were cream, because the reader passed `AppearanceMode.SYSTEM` and followed
the device. The before-shot is `../before-2026-08-31b/android-epub-chrome-oled.png`, and the
control beside it — the library drawn true black on the same device at the same moment — is
what makes it evidence rather than an assertion.

Note what does **not** change: the page stays paper cream under a true-black bar. That is the
requirement, not a miss. `settings-and-about` keeps the reading theme separate from the app's
appearance, "because a dark app chrome with a paper-white page is a legitimate preference".

The fixed-layout reader is a separate surface with deliberately dark chrome in every
appearance, like the comic reader. The first attempt at these shots photographed it by
accident — `', EPUB'` matched `fixed-layout.epub` first — and would have read as the fix
failing in Light.

## Home stopped disagreeing with the library about what can be opened

Found while setting these captures up, not looked for. With a picked folder answering, Home
labelled four part-read publications **"Can't be opened right now"** and went on saying so for
fifty-two seconds, while the library one tap away drew the same publications undimmed.

`HomeDestination` was answering the question itself, and had both of the mistakes the shared
rule documents avoiding: it read `SourceConnectionState.canFetch`, which the rule refuses
because every source is probed on launch and "still asking" is not "cannot be reached", and it
consulted the format, which the rule refuses because that "would conflate 'your network is
down' with 'this file is a CB7'". Home asks `isReadableNow` now. Measured after: **0 of 4**.

## The chip rows wrap instead of running off the window

`android-download-limit-es-scale2-light`, at **320 dp** (`wm size 1080x2400`,
`wm density 540`), `font_scale 2.0`, Spanish. Measured from the tree:

| Chip | Size | Position |
| --- | --- | --- |
| Sin límite | 110×37 dp | x=40..151, y=303 |
| 1,0 GB | 76×37 dp | x=187..263, y=303 |
| 5,0 GB | 76×37 dp | x=40..117, y=355 |
| 20 GB | 71×37 dp | x=153..223, y=355 |

Two lines, every chip inside the 320 dp window with 57 dp to spare, none truncated and none
squeezed into a column of letters. Those were the three things named as falsifying the change.

Spanish rather than the German the earlier rounds assumed: the app ships four locales and
Spanish is the longest. `Tamaño en este dispositivo` exceeds a full 320 dp window on its own,
which is the single-chip-wider-than-the-row case an earlier comment declared unreached.

The **reading list's** order chips — the row that case belongs to — are not photographed here.
Reaching them needs a reading list with a sort override on a device whose language is Spanish,
and the route map this harness walks is English-only, which is a real gap in the tooling and
not a claim about the code. `ListOrderChipsWrapTest` covers that row in all four locales and
fails in all four when its `FlowRow` becomes a `Row`, which was re-run before merging.

## Two things this batch's captures found in the harness itself

**It photographed a splash screen and filed it as Home.** `capture-android.mjs` waited a fixed
3.5 seconds, which is enough for a warm start and not for the first launch after an install.
That is precisely the failure its own header claims to prevent. It now waits for a node
carrying text, because a splash screen is an image and nothing else.

**The crash walk was counting failures instead of routes.** `16/16 routes walked and survived`
became `13/16` the moment `--a11y` was on, because three unnamed views were subtracted from the
route count. An hour went into chasing that as a regression, and it was one line below the
comment explaining that conflating these outcomes is how the script had already lied once.

## The Android well, photographed — and the one surface that could not be

`android-downloads-well-default-light`, `-default-dark` and `-scale2-light`, scrolled to where
the coverless fixtures are. Every one of them draws what the library has drawn all along:

| Cell | Well | Format |
| --- | --- | --- |
| `no-pages` | title centred | `CBZ` |
| `rar4-compressed` | title over two lines | `CBR` |
| `rar4-solid` | title centred | `CBR` |
| `rar5-compressed` | title over two lines | `CBR` |

Before this change all four were bare cream boxes. The `-scale2-light` shot is the one that
settles the layout finding a reviewer raised: at `font_scale 2.0` — beyond the 1.5 the finding
named — `no-pages` and its `CBZ` are clearly separated, because the label's height is now
reserved by a `Column` rather than overlaid. The collision cannot come back by arithmetic.

**Home's well is not photographed, and this says so rather than filing a picture that proves
something else.** Its shelves hold only publications with cover art on this corpus — *Recently
added* and *Finished* draw `archive-comment`, `data-descriptor` and `double-page-spread`, all
three of which have artwork — so there is no coverless card on that screen to capture. Home's
well is proven by `CoverlessWellTest`, which composes the card and asserts both that the title
appears and that **no** format node exists, and which fails when the branch is neutered. A
genuine Home capture needs a corpus with a readable coverless publication recent enough to
reach a shelf.

The earlier `android-home-default-light.png` in this directory is **not** a before-picture of
this defect and must not be read as one: its cells are cover art dimmed to `AWAY_ALPHA`, which
is why they look washed beside the Downloads captures of the same publications.
