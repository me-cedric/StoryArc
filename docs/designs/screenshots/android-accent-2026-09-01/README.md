# The accent reaches the four control kinds — Android, 2026-09-01

`brand-identity-and-app-icons` §1.7, Android half. The review named **tab bars, chips, sliders
and progress ticks** as surfaces the accent never reached.

**Every picture here has dynamic colour OFF**, which is the whole point: that is the path
design.md identifies as the one to fix, and the only path the OLED Dark and Natural
appearances have. Material You is untouched and still the default.

## What the pictures show

| File | Condition | What to look at |
| --- | --- | --- |
| `before-light-selected.png` | light, chip selected | The pair that matters most. The selected *On this device* chip is **pale lavender with dark text**, and the navigation bar's selected pill is the same pale lavender. Neither is a StoryArc colour. |
| `after-light-selected.png` | light, chip selected | The same two, now **muted violet with a white label and a white icon**. |
| `before-dark-at-rest.png` | dark, chip at rest | The navigation pill is Material's grey-lavender `#4A4458`. |
| `after-dark-selected.png` | dark, chip selected | The pill is violet; so is the chip. |
| `before-light-at-rest.png` | light, chip at rest | The same screen with nothing selected, so the chip's outline can be compared too. |
| `before-dark-downloads.png` | dark, Downloads | The same defect on a second destination — this is the navigation bar, so it was on every screen in the app. |
| `before-light-home-buttons.png` | light, Home, empty | The control for the `TextButton` question below. |

The strictly comparable pairs are **light selected** (`before-light-selected` →
`after-light-selected`), which shows the chip and the tab bar, and **dark**
(`before-dark-at-rest` → `after-dark-selected`), which shows the tab bar.

## What was actually wrong

One role, not four surfaces. `darkColorScheme()` and `lightColorScheme()` fill every role the
caller omits from **Material's baseline palette**, which is lavender, and the brand schemes set
eleven roles and omitted the rest. Measured off
`MaterialExpressiveTheme(colorScheme = brandDarkScheme())`, `secondaryContainer` was
`#4A4458` and was read by:

- a selected `FilterChip`'s container — **chips**
- `NavigationBar`'s selected indicator — **tab bars**
- `Slider`'s inactive track — **sliders**
- the linear and circular progress indicators' tracks — **progress ticks**

The four control kinds the review named are four faces of one unset role. The accent already
reached the *active* half of a slider and a progress bar through `primary`; what stayed
Material's was everything at rest and everything selected.

`AccentReachesTheControlsTest` is that measurement, kept — it reads the real Material defaults
rather than restating them, so a material3 upgrade that moves one of these fails the build.

## The one thing design.md had not quite right

design.md answers the review's "Android runs blue/purple" with "the purple was the wallpaper".
That is true of the screenshot the reviewer was looking at and it is not the whole account:
with dynamic colour **off** the app still drew Material's own lavender, from the baseline
rather than from a wallpaper. Two independent causes, and only the second was this project's
to fix. `before-light-selected.png` is that second cause photographed with the wallpaper taken
out of the picture.

## The `TextButton` answer, and why no `TextButton` was touched

Another agent reported that the failure notice's two control labels "render in Material's
default `primary` (blue on this emulator's dynamic colour), not the StoryArc accent", and that
this matches every other `TextButton` in the app.

**The brand scheme's `primary` already is the accent, and every `TextButton` follows it.** In
`before-light-home-buttons.png` — dynamic colour off, no code change — *Add a folder* is
violet and *Open a comic* is a violet filled button with a white label. The blue was the
reader's wallpaper doing exactly what `native-experience` requires.

So the answer is scheme-level and the same everywhere: **nothing tints a `TextButton` by
hand.** Hard-coding `palette.accent` at those two sites would override the reader's Material
You choice on a chrome control, which the chrome/content rule on `LocalStoryArcPalette`
forbids, and would answer a scheme question one call site at a time.

## What is *not* proved by a picture here

- **The slider and the progress track.** Both read the same `secondaryContainer` the pill and
  the chip do — asserted in `AccentReachesTheControlsTest` against the real Material defaults —
  but neither is photographed. No download was in progress on this device, and the
  `Comic reader > chrome` route reproducibly captures after the reader's chrome has auto-hidden
  (two attempts, both a bare page: the chrome recedes faster than the harness's settle).
- **The navigation bar's selected *label*** is still `secondary`, the brand's pink. That is a
  brand token rather than a leak, and Material's own pairing, so it was left alone: the pill
  and the icon were the parts drawing Material's colour.
- **Natural.** Its schemes have the identical hole, worse — Material's lavender containers
  beside a clay accent. Not fixed here: closing it means choosing a clay-family value with a
  gated contrast pairing, which belongs to whoever owns that theme.

## How the device was set up, and how the build was verified

Dynamic colour was turned off by writing the app's own settings file as the app user, then
read back to confirm:

```
{"useDynamicColor":false}   in /data/data/app.storyarc.debug/shared_prefs/app.storyarc.settings.xml
```

**The emulator is shared, and it bit.** An `after` capture taken at 19:34 showed the *old*
build: the sort chip read `Title` instead of `Sort: Title` and both surfaces were still
lavender. `dumpsys` gave `lastUpdateTime=19:32:19` against an install of mine at `19:31:12`,
and a different `codePath` — **another agent had installed their build over mine**, from
another worktree, between the install and the shutter. Not one of the two documented traps
(a discarded install, a broken `/sdcard` mount); a third one.

So the `after` captures are sandwiched between two checks of the *contents* of the installed
APK, not just its timestamp: `base.apk` was read back off the device and searched for the
German string `Sortierung: `, which exists only in this branch, **before** the first capture
and **after** the last. Both found it, with the same `codePath` either side. That capture at
19:34 was discarded and retaken.

`storyarc-j6`, API 36, started with `-gpu host`.
