---
name: ui-conformance
description: Prove a screen matches its design: tokens, computed style, structure, then a Playwright baseline. Use when you change UI or build from Figma.
risk_level: low
writes_files: true
requires_tools: [playwright]
metadata:
  stacks: [react-web, next-web, angular-web, expo-mobile, swift-ios, android-compose, gtk-desktop, winui-desktop, macos-desktop]
---

# ui-conformance

Answer one question: does the built screen match its design? A claim is not proof.
Run the layers in order. Fix the first layer that fails, then run it again.

## Inputs

1. Find the screen in `docs/designs/screens.json` (see `spec-flow`). An alias or a `SCR-id` gives the route, the Figma node and the stories.
2. Read the design through the Figma MCP: `get_design_context` and `get_variable_defs` on the node.
3. If the Figma MCP is not available, use the exports in `docs/designs` or the PNG that the user gives. Say what you lacked. Never guess a value.
4. Before you write a new component, look for one that fits. Use the Storybook MCP when the project has it. Else read the `*.stories.*` files and the component library.
5. Map each Figma component to a code component. Write a new one only when none fits.

## 1. Tokens against computed style

Read both sides as values. A screenshot cannot settle fonts, colors, backgrounds or copy.

1. Run the probes in `scripts/probe-design-values.js` against the running app with Playwright `browser_evaluate`.
2. Run the typography census first. It groups all visible text by family, weight, size, line height and color.
3. Compare family, weight, size, line height, color, background color, background image, radius and spacing with the Figma variables.
4. Quote the measured value against the expected one: `rgb(17,24,39) measured, expected #064e3b`. "Title matches" records nothing.
5. A Figma text-style name is not its content. A CSS Module class can beat a utility class of equal specificity by source order.
6. A gradient headline has `color: transparent`. Read `background-image` and the ancestors and `::before` layers.
7. Compare with the frame that the design shows for this viewport, not only with the type scale rule.

## 2. Structure

1. Compare order, nesting, alignment, constraints and responsive rules with the design.
2. Check each state: hover, focus, disabled, loading, empty, error.
3. Compare the copy character by character.
4. Atomic design on the web: copy `assets/eslint-boundaries.mjs` next to `eslint.config.mjs` and add it to the config. The lint then fails when a level imports a higher level.

## 3. Screenshot compare

1. Capture the screen at the viewport of the reference. Change the viewport, never scale the screenshot.
2. Compare the pair by eye and with a diff.
3. Classify each difference. A layout shift has hard edges. A color change fills a region evenly. Anti-aliasing is a one-pixel outline on glyphs.
4. A difference against a mockup may mean that the mockup is stale. Report the frame and ask the designer. Do not change the build to match a stale picture.
5. A comparative claim needs a control. Capture the matching screen on the same device in the same session. Say what the control rules out.

## 4. Playwright baseline

1. Use `toHaveScreenshot`. Add no image-diff dependency.
2. Keep references in `docs/designs/baselines/`. Keep captures in `test-results/`, which git ignores.
3. Capture 375, 768, 1024 and 1440 pixels wide, in each color scheme that the project ships.
4. Make the run deterministic. Details and a config example are in `references/playwright.md`.
5. Never overwrite a baseline to make a run pass. A tolerance that you chose to pass is a deleted test. Report the tolerance.
6. With no reference, capture all viewports, look at every image, commit them as the baseline, and write "First run. Baseline established. This run proves nothing."
7. Write the report to `docs/delivery/visual/<YYYY-MM-DD>-<slug>.md`: the reference, the run, a results table, the findings, the actions and the commands with their results.

## Proof rules

- A UI change touches a component, a stylesheet, a token, a layout or an asset that a page shows. It ships with a screenshot for each viewport.
- Two exceptions. Code behind a flag that nothing renders yet: say so. A pure refactor: byte-identical screenshots are the proof.
- If the project has no Playwright setup, write "no visual proof: project has no Playwright setup". Propose the viewport matrix.
- A class-name assertion is not proof. It still passes after the rule is deleted from the stylesheet.
- A reference belongs to one renderer. Record and compare it only there.
- When a reference fails after a merge, look at the reference, the new render and the diff. Record it again only when a change meant it.

## Native and desktop

1. Capture the screen on a real simulator or emulator. A preview is not proof: it uses preview data and skips the real theme and insets.
2. iOS: `xcrun simctl io booted screenshot <file>`. Pin one simulator model and one OS version. Run snapshots in an app-hosted test bundle.
3. Android: `adb exec-out screencap -p > <file>`. Compare on one OS, because macOS and Linux fonts differ.
4. Keep volatile parts, such as glass bars and clocks, out of the comparison.
5. Desktop stacks: add the source id `apple-macos`, `winui` or `gtk` to `upstream` in `.agents/compass.json`. Then run `ac sync`.

## Accessibility

1. Walk the keyboard path before you call a change done. Tab through everything that you changed.
2. The focus ring stays visible and unclipped. Enter or Space operates each control.
3. After you close a dialog, focus returns to the control that opened it. After you delete the focused element, focus moves to a sensible place, not to `body`.
4. Report the result in one line. An automated audit cannot see these faults.
5. Before a platform check gates touch-target size, add a test with a target that is too small. The check must fail on it.
6. iOS `performAccessibilityAudit()` passed targets under 44 pt. Measure each target against 44 x 44 pt.
7. Android Accessibility Test Framework checks nothing under Robolectric. Read the Compose semantics tree: touch bounds of 48 x 48 dp, a label on each clickable node, text contrast of 4.5 to 1.

Do not commit.
