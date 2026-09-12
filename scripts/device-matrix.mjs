#!/usr/bin/env node
/**
 * The project's device matrix, written down once.
 *
 * `AGENTS.md` section 6 and `native-experience`'s "Both appearances" scenario both ask for a
 * changed screen in light and dark, at the default and the largest text size. Until now that
 * sentence was the only copy of the matrix, so every sweep was taken from memory and what a
 * change actually photographed varied with whoever took it. `capture-android.mjs` and
 * `capture-ios.mjs` loop over this table in `--matrix` mode, and `capture-compare.mjs` reads
 * the ignored band from it, so a condition is added here and nowhere else.
 *
 * Usage:
 *   node scripts/device-matrix.mjs       print the table
 */
import { pathToFileURL } from 'node:url'

/**
 * The share of each frame, from the top down, that a comparison ignores.
 *
 * **This is the status bar, and it is ignored because the clock moves.** Measured on
 * 2026-09-12 over the 1004 PNGs under `docs/designs/screenshots/`: of 108 pairs of frames
 * filed under the same name, three differ in nothing but rows 79 to 116, columns 157 to 287,
 * of a 1206x2622 iOS frame. That rectangle is the simulator's clock. It accounts for 0.067%
 * to 0.080% of those frames, and it is the entire difference between two photographs of one
 * screen taken on different days.
 *
 * Row 116 is 4.43% of 2622. Six percent is 158 rows on that frame, which clears the lowest
 * measured varying row by 42 rows, and 144 rows on the 1080x2400 Android frame.
 *
 * **What it costs, said plainly.** Six percent of an Android frame is about 52 dp, and an
 * Android status bar is 24 dp, so the band also swallows the top half of the app bar: a
 * regression in the height of the app bar's top padding would not be seen. The corpus holds
 * no Android pair differing only in its status bar, so the Android band is the iOS figure
 * applied across rather than a measurement of its own. `capture-compare.mjs` prints the
 * topmost differing row of every frame it reports, which is the number that would say so.
 */
export const IGNORE_TOP_PERCENT = 6

/**
 * The largest differing fraction a comparison forgives, as a percentage of compared pixels.
 *
 * Measured the same day and over the same 108 pairs, with the band above removed: four pairs
 * are pixel-identical, and the smallest real change is 731 pixels of 2,436,480 — 0.030%.
 * Nothing lies between. So an unchanged screen produces exactly zero differing pixels, and
 * the smallest change anybody has filed produces 0.030%.
 *
 * 0.01% sits a third of the way to that smallest real change and is not zero, so a handful
 * of stray pixels does not fail a sweep: 297 pixels on a 1206x2622 iOS frame, 243 on a
 * 1080x2400 Android one. A threshold of zero would be unusable the first time a device
 * rendered one edge differently; a threshold of 0.1% would have forgiven a change this
 * project actually made.
 */
export const THRESHOLD_PERCENT = 0.01

/**
 * Every condition a sweep photographs, per platform.
 *
 * `suffix` is appended to a frame's name, so a light run and a dark run of one walk cannot
 * overwrite each other. The default condition carries no suffix, which is the convention
 * `capture-ios.mjs` already writes and the committed Android frames already use.
 */
export const MATRIX = {
  ios: {
    /** Named to `capture-ios.mjs --device`. A udid works too. */
    device: 'StoryArc-iPhone17Pro',
    /** Measured 2026-09-12: 435 of the 1004 committed frames are this size, more than any other. */
    frame: '1206x2622',
    /**
     * **The text size axis is missing here on purpose, and it is not missing from the sweep.**
     * The app stores its settings as one JSON blob under a single key, so there is no launch
     * argument for the theme and the simulator's appearance is the only lever — which is why
     * `--appearance` exists. Text size is the other way round: `sweepLaunch(contentSize:)`
     * sets it inside the test process, and the walks that use it are separate cases ending in
     * `-ax5`. Measured 2026-09-12: 38 such frame names across `apps/ios/UITests`, written from
     * 50 call sites. So a sweep at largest text is run by the walks and not by this table, and
     * a condition added here would photograph the same frames twice under two names.
     */
    conditions: [
      { appearance: 'light', textSize: 'default', suffix: '' },
      { appearance: 'dark', textSize: 'default', suffix: '-dark' },
    ],
  },
  android: {
    /**
     * Whatever is attached. `capture-android.mjs` passes no `-s` and lets `adb` read
     * `ANDROID_SERIAL`, so naming the device is the caller's business.
     */
    device: process.env.ANDROID_SERIAL ?? 'the attached device',
    /** Measured 2026-09-12: 393 of the 1004 committed frames are this size, more than any other. */
    frame: '1080x2400',
    /**
     * 2.0 is the largest font scale Android's accessibility settings offer, and the figure
     * `AGENTS.md` section 6 already uses in its own example.
     */
    conditions: [
      { appearance: 'light', fontScale: '1.0', suffix: '' },
      { appearance: 'dark', fontScale: '1.0', suffix: '-dark' },
      { appearance: 'light', fontScale: '2.0', suffix: '-largest' },
      { appearance: 'dark', fontScale: '2.0', suffix: '-dark-largest' },
    ],
  },
}

/** A route or a walk name as a file name: lower case, one hyphen between words. */
export const slug = (name) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')

/** One condition as a sentence, for a log line. */
export const describe = (condition) =>
  [condition.appearance, condition.fontScale ? `font scale ${condition.fontScale}` : null, condition.textSize]
    .filter(Boolean)
    .join(', ')

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  for (const [platform, entry] of Object.entries(MATRIX)) {
    console.log(`${platform}: ${entry.device}, frames ${entry.frame}`)
    for (const condition of entry.conditions) {
      console.log(`  ${describe(condition)}  ->  <name>${condition.suffix}.png`)
    }
  }
  console.log(`\nA comparison ignores the top ${IGNORE_TOP_PERCENT}% of a frame`)
  console.log(`and fails above ${THRESHOLD_PERCENT}% of the remaining pixels.`)
}
