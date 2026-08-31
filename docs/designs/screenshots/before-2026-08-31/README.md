# The "before" set for 2026-08-31

Seven captures, each the state of a screen on the build immediately preceding the fix that
`after-2026-08-31/` shows. Same devices, same library, same appearance and text size — the
only variable is the change. That README says what each pair proves.

| Capture | The defect it holds |
| --- | --- |
| `ios-shelf-caption-{default-light,ax5-light,ax5-dark}` | Every cover printing its title twice, and three truncated columns at the largest text size. |
| `android-shelf-caption-default-light` | The same duplicated caption on Android. **This file is a copy of `after-2026-08-30/android-shelf-no-source-line-light.png`** — the defect was visible in a capture committed the day before and nobody had read it that way. |
| `ios-detail-overflow-and-empty-accessory-dark` | Two at once: an empty glass capsule above the tab bar with no read-aloud session, and an overflow button half again as tall as the *Read* button beside it. |
| `ios-notice-band-dark` | The scan summary as a full-bleed band across the window — the only rectangle in an app whose every other piece of chrome is a floating capsule. |
| `ios-fixed-layout-refused-dark` | *"This comic has no pages StoryArc can show."* on a publication the shelf labels EPUB. |
