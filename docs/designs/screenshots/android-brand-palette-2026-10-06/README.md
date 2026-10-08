# Android wears the StoryArc palette by default, 2026-10-06

`brand.accent` is `oklch(58% 0.2304 295.4)`, one token for both platforms. It reached iOS and
not Android: `AppSettings.Defaults.useDynamicColor` was `true`, so Material You dressed the
chrome in the colours of whatever wallpaper the device carried, and which colour an Android
reader met was decided by their wallpaper rather than by StoryArc.

The default is now `false`. The switch did not move.

The device is the `Pixel_7_Pro` emulator, API 36. **Every frame is from a fresh install**
(`pm clear`), because an install that already holds an answer keeps it — `SettingsStore` reads
a stored record and only a fresh install and a reset read `Defaults`. A device that already had
StoryArc on it would photograph the old default and prove nothing.

| Frame | What it shows |
| --- | --- |
| `android-library.png` | The empty library, light, default text. The button, the Library pill and the overflow dots are the brand violet. |
| `android-library-dark.png` | The same, dark. |
| `android-appearance.png` | Settings › Appearance, light. *Take colours from the wallpaper* is off, and its note names what the switch does rather than what the default is. |
| `android-appearance-dark.png` | The same, dark. |

## The other half of the claim

*One accent on both platforms* needs both platforms in one place. The iOS frame is
`ios-empty-library.png` in
[`../choose-a-file-2026-10-05/`](../choose-a-file-2026-10-05/README.md), taken on the
`StoryArc-Sweep-Empty` simulator the day before. Put it beside `android-library.png`: same
screen, same accent, two platforms.

That README's own closing section explains why **its** Android frames are blue. They were taken
before this change, with Material You still on by default, and they are left as they were: they
are the proof of what the first-run button said, not of what colour the app is.

## What these frames do not cover

The wallpaper path itself. Nothing here photographs the switch turned **on**, so the frames
prove the new default and not that Material You still works when a reader asks for it.
`ReaderAppearanceTest` and `DynamicColourSettingTest` cover that as values, and `Theme.kt`'s
branch is unchanged, but no picture of it exists.
