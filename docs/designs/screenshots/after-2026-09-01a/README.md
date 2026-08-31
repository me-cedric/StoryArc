# Liquid Glass, actually

**Captured 2026-09-01**, iPhone 17 Pro simulator.

The owner looked at the reader's chrome and said it did not look like modern Apple, and
gave Photos' own overlay as the example: dark translucent capsules with a specular edge,
plain glass icon buttons beside one prominent tinted action.

They were right, and the cause was one modifier.

## `.tint` on a plain glass button tints the material, not the glyph

Every floating control in this app was doing it — five call sites across both readers, the
page slider, the read-aloud transport and the return offer. `.tint(.white)` on
`.buttonStyle(.glass)` does not make a white glyph on glass; it makes a **white glass**,
which renders as an opaque pill with nothing showing through it.

`DesignSystem/Glass.swift` had already written the rule down, twice:

> Untinted, deliberately: the spec wants the glass to pick up the page beneath it, and a
> tint is precisely what stops it doing that.

> A fixed colour cannot sit on this material, and one had been sitting on it.

That second line records the same defect being found once before, **on a device**. The
finding lived in a doc comment on a helper that five of the call sites never used.

## What changed

| Control | Was | Now |
| --- | --- | --- |
| Reader close, reader menu (both readers) | `.glass` + `.tint` | `.glass`, untinted, `.foregroundStyle(.primary)`, `.controlSize(.large)` |
| Page slider's return offer | `.glass` + `.tint(.white)` | `.glass`, untinted |
| Read-aloud transport | all four `.glass` + `.tint` | play/pause `.glassProminent` + tint; the other three plain and untinted |
| Return-to-position offer | `.glass` + `.tint(theme.accent)` | `.glassProminent` + the same tint |

**`.glassProminent` is the variant meant to carry a tint** — the filled, emphasised one,
the shape the system gives a *Done* beside plain glass icon buttons. So the fix was not
"remove the tints": it was moving the controls that wanted emphasis onto the style that
expresses it, and taking the tint off the ones that never wanted it.

The glyphs take a hierarchical foreground style, which resolves against the material rather
than against a stored sRGB value — so it follows a page that is cream under one theme and
near-black under another. That is the second half of what `Glass.swift` had written down.

`.controlSize(.large)` is the scale the system draws floating chrome at. A control floating
over content has no bar to sit in and has to carry its own presence; at the default size
these read as small pale dots on a page.

## Why there are two "after" shots

`ios-epub-reader-chrome.png` is the reflowable reader on the Paper theme, and it is honest
but it **cannot prove the material**: the page is cream, so glass over it is cream, and a
control flattened into an opaque pill looks nearly the same as one that has not been. Put
`before-ios-epub-reader-chrome.png` beside it and the difference is a slight warmth and a
larger control — real, and not conclusive.

`ios-comic-reader-chrome.png` is the proof. The comic reader letterboxes a page against
black, so the same two controls sit over dark content: they are translucent, they carry a
specular edge, and the glyphs are white. Before this change they were solid white capsules
there too.

**The lesson is about where a capture is taken, not only whether one was.** A screenshot
over a light background could not have distinguished the defect from the fix, and the first
one taken did not.

## The guard

`GlassIsUntintedTests` fails on any `.buttonStyle(.glass)` followed by a `.tint(`, naming
the file and line, and separately fails if nothing uses `.glassProminent` with a tint any
more — so the rule cannot be satisfied by deleting emphasis instead of placing it
correctly. Mutation-checked: restoring the tint on `ReaderChrome` fails it and names it.
