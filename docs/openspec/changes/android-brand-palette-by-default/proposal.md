## Why

StoryArc has one accent colour, `brand.accent`, `oklch(58% 0.2304 295.4)`, a violet. An iOS
reader sees it. An Android reader does not: `AppSettings.Defaults.useDynamicColor` is `true`,
so `Theme.kt`'s dynamic branch dresses the chrome in the colours of whatever wallpaper the
device carries. The two platforms therefore ship as two different-looking apps out of the box,
and which one a reader meets is decided by their wallpaper rather than by StoryArc.

The owner asked for one brand colour on both platforms by default. Material You stays, because
it is a real Android affordance and some readers want it; it stops being the default.

## What Changes

- **BREAKING for an existing Android install.** A reader who never opened the Appearance
  settings has `useDynamicColor = true` stored, or no stored value at all. After this change a
  stored `true` keeps the wallpaper, because it is an answer the reader's own install already
  holds; only a fresh install, and a reset, take the new default.
- Android's `AppSettings.Defaults.useDynamicColor` becomes `false`.
- The Appearance row keeps its switch and its name. Its note stops saying "On by default".
- `native-experience`'s *Android dynamic colour* scenario is inverted: the scheme is StoryArc's
  palette by default, with a setting to take the wallpaper's colours instead.
- Nothing else moves. OLED Dark and Natural already win over dynamic colour, and the reasons
  they do are unchanged. The cover-derived accent is untouched. iOS is untouched: it has no
  dynamic colour to opt out of.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-experience`: the *Android dynamic colour* scenario states which scheme is the
  default. It currently names the wallpaper. It will name StoryArc's palette.

## Impact

- `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/AppSettings.kt` — the default.
- `apps/android/feature/settings/src/test/kotlin/app/storyarc/feature/settings/DynamicColourSettingTest.kt`
  — asserts the default, and quotes the scenario sentence in its own doc.
- `apps/android/feature/settings/src/main/res/values{,-fr,-de,-es}/strings.xml` —
  `appearance_dynamic_colour_note` says "On by default" in four languages.
- `docs/openspec/specs/native-experience/spec.md` — the scenario.
- Visual proof: the empty library and the Appearance settings row, light and dark, at the
  default and the largest text size, because this changes what every Android screen is coloured
  with. `AGENTS.md` section 6 allows no exception here: the frames differ.
- No code in `Theme.kt` changes. The branch that reads the flag already exists and already
  does the right thing with either value.
