# The shelf caption, 2026-08-31

Booted iPhone 17 Pro simulator (`11DFC984`, iOS 26.5, 402 pt wide), StoryArc built from
`main`. Appearance and text size set with `xcrun simctl ui <udid> appearance` and
`content_size`; captured with `xcrun simctl io <udid> screenshot`.

The `before-2026-08-31/` set beside this one was taken on the build immediately before the
fixes, on the same device, with the same library.

## What each pair proves

| Pair | Before | After |
| --- | --- | --- |
| `ios-shelf-caption-default-light` | Every cell prints its title twice — `Ashfall #1` in primary over `Ashfall #1` in tertiary, six times in one screen. The guard compared the *bare* series against the title while returning the *composed* `"<series> #<number>"`. | One caption per cover. Where a series line would repeat the title it falls through to the author, exactly as the no-series path already did. |
| `ios-shelf-caption-ax5-light` / `-dark` | Three columns at the largest text size, so `Ashfall #1` hyphenates to `Ash-` / `fall #1` and its neighbours truncate to `Ash-fall…` over a series line of `Ashf…`. The cover is recognisable and the caption is not, which inverts what a caption is for. | Two columns. The caption has roughly double the width and reads in full. The documented 104 / 132 / 158 pt tiers are untouched at every ordinary text size — a host test on each platform pins them. |
| `ios-shelf-caption-default-light` (bottom strip) | "1 couldn't be opened" in `textTertiary` over Liquid Glass — barely present against bright artwork. | `textSecondary`, legible at the default size. |

## One thing these captures also show, which is not fixed here

Look at the bottom strip of **`ios-shelf-caption-ax5-light`**. At the largest text size the
covers are big enough that the strip always sits over one, and the scan summary — a fixed
palette colour — is drawn over glass that has taken on a dark cover behind it. In light
mode it is very nearly invisible. In dark mode at the same size it reads, which is the tell.

The cause is not the token. `storyArcGlass` is untinted on purpose, because
[`design.md`](../../design.md) wants chrome to pick up the cover beneath it, so the
surface's luminance is whatever the artwork is — while a `Color` from the palette cannot
follow. The tab bar's own labels in the same strip stay legible in both appearances because
the platform draws them with vibrancy against the material.

The honest finding underneath it, recorded by the agent that made the token change: **no
text token is contrast-gated against glass at all.** `pnpm tokens:check` measures the three
text roles against `surfaceCanvas`, `surfaceRaised` and `surfaceSunken`. Untinted Liquid
Glass is none of those, and neither is `surfaceOverlay`, its own declared opaque fallback.
`textSecondary` was chosen because it has the most measured headroom of the three
(6.36–8.72:1 against 4.94–5.87:1), not because anything certifies it on this surface.

---

# The same change on Android, 2026-08-31

`storyarc-j6` emulator, 1080 × 2400 at ~400 dp, StoryArc debug built from `main`. Appearance
with `adb shell cmd uimode night yes|no`, text size with
`adb shell settings put system font_scale 2.0`, captured with `adb exec-out screencap -p`.

The before image is `before-2026-08-31/android-shelf-caption-default-light.png`, which is
the committed `after-2026-08-30/android-shelf-no-source-line-light.png` — the defect was
already visible in it and nobody had read it that way: `Harbour Lights #1` printed over
`Harbour Lights #1`. It now reads `Harbour Lights #1` over `Ada Lovelace`.

At `font_scale 2.0` the grid drops from three columns to two and every caption reads in
full, matching iOS.

## Two things these captures show that are not fixed

Both are visible in **`android-shelf-caption-scale2-light`** and neither belongs to the
caption change:

1. **The bottom navigation bar clips its labels.** "Downloads" is cut off at the right edge
   at `font_scale 2.0`. This is the shell, not the shelf, and it fails the `design.md` rule
   that every screen survives the largest accessibility text size.
2. **The filter chip row runs off the edge with no affordance.** "Filter" is half out of the
   window. It may scroll horizontally; nothing on screen says so.

The source chip strip above the shelf (`Attic NAS`, `Reading Room`) also overflows, but that
strip is what task 2.4 of `one-library-three-destinations` asks to be deleted, so it is not
worth fixing where it stands.

## One thing that is not a defect, recorded so nobody chases it twice

Launching this build took **75 seconds** on the emulator started with
`-gpu swiftshader_indirect`, ending back at the launcher with *"Skipped 139 frames! The
application may be doing too much work on its main thread"* in logcat. That reads exactly
like a startup defect and is not one. The same APK on the same AVD started with `-gpu host`
reports `TotalTime: 1483` — one and a half seconds. Software GL cannot keep up with Compose
on this host. **Start the emulator with `-gpu host`**, or measure nothing.
