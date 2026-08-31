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
