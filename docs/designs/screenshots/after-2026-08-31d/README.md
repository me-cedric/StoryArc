# Android's search page, after

Same device, same seeded library, same commands as
[`before-2026-08-31d/`](../before-2026-08-31d/README.md), which carries the setup and the
caveats. This is what changed.

## What each pair proves

| Pair | Before | After |
| --- | --- | --- |
| `android-search-at-rest-light` | A bar, a navigation control, and an empty page between them. | The page offers before a letter is typed: the scope stated as two chips, *Pick up where you left off* over the book the reader is two pages into, and *Next in a series you have read* over volume 2 of the series whose volume 1 they finished. |
| `android-search-at-rest-dark` | The same emptiness, dark. | The same offer, dark — so neither shot is proving a theme change by accident. |
| `android-search-at-rest-scale2-light` | Empty at the largest accessibility text size. | The same sections at that size, headings on two lines and unclipped, covers reflowed by the shelf's own width ladder. |
| `android-search-scope-chips-squeezed-scale2` → `android-search-at-rest-scale2-light` | *On this device* broken over four lines with a lone "e" on the last. | The chip on its own line, one line, whole. A `Row` gives its second child whatever width the first left; a wrapping row gives it its own line. |

## All three sections, and what is in each

`android-search-at-rest-light-scrolled` is the same page scrolled to the foot of it. The seeded
library is seven files, and each section holds exactly what the rules say it should:

- **Pick up where you left off** — *Harbour Lights*, read two pages into by hand on the device.
- **Next in a series you have read** — *Cinder Season*, Ashfall Wake #2, because #1 was marked
  read. **Not #3**, which is also unread: `HomeShelves.upNext` offers the lowest unread issue
  after the highest finished one, and one per series.
- **You have never opened these** — *Under Glass* (Ashfall Wake #3), *Paper Moon*, *The
  Glasswright*, *Tin Kingdom*. Note what is **not** in it: *Cinder Season*, which is unread and
  is offered one heading up. `SearchSuggestions` removes it there rather than offering the same
  book twice under a heading that says less about it.

A first draft of this file claimed the third section was absent. It is not, and the scrolled
shot is why the claim was checked rather than left standing — three unread books were sitting
below the fold of the shot that was being read as evidence.

## One thing the screenshots found that no test had

Every card under *You have never opened these* announced itself to a screen reader as
"…. Part-read". `homeRemainingText` falls back to that sentence for a publication that declares
no page count, which is true of every shelf Home draws it for and false of two of the three
sections here. Read off the device's own accessibility tree, not off a picture. Fixed, and
`SearchAtRestTest` now asserts both halves — a never-opened card announces its title alone, a
part-read one still says how much is left.

**The same defect is still on Home**, on Up next, Recently added and Finished, and is not fixed
here: `homeRemainingText` is shared, and changing what three of Home's shelves announce inside a
change about search would be a second change wearing this one's clothes. Named in the handoff.

## Nothing to suggest

| Shot | What is in it |
| --- | --- |
| `android-search-nothing-to-suggest-light` | The app's data cleared, so the library holds nothing. One sentence, one primary action that opens a comic with nothing to configure first, one plain secondary that adds a folder — and **no headings at all**. |
| `android-search-nothing-to-suggest-scale2-light` | The same at the largest text size. The sentence runs past the fold, which is expected. |
| `android-search-nothing-to-suggest-scale2-scrolled` | The same screen scrolled: the whole sentence and **both** actions are reachable. This is the shot that turns the previous one from a defect into a scroll. |

**Two ways in rather than five, and it is a limitation rather than a design.** The library's own
empty state names four transports behind its secondary action; a catalogue, a Kavita server and
a share are opened by sheets `:app` owns, and `SearchScreen` has no way to reach them without a
parameter `SearchDestination` would have to pass — a file another agent owns this round. The
two that need only a system picker are wired here in full. The other three are **absent rather
than drawn dead**: a menu item that does nothing is worse than one that is not there.

## What these do not prove

- **That anything was fetched to draw them, or that nothing was.** The page is a projection over
  publications already on the device; that it cannot fetch is a property of
  `SearchSuggestions.of`'s signature and of the suite that runs it with no store, no registry
  and no client — not of a photograph.
- **The expanded bar.** Recent searches, the clear affordance and the results live there,
  unchanged by this batch and photographed in
  [`after-2026-08-31c/`](../after-2026-08-31c/README.md).
- **iOS.** Its half of section 2 landed in the previous batch and nothing here touches it.
- **A wide window.** Every shot is one 320 dp phone. The docked branch of the bar and the
  three-section page on a tablet are untested by picture.
