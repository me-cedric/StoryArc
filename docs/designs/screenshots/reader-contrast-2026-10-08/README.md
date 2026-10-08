# Reader chrome and theme sheet under Reduce Transparency and high contrast - 2026-10-09

Task 7.6 of `reader-theming-and-page-transitions`. Each pair has the setting off (`standard`)
and on (`reduced` on iOS, `contrast` on Android), with the same book and the same page.

| Frame | What it shows |
| --- | --- |
| `ios-chrome-standard-light.png`, `ios-chrome-reduced-light.png` | The two round reader buttons, light |
| `ios-chrome-standard-dark.png`, `ios-chrome-reduced-dark.png` | The same, dark |
| `ios-theme-sheet-standard-light.png`, `ios-theme-sheet-reduced-light.png` | The theme sheet over the page, light |
| `ios-theme-sheet-standard-dark.png`, `ios-theme-sheet-reduced-dark.png` | The theme sheet over the page, dark |
| `android-reader-chrome-standard-light.png`, `android-reader-chrome-contrast-light.png` | The capsule with close and menu, light |
| `android-reader-chrome-standard-dark.png`, `android-reader-chrome-contrast-dark.png` | The same, dark |
| `android-theme-sheet-standard-light.png`, `android-theme-sheet-contrast-light.png` | The theme sheet, light |
| `android-theme-sheet-standard-dark.png`, `android-theme-sheet-contrast-dark.png` | The theme sheet, dark |

## What the frames show

- **iOS, Reduce Transparency on.** The glass sheet becomes an opaque fill. In the standard frame
  the page text shows blurred through the sheet. In the reduced frame it does not. In light the round
  buttons gain a clear border. In dark they turn into solid dark discs with a white glyph, where
  the standard frame has pale glass pills. The chrome follows the appearance, not the page, so a
  dark disc sits on a cream page.
- **Android, contrast level 1.0.** The dark translucent capsule over the text becomes an opaque
  pill with a border (`ReaderChromeColours.kt`). Over body text this is the clearest change of
  the set.
- The Android theme sheet changes little, because its surface is already opaque. Its borders
  are stronger.

## Increase Contrast audit

`AccessibilityAuditTests.testPublicationPagePassesTheAudit` on the iPhone 17 simulator, with
`xcrun simctl ui <udid> increase_contrast enabled`: the audit reports 6 issues and fails none.
With the setting off it reports 7. Both lists hold the same families: a hit area of 18 pt on
*Find a cover on the web*, and contrast on *Change cover*, *Find a cover on the web*, the
primary button and *Read aloud by Samantha*. The audit runs from the cover filter in
`AuditWalk.swift`, so that filter reached the publication page with the setting on. Increase
Contrast removed one finding (the caption under the cover). It added none.

## How they were taken

- iOS: `ReduceTransparencyWalkTests` through `scripts/capture-ios.mjs --appearance light|dark`.
  `setDisplaySwitch` turns the switch on in the Settings app and a teardown block turns it off.
- Android: emulator API 36. `adb shell settings put secure contrast_level 1.0`, and back to
  `0.0`. `high_text_contrast_enabled` does nothing on API 34 and later.

## Left for a person

Drive the theme sheet with VoiceOver and with TalkBack for five minutes each. Every control
must have a clear name and a clear value. Speech cannot be proved on a simulator or an emulator.
The emulator can run TalkBack. Nobody has listened.
