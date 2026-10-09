# The cover-lookup setting, 2026-10-06

Topic evidence for `cover-for-every-publication`, sections 3 to 5. Keep these until that
change archives.

## What is here

| Frame | Condition |
| --- | --- |
| `ios-settings-privacy.png` | iPhone 17 Pro, light, default text |
| `ios-settings-privacy-dark.png` | iPhone 17 Pro, dark, default text |
| `android-settings-privacy.png`, `-dark.png` | Android emulator `storyarc-store`, 411x914 dp, default text, lookup off |
| `android-settings-privacy-on.png`, `-on-dark.png` | The same screen with the lookup switched on |

The iOS frames were taken by `node scripts/capture-ios.mjs --only
SweepSettingsTests/testCaptureSettingsPrivacy`, which walks to the screen and proves the
navigation title before the shutter.

## What they show

The cover lookup, on the Privacy screen, **off**. The row names all three catalogues —
Open Library, Cover Art Archive, Audnexus — and the paragraph under it states that one
identifier and nothing else leaves the device. That is `cover-art`'s requirement that the
app "name the provider it would ask" before a reader turns the lookup on.

## Android, and what is still owed

**Android frame, taken 2026-10-09.** The Privacy screen on the `storyarc-store` emulator shows the row "Look up missing covers" with its provider list ("Asks: Open Library, Cover Art Archive, Audnexus, AniList, MangaUpdates") and the paragraph under it, off and on. The route is `Settings > Privacy` and `Settings > Privacy > cover lookup on`. Task 3.1 and the Android half of 3.6 need no more frames.

**The candidate chooser, the web hand-off and the write-back confirmation.** The edit menu now reaches them. Android frames of the menu and of the empty chooser are in `../frames-android-2026-10-09/` (`cover-menu-lookup-on*`, `cover-chooser-no-candidate*`, `cover-web-handoff-chrome-first-run.png`). The chooser with pictures and the Custom Tab on the image search are still owed, and the iOS chooser is not photographed.
