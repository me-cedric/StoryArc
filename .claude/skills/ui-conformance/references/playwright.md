# Playwright baseline

Read this file at layer 4 of `ui-conformance`.

## Determinism

A check that fails at random gets ignored. Fix all six causes before you trust a diff.

1. Freeze motion. Set `animations: 'disabled'`. Add a stylesheet with `transition: none` and `animation: none` for `*`.
2. Wait for fonts. Await `document.fonts.ready` before the capture.
3. Wait for a ready signal. Await a test id that the screen sets when it is ready. Never wait a fixed time.
4. Stub changing data: dates, random ids, avatars, live counters. Or pass them in `mask`.
5. Pin the scale. Set `deviceScaleFactor: 1`.
6. Pin the browser. Run one browser project. Pin the Playwright version in `package.json`.

## Tolerance

Start at `maxDiffPixelRatio: 0.01`. Lower it to `0.002` for a stable screen.
Raise it only for a measured reason, and write the reason in the report.

## Spec example

```ts
import { test, expect } from '@playwright/test'

for (const width of [375, 768, 1024, 1440]) {
  test(`dashboard at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await page.goto('/dashboard')
    await page.getByTestId('dashboard-ready').waitFor()
    await page.evaluate(() => document.fonts.ready)
    await expect(page).toHaveScreenshot(`dashboard-${width}-light.png`, {
      fullPage: true,
      mask: [page.getByTestId('last-updated'), page.locator('img.avatar')],
    })
  })
}
```

## Config example

```ts
import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: 'e2e/visual',
  outputDir: 'test-results/visual',
  snapshotPathTemplate: 'docs/designs/baselines/{arg}{ext}',
  expect: { toHaveScreenshot: { maxDiffPixelRatio: 0.01, animations: 'disabled' } },
  use: { deviceScaleFactor: 1, colorScheme: 'light', timezoneId: 'UTC', locale: 'en-GB' },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
})
```

Add a second project with `colorScheme: 'dark'` when the project ships two schemes.

## Rules

- Never compare a capture at one viewport with a reference at another.
- Never commit a capture as a reference before a person looks at it.
- Add `test-results/` to `.gitignore` first. A run that writes captures into the reference directory makes a new baseline each time.
- Name a reference with its source and width, for example `dashboard-1440-light.png`.
- A reference with no known width is a lead, not a baseline.
