# Android — the segmented buttons Material retired, 2026-09-01

Sixteen pictures: two replaced controls × before/after × light/dark × default and largest
accessibility text size. Taken on the `storyarc-j6` emulator (API 36, 1080×2400), started
with `-gpu host` — on software GL the app looks broken and is not.

**The selection treatment is the whole visible change**, so every capture has an option
selected. A picture of an unselected group would prove nothing.

## What they compare

Both builds are `assembleDebug` from the same commit's tree, differing only by the two call
sites. The `before` build has `apps/android/feature/reader/.../PdfTextSheet.kt` and
`apps/android/feature/epubreader/.../ThemeAxesScreen.kt` reverted to their pre-change
content and nothing else. Verified rather than assumed: the `before` APK's dex holds 8
references to `ConnectedButtonGroupKt` — the component itself, which is compiled into
`:core:designsystem` either way — and the `after` APK holds 10, the two extra being the call
sites.

| Picture | Control | Build |
| --- | --- | --- |
| `before-pdf-<appearance>-<size>.png` | The PDF sheet's Search / Highlights tabs | `SingleChoiceSegmentedButtonRow` |
| `after-pdf-<appearance>-<size>.png` | The same two tabs | `ConnectedButtonGroup` |
| `before-align-<appearance>-<size>.png` | The theme axes' Publisher / Left / Justified picker | `SingleChoiceSegmentedButtonRow` |
| `after-align-<appearance>-<size>.png` | The same three options | `ConnectedButtonGroup` |

`<appearance>` is `light` or `dark`; `<size>` is `default` (font_scale 1.0) or `largest`
(font_scale 2.0). The device was put back to 1.0 and light afterwards.

## What they show

**The retired treatment**: one outlined pill split by shared borders, the chosen option
filled tonally and marked with a **check icon**. That is the baseline segmented button, and
Material 3 Expressive says it "is no longer recommended".

**The replacement**: separate shapes with `ButtonGroupDefaults.ConnectedSpaceBetween`
between them, no check icon, and a shape that is different per position — the leading option
rounded on its outer edge and squared on its inner one, the interior option squared on both,
the trailing option the mirror of the leading one. The chosen option takes
`ButtonGroupDefaults.connectedButtonCheckedShape`, which is the round-to-square change the
Expressive guidance actually specifies. Nothing here paints a container colour of its own;
the fill is `ToggleButton`'s Material default.

**`after-align-<appearance>-largest.png` is the one worth looking at twice.** At twice the
system text size the labels wrap — *Publish/er*, *Justifie/d* — and the buttons grow taller
rather than truncating. `design.md` rule 3 asks that the screen survive the largest
accessibility size, and Material forbids a truncated label; a wrapped one is the only
remaining answer, so the component passes no `maxLines`. Its `before` twin wraps the same
way, so this is a preserved property rather than a new one.

## How they were taken

`scripts/capture-android.mjs` could not take these: neither control is a listed route in
`scripts/android-routes.mjs`, and the PDF text sheet and the theme axes screen are both four
or five taps behind a reader. The captures were driven by a throwaway script over that
module's own exported `navigator`, `centre` and `sleep` — nothing under `scripts/` was
modified — walking:

```
Library → Field Notes (PDF) → Read → Menu → Search
Library → The Long Field (EPUB) → Read → Menu → Appearance → Customise → Text alignment
```

Two notes for whoever takes these next.

**The theme axes screen needs a preset that turns publisher styles off.** `AlignmentControl`
is drawn only when the preset does not keep publisher styles; under `Original` the whole
control is replaced by `PublisherStylesNotice`. Picking *Paper* once on level one persists,
so the walk above needs it only on a fresh install.

**"uiautomator found it" is not "you can photograph it".** uiautomator reports nodes just
outside a scrolling container, so the first attempt at the alignment captures stopped with
the picker below the fold and photographed the spacing sliders instead. The walk now scrolls
until the node's *bounds* sit inside the middle 60% of the screen.

**The machine was running four agents and it showed.** `uiautomator dump` answered
`ERROR: null root node returned by UiTestAutomationBridge` on most attempts — the retry loop
in `android-routes.mjs` absorbs it — SystemUI reported "isn't responding" once, and the
emulator went `offline` and reloaded its boot snapshot at one point, silently discarding an
installed APK. That last one is worth knowing: a capture taken straight after an install
that reported `Success` was of somebody else's build, and only a dex check found it.
