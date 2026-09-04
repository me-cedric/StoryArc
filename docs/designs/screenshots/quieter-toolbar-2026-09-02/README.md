# The toolbar keeps two controls and two menus — and the rail stops being a scrim

Twelve pictures, iOS only, taken on `StoryArc-iPhone17Pro`
(`11DFC984-7DF7-4E1A-99F6-B7B4BED091F8`) against the corpus `scripts/corpus.mjs` builds.

Two claims, from two changes, in one folder because they were photographed in one sitting:

- `named-failures-and-quieter-chrome` §2.6 — the library toolbar, **eight** pictures.
- `brand-identity-and-app-icons` §1.7, the iOS half — a cover's progress rail, **four**.

> **One glyph in the "after" shots is already superseded.** The View menu draws a
> `•••`-in-circle here, which was the two-state icon — `ellipsis.circle` while the shelf shows
> everything, the availability symbol otherwise. Later work made it draw the availability
> symbol **unconditionally**, so the axis is visible in both states rather than one. See
> `../stated-axes-2026-09-04/`. The item *count* in these frames — four items in three groups
> — is unchanged and is what §2.6 is proof of.

## The toolbar

| Picture | Appearance | Text size |
| --- | --- | --- |
| `ios-toolbar-before-light.png` | light | default |
| `ios-toolbar-before-dark.png` | dark | default |
| `ios-toolbar-before-light-largest.png` | light | `accessibility-extra-extra-extra-large` |
| `ios-toolbar-before-dark-largest.png` | dark | `accessibility-extra-extra-extra-large` |
| `ios-toolbar-after-*.png` | the same four | |

**Six glyphs become four items in three groups.** The before shows, left to right: select,
availability, layout, sort, filter, add — six controls, four of them an unlabelled glyph, in
two capsules that say nothing about which belongs with which. The design review called them
five; `LibraryToolbarTests` counted them at six before anything moved.

The after is `[Select] · [View · Filter] · [Add books]`. Availability and layout are pickers
inside the view menu, whose glyph is `ellipsis.circle` while the shelf shows everything.

**The dark pair is not decoration.** Both appearances are here because the toolbar sits on
Liquid Glass, and a capsule photographed only on paper says nothing about what it does over a
dark canvas.

**The largest-text pair answers a question rather than ticking a box.** Android's chip row ran
off the window at `font_scale 2.0` and had to learn to wrap. iOS draws these as toolbar icons,
and an icon does not grow with the reader's text: each row is the same width at both text
sizes, and neither the six-glyph row nor the four-item one overflows. So the improvement at the
largest size is the same improvement as at the default — two fewer glyphs to tell apart — and
nothing here was ever an overflow. Worth photographing anyway, because "it does not overflow"
is a claim worth exactly as much as the text size somebody pointed at it.

## The progress rail

| Picture | What the rail measures |
| --- | --- |
| `ios-progress-rail-before-light.png` | `#A6A6A6` on a `#FFFFFF` cover |
| `ios-progress-rail-after-light.png` | `#5A4886` |
| `ios-progress-rail-before-dark.png` | `#11100E` on a `#1A1815` cover |
| `ios-progress-rail-after-dark.png` | `#5A4886` |

The search screen rather than the shelf, because *Pick up where you left off* is where this
corpus reliably shows a part-read publication — the library grid's first screenful holds none.

**The numbers are the claim.** `.black.opacity(0.35)` is a scrim, not a colour: over white it
resolves to a mid-grey and over the dark cover it lands **within seven units per channel of the
artwork behind it**, which is a rail a reader cannot see. So the half of the bar that says *how
much is left* was legible on pale covers and absent on dark ones. `accentMuted` is `#5A4886` on
every cover alike, and `design.md` gives that token exactly this job — "accent at rest: progress
rails, unselected indicators" — which nothing in the app was doing.

Measured with a script rather than by eye, and that mattered: the first dark *before* looked
right and was wrong. It was captured by a background run that finished **after** the source
edit landed, so it photographed the change and was filed as its own before. Reading the pixel
caught it; looking at the picture had not.

**No largest-text pair for this one.** The rail is two points high at every text size, so the
size does not bear on the claim.

## What is deliberately not fixed here

The **segmented scope control** — *Everywhere / On this device*, visible in all four progress
pictures — is grey in an app that is violet everywhere else. It stays grey. It is the platform's
own control and neutral by design; `connected-button-groups` decided in its own `design.md` that
"iOS's segmented control is current and idiomatic on that platform" and is not replacing it; and
the only way to colour its selected segment is `UISegmentedControl.appearance()`, a global UIKit
proxy that cannot follow the Natural theme's two accents and so would be right in three
appearances and wrong in two. The pictures are filed as evidence for that decision, not as a
defect report.

## How to retake them

```bash
node scripts/corpus.mjs --simulator     # once, if the shelf is empty

for appearance in light dark; do
  node scripts/capture-ios.mjs --out <dir> --only testCaptureLibrary --appearance $appearance
  node scripts/capture-ios.mjs --out <dir> --only testCaptureLibraryAtLargestText \
    --appearance $appearance
  node scripts/capture-ios.mjs --out <dir> --only testCaptureSearch --appearance $appearance
done
```

A *before* means restoring the sources it photographs — `git checkout <commit> -- <paths>` over
the tree, capture, then put them back. **Wait for each run to finish before editing anything**:
that is the mistake recorded above, and the harness gives no warning when a capture builds a
tree that changed under it.
