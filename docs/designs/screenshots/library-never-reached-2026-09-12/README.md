# A source that has never been reached — 2026-09-12

Evidence for `library-browsing`'s scenario *A source that has never been reached*. The
scenario has three clauses, and each frame has to show all three: the library says the
source has not been read yet, it names it, and the rest of the library stays complete and
usable while it says so.

## The state in every frame

Three OPDS catalogues are registered. Two answer, one points at a port nothing listens on.

| Source | Port | What it does |
| --- | --- | --- |
| Attic Catalogue | 4444 | Answers. Contributes publications to the shelf. |
| Loft Catalogue | 4445 | Answers. Contributes publications to the shelf. |
| Cellar Catalogue | 4999 | Refuses the connection. Never answered, so it is the named one. |

Attic and Loft answered, so each carries a successful-sync stamp and neither is named.
Cellar has no stamp and is unreachable, which is the whole rule — see `sourcesNeverReached`
on both platforms.

## The frames

| File | Platform | Condition |
| --- | --- | --- |
| `ios-library-source-never-reached.png` | iOS | Light, default text |
| `ios-library-source-never-reached-dark.png` | iOS | Dark, default text |
| `ios-library-source-never-reached-ax5.png` | iOS | Light, `AccessibilityXXXL` |
| `android-library-source-never-reached.png` | Android | Light, font scale 1.0 |
| `android-library-source-never-reached-dark.png` | Android | Dark, font scale 1.0 |
| `android-library-source-never-reached-ax.png` | Android | Light, font scale 2.0 |

## What the iOS accessibility frame shows, and it is not clean

At `AccessibilityXXXL` the sentence reads in full and *Try again* is painted under the
floating tab bar. `safeAreaBar` gives the strip a height the stacked layout exceeds.
`ViewThatFits` and `fixedSize` were both tried and neither moved it, so the cap belongs to
the bar rather than to the notice — `UnavailableFolderNotice`, the same sentence-plus-action
shape in the same bar, has the same limit. It is **not fixed**. Android has no such cap: its
`Scaffold` bottom bar grows, and the font-scale-2.0 frame shows the sentence wrapped to three
lines with the button beside it.

## How to take them again

```bash
node scripts/opds-server.mjs <corpus> --port 4444      # and again on 4445

# iOS
pnpm build:ios:ui && pnpm seed:ios:ui
node scripts/capture-ios.mjs --out <dir> --device <udid> \
    --only SweepSourcesTests/testCaptureNeverReachedNotice
node scripts/capture-ios.mjs --out <dir> --device <udid> --appearance dark \
    --only SweepSourcesTests/testCaptureNeverReachedNotice
node scripts/capture-ios.mjs --out <dir> --device <udid> \
    --only SweepSourcesTests/testCaptureNeverReachedNoticeAtLargestText

# Android
pnpm build:android
adb install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
node scripts/seed-android-sources.mjs --device <serial>
node scripts/capture-android.mjs Library --out <dir>/android-…png [--dark] [--font-scale 2.0]
```

`seed-android-sources.mjs` copies the owner of `app.storyarc.library.xml`, so it fails on a
device where the app has never written one. Launch the app once first; if that file is still
absent, put an empty `<map />` preference file there with the app's own uid before seeding.
