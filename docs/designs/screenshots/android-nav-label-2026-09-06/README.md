# The navigation bar's selected label — Android, 2026-09-06

Five frames from `storyarc-j6` (1080 × 2400, 411 × 914 dp, `-gpu host`), taken with
`scripts/capture-android.mjs` on the `Library` route. The 2026-09-05 design review's finding 6:
*the Android nav bar wears two brand colours at once*.

| Frame | What it shows |
| --- | --- |
| `android-nav-label-before.png` | Before, light: the selected *Library* label is the pink pole (`secondaryStrong`) over the violet pill (`accentMuted`) |
| `android-nav-label-before-dark.png` | Before, dark: the same two colours on one control state |
| `android-nav-label.png` | After, light: the label follows the accent, the pill is unchanged |
| `android-nav-label-dark.png` | After, dark |
| `android-nav-label-dynamic.png` | After, Material You on: label, pill and every other accented control take the wallpaper's own colour together |

## What was wrong, and where the fix went

Material reads `secondary` for a selected label drawn under the indicator and
`secondaryContainer` for the indicator itself. On the brand schemes those two roles are the two
poles of the identity on purpose — `design.md` §2 gives the pink to links and chips and the
violet family to tab bars — so a selected destination was the pink pole's name over the violet
pole's pill. `native-experience`'s *Chrome accent* says the chrome's accent "is a single colour".

The label now follows `primary`, which on every brand scheme is `brand/accent`, at the one
call site that draws the control — `accentedItemColours` in
`core/designsystem/navigation/AdaptiveNavigation.kt`. Nothing else moves: the pill keeps the
container pair, and the schemes' `secondary` is untouched because many Material token families
read it. `AccentReachesTheControlsTest` asks the helper what it resolves under each brand scheme;
`AdaptiveNavigationTest` asks that the bar and the rail are both given the answer.

**Followed on the dynamic-colour path too.** Material's default there is the wallpaper's
`secondary`, a different tone from the wallpaper's `primary` every other accented control on the
screen draws. The rule is one accent per control state, so the label reads `primary` whichever
scheme supplied it — the last frame is that.

## How to retake them

```bash
node scripts/capture-android.mjs Library --out docs/designs/screenshots/android-nav-label-2026-09-06/android-nav-label.png
node scripts/capture-android.mjs Library --out docs/designs/screenshots/android-nav-label-2026-09-06/android-nav-label-dark.png --dark
```

The *before* pair needs the parent of the fix installed; Material You is turned off in the
app's own Appearance settings for the four brand frames and on for the last.
