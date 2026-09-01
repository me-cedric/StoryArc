# A quieter reader, and a theme sheet with two levels

## Why

The reader is the screen StoryArc exists for, and it is the screen carrying the
most furniture. Open a publication, tap the middle, and three separate surfaces
arrive at once: a top bar, a bottom bar and a page slider. Between them they draw
a close button, a title, a table-of-contents button, a bookmark button, a theme
button, a search button, a settings button, a page number, a percentage, a chapter
name, a pages-remaining count and a full-width slider with a thumbnail rail. Every
one of them was justified on its own. Together they take about a fifth of a phone
screen and are the first thing a reader sees after the page.

**The progress display is sized for a comic and shown on a novel.** A 24-page
chapter of a comic wants a slider: pages are the unit, and dragging to page 14 is a
thing a reader does. A 400-page novel does not. Its reader wants to know roughly
where they are and get back to the text. Ours shows the comic version to both —
percentage, pages-remaining and a slider — and on a reflowable publication two of
those three are computed from a page count the spec itself says is not a stable
identity.

**The theme sheet does two jobs in one surface.** Six presets and eleven axes are
in the same sheet, so a reader who wants Paper scrolls past nine sliders to find
it, and a reader who wants to nudge line spacing hunts for it among the presets.
The presets are the common case by a wide margin and they are not what opens first.

## What changes

**One close, one menu.** Revealed chrome is a way out and a way in: a close
affordance, and a single menu holding everything else. Nothing that was reachable
stops being reachable — the table of contents, bookmarks, search, themes and
settings all move behind the menu, where they are *labelled* rather than being
eleven icons a reader has to recognise.

**Progress sized to the format.** A reflowable publication shows one line: how far
through, and how much of this chapter is left, in words. A comic keeps its slider,
because a comic reader really does drag to a page. Both live in the menu rather
than over the page, and the coarse position is drawn as a fill behind the menu's
own contents row — visible at a glance, costing no separate surface.

**Two sheets, not one.** The theme surface opens on the presets: a grid of named
swatches and nothing else, plus one full-width action that opens the second sheet.
The second holds the axes, each labelled with its current value rather than an
unlabelled slider, over a live specimen of the reader's own text — and a *reset*
that returns the modified preset to its published values.

**And it will not be a copy.** Three deliberate differences, chosen because they
are better for a reading app rather than to be different: the progress fill behind
a labelled row instead of a bare percentage; sliders that state their value, since
"line spacing 1.4" is actionable and a dot on a track is not; and a reset that says
which preset it restores, because a reader who modified Calm wants Calm back and
not a factory default they never chose.

## Platforms

**Both.** The reader is where the two platforms are furthest apart already —
`SwiftUI` sheets and a `.regular` toolbar against a Compose `ModalBottomSheet` and
an edge-to-edge scaffold — and [ADR-0001](../../../decisions/0001-independent-native-cores.md)
means neither draws the other's answer. The *behaviour* below is identical: same
count of revealed controls, same two-level structure, same reset semantics.
design.md names each platform's components and the guidance behind them.

## Non-goals

- **No new reading feature.** Nothing here adds a capability. Every control that
  exists still exists; this changes how many of them are on screen at once.
- **No change to the theme model.** The six presets, the eleven axes, the custom
  colour slot and the per-series scope in
  [`reading-themes`](../../specs/reading-themes/spec.md) are unchanged. This
  changes which sheet they appear in and adds a reset for a modified preset.
- **No change to progress storage.** [`reading-progress`](../../specs/reading-progress/spec.md)
  records what it already records; this is about what is displayed.
- **Not the shell.** The bottom bar, the search page and the changelog are
  [`quiet-shell-and-search`](../quiet-shell-and-search/proposal.md).
- **Not audio.** A playback surface over the reader is
  [`audiobooks-and-playback`](../audiobooks-and-playback/proposal.md).
- **No gesture removal.** Edge taps, swipes, pinch-zoom and the reading-direction
  mirroring are untouched. Fewer visible controls must not mean fewer ways in.

## Capabilities

- **`comic-reader`** — revealed chrome becomes a close and a menu; the slider moves
  into the menu.
- **`ebook-reader`** — a reflowable publication's progress is a sentence, not a
  slider; the theme surface opens on presets and Customise is a second sheet.
- **`reading-themes`** — customising a preset, and resetting it by name.
