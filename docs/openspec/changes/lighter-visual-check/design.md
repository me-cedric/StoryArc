## Context

The proof rule is `AGENTS.md` section 6 and the gate `scripts/preview-proof-check.mjs`. The capture code is the iOS UI-test walks (`apps/ios/UITests`, about 11,000 lines) and the Android routes (`scripts/android-routes.mjs`, `scripts/capture-android.mjs`). The Android unit tests already run Compose on Robolectric.

## Goals

- The agent that builds a screen sees it in seconds, in light and dark, without a walk through the app.
- A guideline fault (hit target, contrast, label, clipping) fails a test without a person looking.
- No frames agent after a merge. No emulator queue for a screen that a JVM can draw.

## Non-goals

- Store screenshots. Performance proofs (frame timing, curl recordings). The device checklist.

## Decisions

1. **swift-snapshot-testing (MIT) for iOS.** It renders a SwiftUI view in a `UIHostingController` inside the unit-test host on a booted simulator, so it uses the real UIKit drawing. Use `.image(precision:perceptualPrecision:)` with a perceptual precision near 0.98, so a sub-pixel antialiasing change does not fail. References live beside each test in `__Snapshots__/`.
2. **Roborazzi (Apache 2.0) for Android.** It captures Compose on Robolectric with `@GraphicsMode(NATIVE)`, on the JVM, with no emulator. References live in `src/test/snapshots/` of each module. `pnpm snap:android` verifies; `pnpm snap:android:record` records.
3. **Guideline checks by machine.** iOS: `performAccessibilityAudit` in the UI-test target over the screen catalogue (`AuditWalk` exists). Android: Compose `enableAccessibilityChecks()` with the Accessibility Test Framework in the Robolectric tests of the catalogue.
4. **One screen catalogue, two platforms.** A list of screens and states that both platforms name the same way (home, library grid and list, publication page with and without a cover and its cover menu, player, reader chrome per format, settings, sources, sync, downloads, search). Each entry has a snapshot test in light and dark, and an audit. An agent that adds a screen adds its entry.
5. **A device screenshot only where a snapshot cannot show it.** Navigation, system materials (Liquid Glass over content), insets, system UI (shade, widgets, CarPlay), and web view content. One light and one dark per changed screen, downscaled with `sips` to 1200 px on the long side.
6. **The gate.** `pnpm preview:proof` passes a branch that changes drawing code when the branch adds or changes a frame under `docs/designs/screenshots/` or a snapshot reference (`__Snapshots__/` on iOS, `src/test/snapshots/` on Android).
7. **Mobile MCP (Apache 2.0) to drive the running app.** `@mobilenext/mobile-mcp`, pinned in `.mcp.json`, gives an agent launch, tap, swipe, screenshot and the element tree with sizes, on an iOS simulator (Xcode and a booted simulator) or an Android emulator, without a UI-test walk. Its anonymous telemetry is turned off (`MOBILEMCP_DISABLE_TELEMETRY=1`). Its cloud-device tools are paid and are not used. Found in the owner-suggested collection `salmanashraf/mobile-ai-agents` (MIT); the rest of that collection is not adopted, because the project's rules and installed skills already cover its review prompts.
8. **Not adopted.** Maestro (open source CLI) would repeat the walks the repository already has, and its iOS real-device support is not official. Paid visual services (Applitools, Percy, Maestro Cloud) are out by the owner's rule, and their cloud devices cannot reach the local Kavita and Samba fixtures. Google's Compose Preview Screenshot Testing renders `@Preview` functions only and was alpha.

## Risks

- A snapshot draws a material or a blur differently from a device. Decision 5 keeps a device screenshot for those screens.
- Reference images add weight to the repository. Keep the catalogue small, and record at scale 1 on iOS and at the default Robolectric density on Android.
