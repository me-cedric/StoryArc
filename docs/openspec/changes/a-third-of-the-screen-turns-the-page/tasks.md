**What a tick means.** The code exists and something asserts it. A tick does not
mean a reader has used the screen; the device frames say which device.

## 1. The zone is a third

- [x] 1.1 `ReaderTapZonesTest` and `ReaderTapZonesTests`, six cases each: the fraction, both turn zones, the middle, the boundaries belonging to the middle, the setting off, and a wider screen keeping the same three shares. Right-to-left needs no case of its own on either platform — the display order is already reversed, so a step right is a step right whichever way the story runs, which the existing turn tests cover.
- [x] 1.2 A third on both. `ReaderGestureTest` needed one edit and it is worth naming: it guards the gesture by matching `isEdgeTap(point, size)` in the source, and the call gained an argument, so the literal it matches is now the name and the first two arguments. The gesture is what it guards, not the arity.
- [x] 1.3 `spreadTap` is a function rather than two lines inside a lambda, because a test cannot reach a lambda in a `Row`. Four cases in `ReaderTapZonesTest`: the rescale itself, the leading half not being two thirds a turn zone, the middle of the spread toggling the chrome from either side of the fold, and the outer edges still turning.

## 2. A setting turns them off

- [x] 2.1 In the same pair of files, as the fifth case each.
- [x] 2.2 `turnPagesByTappingTheEdges`, true by default, reaching the reader by `LocalTapTurnsPages` on Android and a `turnPagesByTappingTheEdges` environment value on iOS — the reader is a feature module on both and does not read the settings store. `isEdgeTap` follows it too: with no turn to protect, every tap is free to become a double-tap zoom.
- [x] 2.3 A switch on Android and a toggle on iOS, both beside the volume row, both with the note. Two strings in four languages on each platform; `strings:drawn` and `strings:ios` green.
- [x] 2.4 `TapZonesDefaultTest` on Android and two added cases in `SettingsStoreTests` on iOS: never touched means on, settings written before the field existed still mean on, and a reader who turned it off keeps it off.

## 3. Seen on a device

- [x] 3.1 `docs/designs/screenshots/a-third-turns-the-page-2026-09-10/`, Android and iOS, light and dark.
- [x] 3.2 Four frames: the page before, then a tap in each third. The page is the same in all four and the controls come and go. The control is the pair with the zones on, where the trailing third turns and the middle third shows the controls.
- [x] 3.3 **And it failed.** With the zones off, an edge tap still turned the page: the reader read the environment value inside the closure a `UITapGestureRecognizer` calls, where `@Environment` gives back its default of `true`. `tapHandler` now reads the flag in the body pass and `handleTap` takes it as a parameter; `TapZoneWiringTests` guards the wiring, because no unit test can see it.

## 4. The gates

- [x] 4.1 `pnpm test:android`, `pnpm test:ios`, `./gradlew lint` clean for every module touched.
- [x] 4.2 `pnpm lint` green, including the four-language check for the new string.
- [x] 4.3 `pnpm spec:validate && pnpm spec:guard` green.
