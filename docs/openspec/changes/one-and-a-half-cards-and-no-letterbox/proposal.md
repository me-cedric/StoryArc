# One and a half cards, and no letterbox

**Platforms: both.** One row, drawn twice.

## Why

Four things a reader saw on the phone, in one screenshot of Keep reading.

**The cards are not the same size.** `HorizontalMultiBrowseCarousel` is doing
exactly what it is for: a multi-browse carousel masks its items to large,
medium and small on purpose. The row was built with it, and the result is a
hero, a smaller one beside it, and a sliver — three sizes for three cards that
are the same kind of thing.

**Two and a half fit, and the reader wants one and a half.** The same cause and
a different symptom: the card is sized so a third peeks, which is what a
multi-browse carousel is meant to do and not what this row is for.

**The artwork is letterboxed.** A bar of `surfaceSunken` sits above and below
every cover, because the artwork area is a fixed 2:3 and a cover that is not
2:3 is centred in it. On a dark theme that bar reads as black, and the covers
this was seen with are all shorter than the box.

**The resume affordance is at a different height on every card.** The card
stacks artwork, title, byline, progress and the button in order, so a title
that wraps to two lines or a byline that is missing moves the button. Two cards
side by side put their buttons at two heights.

## What Changes

- **Every card is the same width and the same height.** The row stops being a
  multi-browse carousel.
- **About one and a half fit across a phone**, so the second card is plainly a
  second card.
- **The artwork is drawn whole, at its own proportions, with no bar around it.**
  Not cropped — `design.md` is explicit that a cover cropped to a shape it is
  not loses the part of the artwork carrying the title. The artwork area takes
  the cover's own aspect and the card's fixed height absorbs the difference.
- **The resume affordance is pinned to the foot of the card**, so it is at one
  height whatever the title did. Artwork at the top, what it is under that,
  what the reader can do at the bottom.

## Capabilities

`skip_specs: true`, with the reason in `.openspec.yaml`: the three scenarios
this builds — one and a half cards, every card the same size, artwork not
letterboxed — are in `one-library-three-destinations`' own `home-screen` delta,
because that change ADDs the capability and there is no main spec to modify yet.

## Impact

- `apps/android/feature/library`: `HomeScreen`'s carousel, `HomeCards`'
  `homeHeroWidth`, `homeHeroBlockHeight`, `HomeCoverArt` and the card's column.
- `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature`: the same row.
- `HomeHeroHeightTest` and its iOS twin, which assert the height arithmetic.

## Non-goals

- **Not the other shelves.** Recently added and Up next are a different row and
  are unchanged.
- **No cropping**, in any form, on any surface.
- **No new artwork fetching.** The cover a card draws is the one it already had.
