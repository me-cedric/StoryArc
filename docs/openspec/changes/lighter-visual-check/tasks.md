## 1. Spec and rules

- [x] 1.1 Write this change: proposal, design, the `native-experience` delta and these tasks.
- [x] 1.2 Rewrite `AGENTS.md` section 6 to the new rule: the builder looks at its own screen; snapshot tests and accessibility checks; a device screenshot only where a snapshot cannot show the screen; downscale. Point `docs/design.md` section 11 at it.
- [ ] 1.3 `pnpm preview:proof` accepts a snapshot reference (`__Snapshots__/` on iOS, `src/test/snapshots/` on Android) as proof, with self-test cases for both.
- [x] 1.5 Mobile MCP in `.mcp.json`, pinned to 1.0.9, telemetry off.
- [ ] 1.4 `pnpm frames:shrink` downscales new frames with `sips` to 1200 px on the long side.

## 2. Android

- [ ] 2.1 Add Roborazzi to the version catalogue and to the Compose feature modules' unit tests, with `@GraphicsMode(NATIVE)`, references in `src/test/snapshots/`, and `pnpm snap:android` and `pnpm snap:android:record`.
- [ ] 2.2 Snapshot tests for the screen catalogue, light and dark.
- [ ] 2.3 Accessibility Test Framework checks (`enableAccessibilityChecks()`) over the screen catalogue. A test proves that a 40 dp target fails.

## 3. iOS

- [ ] 3.1 Add swift-snapshot-testing to the test targets that hold views, with references in `__Snapshots__/`, and `pnpm snap:ios` and `pnpm snap:ios:record`.
- [ ] 3.2 Snapshot tests for the screen catalogue, light and dark.
- [ ] 3.3 The accessibility audit (`AuditWalk`, hit region and contrast included) reaches every screen of the catalogue that a UI test can reach. A test proves that a 30 pt target fails.

## 4. Catalogue and CI

- [ ] 4.1 `docs/designs/screen-catalogue.md` lists the screens and states, with the test that draws each on each platform.
- [ ] 4.2 The snapshot verifications and the accessibility checks run in `pnpm test:ios`, `pnpm test:android` and CI.
