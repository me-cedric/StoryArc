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

## The section that is absent, and is the point

There is **no *You have never opened these*** heading in the seeded shots, and there should not
be. Every publication in that library is either part-read, finished, or the next volume in a
series — and *next in a series* wins over *never opened*, so nothing is left for the third
section. `navigation-shell` asks the screen to say so "rather than drawing empty headings", and
a section with nothing in it being **absent** rather than present-and-empty is what that looks
like. A shot with three headings and two runs of covers would have been the failure.

The same rule, from the other end, is `SearchAtRestTest`'s first assertion.

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
