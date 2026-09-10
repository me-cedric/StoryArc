**What a tick means.** The code exists and something asserts it. A tick does not
mean a reader has used the screen; the device frames say which device.

## 1. The zone is a third

- [x] 1.1 `ReaderTapZonesTest` and `ReaderTapZonesTests`, six cases each: the fraction, both turn zones, the middle, the boundaries belonging to the middle, the setting off, and a wider screen keeping the same three shares. Right-to-left needs no case of its own on either platform — the display order is already reversed, so a step right is a step right whichever way the story runs, which the existing turn tests cover.
- [x] 1.2 A third on both. `ReaderGestureTest` needed one edit and it is worth naming: it guards the gesture by matching `isEdgeTap(point, size)` in the source, and the call gained an argument, so the literal it matches is now the name and the first two arguments. The gesture is what it guards, not the arity.
- [ ] 1.3 Not asserted. `ReaderScreen` rescales the point for a spread and the code is unchanged by this work, but nothing pins it and a third makes the failure larger than a quarter did.

## 2. A setting turns them off

- [x] 2.1 In the same pair of files, as the fifth case each.
- [x] 2.2 `turnPagesByTappingTheEdges`, true by default, reaching the reader by `LocalTapTurnsPages` on Android and a `turnPagesByTappingTheEdges` environment value on iOS — the reader is a feature module on both and does not read the settings store. `isEdgeTap` follows it too: with no turn to protect, every tap is free to become a double-tap zoom.
- [x] 2.3 A switch on Android and a toggle on iOS, both beside the volume row, both with the note. Two strings in four languages on each platform; `strings:drawn` and `strings:ios` green.
- [ ] 2.4 Not asserted directly. The default is on the field on both platforms and the settings round-trip tests cover the store, but no test says "never written means on".

## 3. Seen on a device

- [ ] 3.1 Screenshot the settings row on the OnePlus 7T Pro (`f7cee850`), light and dark.
- [ ] 3.2 Turn the zones off on the device, tap each third of a page, and record that the page did not turn and the chrome toggled. A frame per third, with the control frame from before the change.
- [ ] 3.3 The same on the iOS simulator.

## 4. The gates

- [ ] 4.1 `pnpm test:android`, `pnpm test:ios`, `./gradlew lint` clean for every module touched.
- [ ] 4.2 `pnpm lint` green, including the four-language check for the new string.
- [ ] 4.3 `pnpm spec:validate && pnpm spec:guard` green.
