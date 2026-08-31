# Android's search page, before section 2's second half

Android's search page as it stood after `quiet-shell-and-search` sections 1 and 2's *bar*:
a bar at the top, the navigation below, and **nothing in between**. The source said so where
the space was left, and the previous batch's README said so too — "the Android search page has
nothing under its bar yet".

**Why `e` and not `d`.** `…-31d/` was taken while this work was in flight, by the
`quiet-reader` batch on `main`, for three iOS reader shots. Two batches under one name would
have left one folder holding two subjects and two READMEs each describing half of it, so this
pair moved along a letter rather than merging into it.

## Device and setup

`storyarc-api36`, started with `-gpu host`. **Not `storyarc-j6`**: another emulator was already
running that AVD when this work started, and the emulator refuses a second instance of one AVD
without `-read-only`. Installing a build onto a device somebody else is using would have
replaced the app under them, so a second AVD was booted instead. Same app, same 320 × 640 dp at
160 dpi, and every shot in both folders comes from it.

The library is seven CBZ files generated for these captures and pushed into the app's own
external files directory, which the launch scan walks when no folder has been picked. They are
**not** the committed corpus and are not committed anywhere: the corpus in
`packages/test-fixtures/` holds format edge cases — a truncated archive, a data descriptor, a
password-protected file — and none of it is a series with a finished volume and an unread one
after it, which is exactly what *Next in a series you have read* needs to have something to
say. One volume was marked read from the publication page and one standalone was read two pages
into, both by hand on the device, to produce the two reading states the page draws.

```bash
pnpm build:android
adb -s emulator-5556 install -r -t apps/android/app/build/outputs/apk/debug/app-debug.apk
pnpm capture:android Search --out …/android-search-at-rest-light.png
pnpm capture:android Search --out …/android-search-at-rest-dark.png  --dark
pnpm capture:android Search --out …/android-search-at-rest-scale2-light.png --font-scale 2.0
```

`pnpm capture:android` gained a `Search` route in this change — the route table had none,
because until section 1 there was no search destination to walk to. The previous batch took its
two search shots by hand with `adb input tap` and said adding a route was worth doing.

## What is in them

| Shot | What is in it |
| --- | --- |
| `android-search-at-rest-light` | The page with a seeded library behind it and nothing on it. The bar works, the navigation works, and the body is empty — which is the whole defect. |
| `android-search-at-rest-dark` | The same, dark, so the "after" pair is not proving a theme change by accident. |
| `android-search-at-rest-scale2-light` | The same at the largest accessibility text size. Empty at every size. |
| `android-search-scope-chips-squeezed-scale2` | **Not the same "before".** This one is the page *with* the suggestions built and the scope chips still in a plain `Row`, which is the state that revealed a defect nobody had seen: at `font_scale 2.0` in a 320 dp window, *On this device* is drawn over four lines with a lone "e" on the last. It was taken by reverting the one-line layout change, rebuilding, capturing, and restoring — because a fix with no picture of what it fixed is a claim. |

## What these do not show

The **expanded** search bar, which is a second surface reached by tapping the field and which
this change does not touch. Recent searches, the clear affordance, the results and the
could-not-answer line all live there and were photographed in
[`after-2026-08-31c/`](../after-2026-08-31c/README.md).

Neither folder shows iOS. Its half of section 2 landed in the previous batch and nothing here
changes it.
