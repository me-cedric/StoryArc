# Paper grain, Android pair, dark pair and refusals - 2026-10-09

Task 0.5 of `reader-theming-and-page-transitions`. The iOS light pair is in
`ios-paper-grain-2026-09-05/`. This set adds what that README listed as open: the Android pair,
the dark pair on both platforms, and one refusal frame per platform.

Each file is the middle slice (600 px high) of one full frame of the reflowable reader over
*The Long Field*, page only. A pair differs in one thing: Natural on or off. The numbers come
from `node scripts/grain-delta.mjs <on.png> <off.png>` run on the slices in this folder.

| Frame | What it shows |
| --- | --- |
| `ios-grain-on-band.png`, `ios-grain-off-band.png` | iOS, Paper page, Natural on and off |
| `ios-grain-on-quiet-band.png`, `ios-grain-off-quiet-band.png` | iOS, Quiet (dark) page, Natural on and off |
| `ios-grain-refused-band.png`, `ios-grain-refused-quiet-band.png` | iOS, Natural on, Reduce Transparency on |
| `android-grain-light-on-band.png`, `android-grain-light-off-band.png` | Android, light, Natural on and off |
| `android-grain-dark-on-band.png`, `android-grain-dark-off-band.png` | Android, dark with the Quiet page, Natural on and off |
| `android-grain-dark-refusal-band.png` | Android, Natural on, contrast level 1.0 |

## Numbers

Share of pixels the texture changed, and the mean signed change over the changed pixels
(R, G, B; negative is darker).

| Pair | Changed | R, G, B over changed pixels | Speckle run, median / 95th |
| --- | --- | --- | --- |
| iOS light | 63.2% | -1.70, -1.95, -2.09 | 2 px / 8 px |
| Android light | 50.8% | -1.85, -2.06, -2.31 | 2 px / 6 px |
| iOS dark | 86.4% | +2.39, +2.27, +2.08 | 5 px / 22 px |
| Android dark | 81.1% | +2.39, +2.24, +2.03 | 4 px / 17 px |
| iOS refused, light and dark | 0.0% | 0, 0, 0 | none |
| Android refused, dark | 0.0% | 0, 0, 0 | none |

## What the numbers say

- **Android matches iOS.** Both are warm. Blue moves 24% more than red in light (Android 2.31 over
  1.85, iOS 2.09 over 1.70). Both lighten a dark page with the same three values to within 0.05.
  Both specks are a few pixels wide. Android changes fewer pixels in light (51% against 63%). The
  Android cell is 1.5 device pixels on a 1344 px panel, and the iOS one is divided by its scale on
  a 1206 px panel, so a small gap is expected. It is not a different texture.
- **Dark is a larger part of the range.** On a dark page the grain changes 81% to 86% of the
  pixels, against 51% to 63% on a light page, and its sign flips: it lightens. The tint pair gives
  warm light specks on dark and dark brown ones on light.
- **Both refusals remove the grain completely.** The refusal frame equals its Natural-off twin
  to the pixel.
- The first paragraph of the judgement still stands as the 2026-09-05 README wrote it: grain at
  this strength is invisible in one frame and clear in a pair, and no bundled tile is needed.
  What nobody has done is look at a real panel.

## How they were taken

- iOS: `GrainWalkTests` through `node scripts/capture-ios.mjs --only GrainWalkTests --device
  <udid> --appearance light`, on the iPhone 17 simulator. The two refusal cases drive
  *Settings > Accessibility > Display & Text Size* with `setDisplaySwitch`, because `simctl ui`
  has no switch for Reduce Transparency. Every walk starts with `freshShelfSettings`, so a theme
  that an earlier walk chose does not carry over.
- Android: Pixel 9 Pro XL emulator, API 36, 1344 x 2992. Natural on and off from
  *Settings > Appearance*, the Quiet page from the theme sheet, and `cmd uimode night yes` for
  dark.
- **The Android refusal needs `contrast_level`, not `high_text_contrast_enabled`.**
  `adb shell settings put secure contrast_level 1.0`. On API 34 and later the app reads the
  contrast level (`HighContrast.kt` says why). Put it back with `contrast_level 0.0`.

## Left for a person

Look at Natural grain on a real phone in light and dark. It must look like paper and not like
noise, and it must vanish under Reduce Transparency and under high contrast.
