# One and a half cards, and no letterbox — 2026-09-10

Keep reading on the home surface, photographed on a OnePlus 7T Pro
(`f7cee850`, 1440 × 3120, 2 comics part-read). Change:
`one-and-a-half-cards-and-no-letterbox`, task 4.1.

## Before

`android-keep-reading-before.png` — the frame the reader reported. Three
faults in one picture:

- **Two and a half cards fit**, and the third is a sliver.
- **The artwork is letterboxed.** A bar of the recessed surface colour sits
  above and below the *Superior* cover, which reads as black on the dark
  theme.
- **The two Resume buttons are at two heights**, because the second card has a
  byline and a title that wraps and the first has neither.

## After

| Frame | Text size | Theme |
| --- | --- | --- |
| `android-keep-reading-light.png` | default | light |
| `android-keep-reading-dark.png` | default | dark |
| `android-keep-reading-light-largest.png` | 200% | light |
| `android-keep-reading-dark-largest.png` | 200% | dark |

What the frames show at the default text size: about one and a half cards
across, both cards the same size, both covers drawn edge to edge with no bar
around them, and both Resume buttons on one line at the foot of their card.

## iOS

`ios-keep-reading-light.png`, `-dark.png`, `-light-largest.png`,
`-dark-largest.png` — iPhone 17 Pro simulator, two comics part-read.

The iOS row had only one of Android's four faults: its cards were already one
size, its caption was already at the foot of the card, and its artwork already
fits inside a blurred copy of itself rather than onto a bar. What changed is
the width — the card took 0.86 of the *window*, which put one card and a
sliver on a phone. It now takes the same share of the room that Android does,
so the second card is plainly a second card.

The two comics were part-read by writing two progress records into the
simulator's own store, because the reader's chrome would not stay on screen
long enough to close it by hand. The records say page 3 of 8 and page 2 of 8,
which is what the captions read back.

## What the 200% frames also show, and what is not fixed

At 200% the row is taller than the space above the navigation bar, so the foot
of each card is below the fold and a reader scrolls to it. The button's own
label wraps inside the button. Both are out of this change's scope — the
`home-screen` scenario about the next heading is written for "the default text
size", and the wrapped label is the Material button doing what it does in a
narrow card. They are recorded here so the next reader knows they were seen
and left, not missed.
