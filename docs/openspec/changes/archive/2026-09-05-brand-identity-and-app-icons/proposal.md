# The brand the app actually has, and letting a reader pick its face

## Why

**StoryArc has no app icon.** `AppIcon.appiconset` declares a 1024×1024 slot and contains
no image at all, so iOS falls back to a blank tile. Android has a placeholder whose own
comment says so: *"Placeholder mark: an open book's spine arc. Replaced by the real app icon
before any release build."* Its background is `#EC7C27`, an orange picked to match an accent
that is about to change.

**And the accent no longer matches the brand.** The token set is built around `ember` —
`oklch(70% 0.165 52)`, described as "reading-lamp amber". The brand artwork the owner
supplied is a pink-to-violet arc, measured at `oklch(71% 0.20 357)` and `oklch(56% 0.24 291)`.
An app whose icon and whose accent disagree looks like two products.

**The supplied artwork cannot be shipped as it is.** The files are raster crops from a larger
composite: the "transparent" icon carries a white plate with a speckled grey edge, the mark is
off-centre in its own canvas, and the two renders disagree about where the gradient ends —
one finishes violet, the other blue-violet. They are a *design*, not an asset.

## What changes

**The mark becomes vector, authored from geometry.** It is six petals on a 2×3 grid, each a
square with one corner rounded to a quarter-circle, the lower-left one carrying a bookmark
notch — a shape that is exactly describable and therefore exactly reproducible at any size.
One definition emits the iOS raster sizes, the Android adaptive-icon vector drawable, and an
SVG for the docs, so the three can never drift.

**The accent becomes the brand pink**, at the lightness the current accent already occupies,
so every contrast relationship the token gate validates is preserved rather than re-argued.
The violet is added as the far end of the brand gradient — **for the identity, not for the
UI**: the mark, the icon and brand surfaces. Chrome keeps one accent, because the direction
this design system is built on is that chrome recedes.

**The accent tokens are renamed to their role.** `ember` describes a colour that is about to
stop being true, and a token called `ember` holding a pink is a trap for every future reader.
`accent`, `accentStrong` and `accentMuted` describe what they are *for*, so the next brand
change is a value change rather than a rename. It is 56 references across 14 files, most of
them generated.

**A reader can choose the icon.** Five faces of the same mark — the artwork already came as a
set — chosen in Settings beside Appearance, which is where a reader already goes to decide
what the app looks like.

## Platforms

**Both**, and the mechanisms are entirely different rather than merely styled differently:
iOS has a first-class API for this (`setAlternateIconName`) and Android has none, so Android
does it by enabling and disabling `activity-alias` components. That difference is visible to
a reader — Android's change takes effect in the launcher rather than instantly — and the spec
says so rather than promising what one platform cannot do.

## Non-goals

- **No new colour system.** The neutrals, the surfaces, the Natural theme and the OLED
  variant are untouched. This changes the accent's hue and adds one identity colour.
- **No cover-derived accent change.** `native-experience` already says in-content accents
  derive from cover art and chrome uses the brand accent. That division stands; only the
  brand accent's value moves.
- **No gradient in the chrome.** The pink-to-violet arc is the identity. A two-colour
  gradient across the UI would fight the direction the whole palette is built on.
- **No icon editor, no custom colours, no user-supplied art.** A fixed set the app ships.
- **Not a rebrand of the written material.** The name, the wordmark's typeface and the
  tagline are as supplied.

## Capabilities

- **`settings-and-about`** — choosing the app icon.
- **`native-experience`** — the chrome accent's value, and the icon a reader chose surviving
  the platform's own reinstalls and backups.
