## Context

See proposal.md — Why. The four symptoms have two causes.

`HomeScreen` builds the row with `HorizontalMultiBrowseCarousel`, whose whole
purpose is to mask items to three sizes. `HomeCards` then fixes the artwork area
at `width * HOME_COVER_ASPECT` — 2:3 — and `HomeCoverArt` letterboxes anything
that is not that shape onto `surfaceSunken`, which the file's own header defends
at length and correctly: the alternative it was arguing against was *cropping*.

## Goals / Non-Goals

**Goals:**

- One card size, arrived at once, so the row and the height function cannot
  disagree.
- No bar of background around a cover, and no cover cropped.

**Non-Goals:**

- Design-level: no per-card sizing, no aspect the reader can choose.

## Decisions

**An uncontained carousel, not a multi-browse one.**
`HorizontalUncontainedCarousel` draws every item at one width and lets the next
one run off the edge, which is exactly "one and a half cards" and exactly "the
same size every time". Alternative considered: a `LazyRow`, which would also do
it. Rejected because the carousel keeps the snapping and the mask the row
already has, and `maskClip` at the call site is written for it.

**The card's height is fixed and the artwork's is not.** This is the resolution
of what looks like a conflict between the reader's two requests. *No letterbox*
and *every card the same height* cannot both hold if the artwork area is a fixed
shape — one of them has to give, and cropping is not on the table. So the
artwork is drawn at its own aspect inside a **bounded** area, and the card's
fixed height absorbs whatever the cover does not use: a shorter cover leaves
more room for the caption block below it rather than a black bar above and below
it. The row keeps one height; no cover is letterboxed; nothing is cropped.

**The bound is the artwork's *maximum* height, not its height.** A very tall
cover — a manga volume at 1:1.6 — must not push the caption off the card, so the
area caps at what a 2:3 cover of that width would take. Past that the cover
scales down to fit, which is still whole and still uncropped.

**The caption block is bottom-anchored.** Artwork at the top; title and byline
under it; a flexible space; then progress and the resume affordance at the foot.
That is the answer to "what should be pushed top or bottom": what the card *is*
goes with the artwork, what a reader *does* goes where their thumb is, and the
variable part — a title that wraps, a byline that is missing — is absorbed
between the two rather than at the bottom.

**Platform APIs.** Android: `HorizontalUncontainedCarousel` from the same
`material3.carousel` package the current row uses, so no dependency changes;
`Modifier.weight` for the flexible gap. iOS: the row is a `ScrollView` with a
fixed item width, and `Spacer()` for the same gap. Verified present, not
assumed.

**Accessibility.** The card is already one merged node with a label; nothing
here changes what it says. The larger card is a larger target for the same
action, which is the direction accessibility wants. At the largest text size the
caption block grows and the artwork's bound shrinks to keep the card's height,
which is the same trade the height function already makes and which the device
frames at `font_scale 2.0` have to show.

## Risks / Trade-offs

- **A cover much shorter than 2:3 leaves a large gap under the artwork.** →
  The caption block is directly under the artwork rather than pinned below a
  fixed area, so the gap lands between the caption and the actions, where it
  reads as spacing rather than as a missing thing.
- **`HomeHeroHeightTest` asserts the arithmetic of a height that changes.** →
  It calls `homeHeroBlockHeight`, so it follows the change; what it must keep
  asserting is the claim, that the next heading is visible without scrolling,
  and the device frame is what proves it.

## Migration Plan

None. Nothing is stored about the row.
