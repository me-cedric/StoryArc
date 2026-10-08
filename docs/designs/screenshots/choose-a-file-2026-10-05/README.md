# The first-run button stops calling every publication a comic, 2026-10-05

The button read *Open a comic*. StoryArc reads comics, ebooks, PDFs and audiobooks, and the
picker behind the button accepts any file (`arrayOf("*/*")`), so the label named neither what
the app holds nor what the button does. It now reads **Choose a file**.

*Choose*, not *Open*: the `Add books` menu already carries an `Open a file` row wired to this
same action, and `navigation-shell` requires that menu to keep all five ways in. Two controls
reading *Open a file* would be one label for a screen reader to tell apart.

The iOS device is the `StoryArc-Sweep-Empty` simulator, iPhone 17 Pro, iOS 27.0. The Android
device is the `Pixel_7_Pro` emulator, API 36, on a fresh install (`pm clear`).

| Frame | What it shows |
| --- | --- |
| `android-library.png` | The empty library, light, default text. The button reads *Choose a file*, and the sentence above it agrees. |
| `android-library-dark.png` | The same, dark. |
| `ios-empty-library.png` | The empty library, light, default text. |
| `ios-empty-library-dark.png` | The same, dark. |
| `ios-empty-search.png` | The search page at rest, which draws the same button from `SearchAtRest`. |
| `ios-empty-search-dark.png` | The same, dark. |

## Why the Android button is blue and the iOS one is violet

They are the same token. `brand.accent` is `oklch(58% 0.2304 295.4)`, one value on both
platforms. The Android frames are blue because **Material You is on by default**
(`AppSettings.Defaults.useDynamicColor = true`), so `Theme.kt`'s dynamic branch takes the
emulator wallpaper's palette instead of `brandLightScheme()`. `native-experience` asks for
exactly that: the scheme "derives from the user's wallpaper by default, with a setting to use
the StoryArc palette instead".

Turning that setting off was photographed during this pass and renders StoryArc's violet on
Android -- the Library pill, `Add books` and the overflow dots all take it. That frame is not
committed here, because it is not what a reader sees by default and this folder is proof of
the default.

## What these frames do not cover

`LibraryAway` -- the state an unreachable source leaves behind -- draws the same button at
`LibraryStates.kt:191` and `LibraryStates.swift:190`, and is not photographed. Reaching it
needs a source that was reachable and then is not.

`capture-android.mjs` has no route for any of the three states that draw this button. The
Android frames here were taken by clearing the app's data and capturing the `Library` route,
which lands on the empty state only because a fresh install has nothing in it.
