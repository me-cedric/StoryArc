# Reader theming and page transitions

## Why

The reader is the product. Today's `ebook-reader` spec says typography is
adjustable but does not say *what* is adjustable or how it is presented, and
`comic-reader` lists five page transitions with no shared model behind them.
`settings-and-about` offers three appearances where four are wanted.

Apple Books is the reference for what "good" means here, and it sets a specific
bar: a single sheet that combines six named presets with per-axis fine control,
a live preview of real chapter text, and controls that are pleasant enough to
open mid-chapter. That bar is worth meeting explicitly rather than approximating.

Research settles the build-versus-adopt question, and it splits cleanly:

- **Readium covers every typographic axis**, on both platforms, including
  `backgroundColor` and `textColor` — which is how custom theme colours work
  without forking a rendering engine.
- **Readium exposes no page-transition preference at all.** Slide, curl and fade
  are ours to build on both platforms.

That asymmetry is the shape of this change.

## What changes

### New capability: `reading-themes`

The theme model both readers share: six named presets, the axes each one sets,
custom colour, and how a preset relates to the app appearance. Extracted as its
own capability because the readers consume it rather than owning it, and because
the app's appearance setting and the reader's theme now interact.

### New capability: `page-transitions`

The transition engine: slide, curl, fade and scroll, with the curl finger-tracked
and interruptible. Shared by both readers because a transition is about the
container, not the content. Contains the platform-honest statement of what a curl
over reflowable web content actually costs.

### Modified: `ebook-reader`

Replaces the vague "typography controls" requirement with the ten concrete axes,
the live preview showing chapter title and body, and the mapping from each axis
to its Readium preference — including the `publisherStyles` dependency that most
of them carry.

### Modified: `comic-reader`

Points its transition requirement at `page-transitions` instead of restating it,
and renames `fade` to `fastFade` to match the vocabulary the reader UI uses.

### Modified: `settings-and-about`

Four appearances, not three: System, Light, Dark, and OLED Dark — plus Natural
as a fifth that is a *theme* rather than an appearance, since it carries texture
and accent treatment rather than a light/dark polarity.

### Modified: `native-experience`

Adds the specific platform presentation this change owes: an iPadOS layout
following Books' sidebar-and-grid structure, Liquid Glass treatment of the
settings sheet matching Books on iOS 26, and the Material 3 Expressive
equivalents on Android — a bottom sheet with tonal cards rather than a
translation of the iOS sheet.

## Non-goals

- **Audiobooks.** Out of scope entirely.
- **Matching Apple's exact theme values.** They are not published. StoryArc's six
  presets carry the same names and roles and are its own interpretations.
- **Shipping Apple's fonts.** Books uses commercial faces such as Canela.
  StoryArc bundles openly-licensed families only.
- **Per-publication theme override.** Themes apply per series, as the readers
  already specify. A per-publication exception can come later if it is missed.
- **Cloning the Book Store, Search or Home tabs** visible in the reference
  screenshots. StoryArc has no store; its Home is the continue-reading surface
  already specified in `library-browsing`.

## Risks

| Risk | Detail |
| --- | --- |
| **Curl over reflowable content** | Readium paginates EPUB inside a web view. A finger-tracked curl over live web content requires snapshotting each page and animating the snapshot, which means text is an image for the duration of the turn. Open question below. |
| **Android shader floor** | AGSL `RuntimeShader` needs API 33; the project floor is API 31. Either the curl is mesh-and-transform based, or it is gated with a fallback below 33. |
| **`publisherStyles` coupling** | Line height, letter spacing, word spacing, paragraph spacing, text align, hyphens and type scale are all inert while publisher styles are on. The UI must make that legible rather than showing dead sliders. |
| **Texture cost** | A "Natural" theme with real paper grain is either a bundled tiling asset or procedural noise. The first adds bytes, the second is cheaper and scales. |

## Decisions

The four questions this change opened are answered. Rationale and consequences
are in `design.md`.

| Question | Decision |
| --- | --- |
| Curl over reflowable EPUB | **Snapshot-based.** Curl works on books too; each page is rastered and deformed. |
| Android curl floor | **Gated at API 33.** `minSdk` stays 31; the AGSL curl is available on 33+ and absent below, with Slide as the default there. |
| Natural's reach | **Accents app-wide, grain only on reading surfaces.** |
| Bundled fonts | **Five families:** Literata, Source Serif 4, EB Garamond, Bitter, Atkinson Hyperlegible — plus the system serif and sans, which cost nothing. |

The Android decision is the one that simplified the design rather than
complicating it: gating means **one** curl implementation, not a shader and a
mesh fallback. `page-transitions` already required Curl to be absent where it
cannot be honest, so the gate needed no new requirement — only a broadening of
that scenario from "cannot hold the frame rate" to "lacks the capability".
