# Tasks: foldables and iPhone Duo

**No task here is started.** The owner decided on 2026-10-23 that foldables are supported
later; this list is the plan, so that the work can start without a second planning pass. A
ticked box means the code exists on the platform named and a test or a snapshot asserts it. A
tick does not mean a person held a foldable device.

Waves run in order. Wave 0 can run alone and early, because it only removes what blocks the
rest and moves the SDK pin before the store deadline.

## 0. Prerequisites and the deadline

- [ ] 0.1 **iOS: move the CI Xcode pin to 27.1 and build with the iOS 27.1 SDK** (`.github/workflows/ios.yml`, `apps/ios/project.yml`). Verify: `pnpm build:ios` on CI; the app runs edge to edge on the `iPhone Duo` simulator (Device Hub) with no letterbox.
- [ ] 0.2 **iOS: a `release:check` rule that fails after 2027-03-01 when the Xcode pin is older than 27.1** (`scripts/release-check.mjs`, with a self-test). Verify: `pnpm release:selftest`.
- [ ] 0.3 **iOS: `UIScreen.main` leaves `ReaderBrightness.swift`** (D6). Test first: a host test that the brightness store reads and writes through an injected screen. Verify: `pnpm test:ios:host`, `pnpm lint:ios`.
- [ ] 0.4 **Both: a resize test from the outer to the inner size and back keeps the page, the sheet and the voice** (D5). iOS: `ReaderFeatureTests`; Android: `feature/reader` JVM test with `WindowClass` changes. Verify: the test fails when the reader rebuilds its state on resize.
- [ ] 0.5 **Android: the Pixel Fold emulator profile in `scripts/device-matrix.mjs`** at 841 x 701 dp open and the closed size, with the posture set through `adb emu fold` (Assumed command; check the emulator's console help). Verify: `pnpm capture:matrix --devices fold` boots it and writes a frame.
- [ ] 0.6 **Owner: answer Open Questions 1 and 2 of `design.md`.**

## 1. The fold as a reserved region

- [ ] 1.1 **iOS, test first: the hinge arithmetic of `HingeSlots.kt` ported as a pure function** (`StoryArcCore`, `HingeSplit.swift`): given a surface width and a division region, the side a page goes to and its width. Same cases as `HingeSlotsTest.kt`. Verify: `pnpm test:ios:host`.
- [ ] 1.2 **iOS: the comic page surface reads `ReservedRegion` of kind `.division` and moves the page to the wider side** (`ReaderFeature`). Verify: a snapshot on the `iPhone Duo` simulator, open, light and dark; the page edge does not cross the fold.
- [ ] 1.3 **Both: a spread puts its gutter on the fold** (`comic-reader` double-page spread). Android: `ReaderPageSurface.kt`; iOS: the spread view. Verify: a snapshot per platform in book posture with a two-page spread; the gutter x equals the fold x.
- [ ] 1.4 **Both: no control under the camera occlusion or the fold.** iOS: the reader chrome and the sheets read `.occlusion`; Android: `occlusionType`. Verify: the catalogue accessibility audit on the open display reports no element whose bounds cross a reserved region.
- [ ] 1.5 **Both: asymmetric insets.** Sweep the apps for `safeAreaInsets.left * 2` and for paddings mirrored from one edge. Verify: a grep in CI (`scripts/inset-symmetry-check.mjs`, with a self-test) finds none.

## 2. Postures

- [ ] 2.1 **Android, test first: the tabletop layout as a pure layout decision** (`core/designsystem`): posture `HALF_OPENED` with a horizontal fold gives page-above, controls-below; anything else gives the flat layout. Verify: JVM test.
- [ ] 2.2 **Android: the reader draws the tabletop layout** (D3), auto-hide off while it lasts, one announcement "Controls below" (four languages). Verify: Roborazzi at 841 x 701 dp with the posture faked; TalkBack reading order in the accessibility check.
- [ ] 2.3 **iOS: the same with the arrangement container** (D3, Assumed API). Verify: a snapshot on the `iPhone Duo` simulator at half-open; VoiceOver order in the audit.
- [ ] 2.4 **Both: book posture forces the spread and withholds Curl** (D4). Verify: a test that the transition picker offers no Curl in book posture; a snapshot with a right-to-left spread.
- [ ] 2.5 **Both: the outer display.** Walk the screen catalogue on the outer display size (iOS: `iPhone Duo` closed; Android: the Pixel Fold closed profile). Verify: the catalogue snapshots at that size, light, dark and largest; no clipped control; every target at 44 pt or 48 dp.
- [ ] 2.6 **iOS: Split View on the inner display.** Verify: the resize test of 0.4 with a half-width window and insets on the left; a snapshot on each side.
- [ ] 2.7 **Both: no posture reported draws the flat layout** (the failure scenario). Verify: the layout tests of 2.1 and 1.1 with a nil posture.

## 3. Store listings

- [ ] 3.1 **iOS: the `duo` bucket in `scripts/store-capture.mjs`** (D7): the `iPhone Duo` simulator, outer and inner, portrait, the six frames, four languages, written to `.build/store/appstore/<locale>/NN-name-duo-outer.png` at 1398 x 2034 and `-duo-inner.png` at 2007 x 2853. Verify: `pnpm store:capture --buckets duo --locales en-US`, then `pnpm store:verify` accepts the sizes.
- [ ] 3.2 **Android: the `fold` bucket** (D7): the Pixel Fold profile open and closed, the six frames, written to the Play large screen slot. Verify: `pnpm store:capture --buckets fold --locales en-US`, then `pnpm store:verify`.
- [ ] 3.3 **`pnpm store:verify` knows the Duo slot sizes and the April 2027 rule**: it warns while the set is missing and fails after 2027-03-01. Verify: `pnpm store:selftest`.
- [ ] 3.4 **Listing text**: one sentence per language in `docs/designs/store/*/listing/*.md` that names foldables. Verify: `pnpm store:verify` length rules.
- [ ] 3.5 **`docs/designs/store/README.md`**: the two buckets in the device table and the Duo sizes. Verify: read.

## 4. Proof and bookkeeping

- [ ] 4.1 **`docs/designs/screen-catalogue.md`**: a posture column (flat, tabletop, book, outer) for the reader, the player and the library entries. Verify: `pnpm preview:proof` accepts the new names.
- [ ] 4.2 **`docs/mvp-device-checklist.md`**: two owner steps, an iPhone Duo and a Galaxy Z Fold or Pixel Fold, each with the four postures and a spread.
- [ ] 4.3 **`/opsx:verify foldables-and-iphone-duo`**, resolve each critical finding, update the `native-experience` row of `docs/openspec/STATUS.md`, then `/opsx:archive`.
