A ticked box here means: the code exists, a test that fails without it landed, and the frames
this change needs exist. A tick does **not** mean a person watched it on a device.

## 1. The default

- [ ] 1.1 **`AppSettings.Defaults.useDynamicColor` becomes `false`** (android). One value in
  `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/AppSettings.kt:100`. Nothing
  in `Theme.kt` moves: its `useDynamicColor && SDK >= S` branch already reads the flag and
  already falls through to `brandLightScheme()` and `brandDarkScheme()`.
- [ ] 1.2 **`DynamicColourSettingTest` asserts the new default** (android). The test named
  *the wallpaper dresses the chrome until a reader says otherwise* asserts
  `assertTrue(AppSettings.Defaults.useDynamicColor)` and has to become its opposite, under a
  name that says what is now true. Its doc quotes the old scenario sentence; quote the new one.
  The second test, *turning it off changes nothing else, and a reset undoes only it*, inverts
  with it: the opted state is now `useDynamicColor = true`.
- [ ] 1.3 **A test proves an existing install keeps its own answer** (android). A stored record
  carrying `useDynamicColor = true` still reads `true` after the default moves. This is the
  clause in the scenario that nothing asserts today, and it is the one a reader would feel.

## 2. The words

- [ ] 2.1 **`appearance_dynamic_colour_note` stops saying "On by default"** (android). The
  sentence becomes one that names what the switch does rather than what the default is, in
  `values`, `values-fr`, `values-de` and `values-es`. `pnpm lint` fails on a locale left behind.
- [ ] 2.2 **Check the two sibling notes still read true** (android).
  `appearance_dynamic_colour_oled_note` and `appearance_dynamic_colour_natural_note` explain why
  the switch is disabled under OLED Dark and Natural. Both say the theme "already uses
  StoryArc's palette", which stays true, but read them against the new default before leaving
  them alone.

## 3. Proof

- [ ] 3.1 **Frames of the empty library, Android, from a fresh install** (android). Light and
  dark, at the default and the largest text size, into
  `docs/designs/screenshots/android-brand-palette-<yyyy-mm-dd>/`. A fresh install, because a
  device that already has StoryArc keeps its stored answer and would photograph the old default.
- [ ] 3.2 **A frame of the Appearance settings row** (android), showing the switch off and its
  new note, in light and dark.
- [ ] 3.3 **The README beside those frames names the iOS frame to compare against**, so the
  claim *one accent on both platforms* has both halves in one place. `ios-empty-library.png`
  in `docs/designs/screenshots/choose-a-file-2026-10-05/` is that frame.
