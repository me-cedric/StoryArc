## 1. Spec and rules

- [x] 1.1 Write this change: proposal, design, the `native-experience` delta and these tasks.
- [x] 1.2 Rewrite `AGENTS.md` section 6 to the new rule: the builder looks at its own screen; snapshot tests and accessibility checks; a device screenshot only where a snapshot cannot show the screen; downscale. Point `docs/design.md` section 11 at it.
- [x] 1.3 `pnpm preview:proof` accepts a snapshot reference (`__Snapshots__/` on iOS, `src/test/snapshots/` on Android) as proof, with self-test cases for both.
  - Built: `scripts/preview-proof-check.mjs` accepts a `.png` under `__Snapshots__/` or `src/test/snapshots/` as proof. The self-test has one iOS case and one Android case.
- [x] 1.5 agent-device in `.mcp.json` and `pnpm device`, pinned to 0.21.22, smoke-tested on an iOS simulator.
- [x] 1.4 `pnpm frames:shrink` downscales new frames with `sips` to 1200 px on the long side.
  - Built: `scripts/frames-shrink.mjs` shrinks each new frame with `sips -Z 1200`. It skips a frame that is already 1200 pixels or less.

## 2. Android

- [x] 2.1 Add Roborazzi to the version catalogue and to the Compose feature modules' unit tests, with `@GraphicsMode(NATIVE)`, references in `src/test/snapshots/`, and `pnpm snap:android` and `pnpm snap:android:record`.
  - Built: Roborazzi 1.76.0 in the version catalogue, the `:core:snapshots` test module, `@GraphicsMode(NATIVE)`, references in `src/test/snapshots/`, and `scripts/snap-android.mjs` behind `pnpm snap:android` and `pnpm snap:android:record`.
- [x] 2.2 Snapshot tests for the screen catalogue, light and dark.
  - Built: 17 `Catalogue<NN><Name>Test` classes in `:app`, `:feature:library`, `:feature:settings`, `:feature:reader` and `:feature:epubreader`, light and dark, 34 references.
- [x] 2.3 Accessibility Test Framework checks (`enableAccessibilityChecks()`) over the screen catalogue. A test proves that a 40 dp target fails.
  - Built: the Accessibility Test Framework checks nothing under Robolectric (design.md), so `:core:snapshots` reads the Compose semantics tree: touch targets, labels and contrast. `AccessibilityChecksTest` proves that a 40 dp target fails.

## 3. iOS

- [x] 3.1 Add swift-snapshot-testing to the test targets that hold views, with references in `__Snapshots__/`, and `pnpm snap:ios` and `pnpm snap:ios:record`.
  - Built: swift-snapshot-testing 1.19.6 in the app-hosted bundle `StoryArcSnapshotTests` (`apps/ios/SnapshotTests`), references in `__Snapshots__/`, and `scripts/snap-ios.mjs` behind `pnpm snap:ios` and `pnpm snap:ios:record`.
- [x] 3.2 Snapshot tests for the screen catalogue, light and dark.
  - Built: `LibraryCatalogueTests`, `DetailAndPlayerCatalogueTests`, `SettingsCatalogueTests` and `ReaderCatalogueTests` draw entries 01 to 17 and 05b, light and dark.
- [x] 3.3 The accessibility audit (`AuditWalk`, hit region and contrast included) reaches every screen of the catalogue that a UI test can reach. A test proves that a 30 pt target fails.
  - Built: `CatalogueAuditTests` walks the app to each reachable screen and runs `performAccessibilityAudit`. It measures each control against 44 pt itself. `testAThirtyPointTargetFails` proves that a 30 pt target fails.

## 4. Catalogue and CI

- [x] 4.1 `docs/designs/screen-catalogue.md` lists the screens and states, with the test that draws each on each platform.
  - Built: `docs/designs/screen-catalogue.md` names the iOS test, the iOS audit and the Android test and images of each entry.
- [x] 4.2 The snapshot verifications and the accessibility checks run in `pnpm test:ios`, `pnpm test:android` and CI.
  - Built: `pnpm test:ios` runs the host tests, then `pnpm snap:ios`. `pnpm test:android` passes `-Proborazzi.test.verify=true`. CI runs the Android accessibility checks with `./gradlew test`. CI does not compare images, because the references are recorded on macOS.

## 5. Verify findings, 2026-10-10

The verify step of the docs pass found that two scenarios of the delta state more than the code does. The change stays active until each item below is closed, by code or by an owner decision that changes the delta.

- [x] 5.1 iOS: text under the contrast floor fails the catalogue audit (scenario "Guidelines are checked by machine"). Now `auditCatalogue` in `apps/ios/UITests/CatalogueAuditTests.swift` fails only `.hitRegion` and `.sufficientElementDescription`, and it prints contrast and clipped-text findings. Android fails on contrast. Alternative: the owner rules that `pnpm tokens:check` is the iOS contrast check, and the delta says so. Done 2026-10-10: a contrast finding that names an element fails `auditCatalogue`; a drained known-fault list in `apps/ios/UITests/CatalogueVerdict.swift`; proved with a faint label behind `-storyarc.audit.targets`.
- [x] 5.2 The largest text size (scenario "Both appearances"). No snapshot test draws it: no iOS snapshot sets a content size category, and no Android catalogue test sets `fontScale` (`docs/designs/screen-catalogue.md`, "The largest text size"). The iOS audit prints Dynamic Type findings and does not fail them. Add a largest-size snapshot or a failing check on each platform, or the owner changes the scenario. Done 2026-10-10: both platforms draw each catalogue screen in light at the largest text size (iOS AX5 `.largest.png`, Android font scale 2.0 `-largest.png`); the first run found and fixed seven layout faults.
- [x] 5.3 iOS: `CatalogueAuditTests` is in `StoryArcUITests`, so only `pnpm test:ios:ui` runs it. `pnpm test:ios` runs the host tests and `pnpm snap:ios`, and `.github/workflows/ios.yml` runs neither UI tests nor snapshots. Task 4.2 holds for Android only until a gate runs the iOS audit. Done 2026-10-10: `pnpm test:ios:audit`, and a "Catalogue audit" step in `.github/workflows/ios.yml` (entry 02 left out: the seed gives the device a library).
- [x] 5.4 Android: catalogue entries 05b and 18 have no snapshot test, and the iOS audit cannot reach 05b (`docs/designs/screen-catalogue.md`). Done 2026-10-10: Android catalogue tests and references for 05b and 18.
- [x] 5.5 `AGENTS.md` section 6 names the `:core:snapshots` checks for Android (not `enableAccessibilityChecks()`), and says which iOS findings fail and which are printed. Done 2026-10-10 in the docs pass.
