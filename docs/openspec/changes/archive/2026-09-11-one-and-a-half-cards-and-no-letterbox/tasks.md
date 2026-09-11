**What a tick means.** The code exists and something asserts it, and for a
layout that means a device frame as well as a test — this is a change nobody can
check by reading.

## 1. One size, one and a half of them

- [x] 1.1 Assert the height claim before touching it: `HomeHeroHeightTest` passes now and states what it protects. It is the control for the rest.
- [x] 1.2 Swap the multi-browse carousel for an uncontained one, and widen `homeHeroWidth` so about one and a half cards fit a phone. Verify: `HomeHeroHeightTest` still passes, and the frame in 3.1 shows one and a half.
- [x] 1.3 Write the test for the width arithmetic: at a phone's width about one and a half cards fit, at a tablet's more do, and the number is never below one whole card.

## 2. No letterbox, and nothing cropped

- [x] 2.1 Write the test that the artwork area takes the cover's own aspect, bounded by what a 2:3 cover of that width would take, and that a cover past the bound scales down rather than cropping. Red before 2.2.
- [x] 2.2 Draw the cover at its own aspect inside that bound. Verify 2.1 passes and that no call site asks for a crop.
- [x] 2.3 Assert the card's height is unchanged by the cover's shape: two cards with covers of different aspects are the same height.

## 3. The actions are where the thumb is

- [x] 3.1 Write the test that the resume affordance is at the same offset from the card's foot whatever the title's line count and whether a byline exists. Red before 3.2.
- [x] 3.2 Bottom-anchor the caption block. Verify 3.1 passes.

## 4. Seen on a device

- [x] 4.1 Screenshot Keep reading on the OnePlus 7T Pro (`f7cee850`) with at least two publications, light and dark, default and largest text. Control: the frame from before this change, which shows three sizes, letterboxing and two buttons at two heights.
- [x] 4.2 The same on the iOS simulator. The row already had one size and a foot-anchored caption; what changed there is the width, and `HomeHeroWidthTests` asserts it.

## 5. The gates

- [x] 5.1 `pnpm test:android`, `pnpm test:ios`, `./gradlew lint` clean for every module touched.
- [x] 5.2 `pnpm lint` green.
- [x] 5.3 `pnpm spec:validate && pnpm spec:guard` green.
