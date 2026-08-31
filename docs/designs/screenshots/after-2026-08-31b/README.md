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
audit has exactly one finding on Downloads and it is about contrast. Android's own scanner
*did* see it — as `UNNAMED View` and `SMALL View 114.3x14.1dp` in `pnpm smoke:android:a11y`
— because it measures boxes rather than labels, and nobody had connected that line to a
missing placeholder.

A defect invisible to every automated check and obvious to anyone looking at the screen is
the case §6 of [`AGENTS.md`](../../../AGENTS.md) asks for a screenshot to catch. It went
unnoticed until someone photographed the screen for an unrelated reason.

## Still open on these screens

The Android half of the same defect. `OnDeviceCover` in
`apps/android/app/src/main/kotlin/app/storyarc/DownloadsParts.kt` has the identical empty
box, and the library's `CoverCell` is private to `:feature:library` — so the fix is the same
shape as the iOS one and was blocked on another change already moving code in that file.
Recorded in [the delivery note](../../../delivery/remaining-work-2026-08-31.md).

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
