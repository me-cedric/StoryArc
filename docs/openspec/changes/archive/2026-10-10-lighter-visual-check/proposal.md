## Why

The owner said on 2026-10-09 that taking frames wastes hours and resources. Each wave ran two frames agents after the merge. They walked the app again, seeded fixtures again, rebuilt the UI tests, and waited for the one emulator that the 24 GB Mac allows. A wave lost 2 to 5 hours to it. `docs/designs/screenshots/` holds 1,687 frames (461 MB).

The frames have one real job: the agent that built a screen must see it, and must check it against the Apple Human Interface Guidelines and Material 3. In waves 4 and 5 that look found about 14 defects that no test found. The job stays. The way to do it changes.

## What Changes

- The builder looks at its own screen while it builds, in light and dark, and fixes it before the change lands. No separate frames phase runs after a merge.
- Snapshot tests render each screen state with fixture data, in light and dark: swift-snapshot-testing on a booted iOS simulator, Roborazzi on Robolectric for Android. A changed image fails the test until its reference is recorded again.
- Machines check the guidelines: Apple's accessibility audit on iOS and the Accessibility Test Framework on Android run over every screen of a fixed catalogue. A hit target under 44 pt or 48 dp, a contrast failure, a missing label or clipped text fails the test.
- A device screenshot is taken only where a snapshot cannot show the screen: navigation, system materials, insets, system UI, and the content of a web view. At most one per appearance per changed screen, downscaled.
- `pnpm preview:proof` accepts a snapshot reference as proof. `AGENTS.md` section 6 states the new rule.
- Every tool is free and open source. Nothing paid.

## Capabilities

### Modified Capabilities

- `native-experience`: the requirement "Visual proof of interface changes".

## Impact

- Two test-only dependencies: swift-snapshot-testing (MIT) in the iOS test targets, Roborazzi (Apache 2.0) in the Android unit tests. The Accessibility Test Framework (Apache 2.0) comes with the AndroidX test libraries.
- No change to what a reader sees.
