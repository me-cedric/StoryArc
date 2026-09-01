# Design — publication detail

Visual composition is [`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md)
§3.4 and §4.4. This says what it is built from, and what already exists.

## The colour is already written, tested, and mirrored

This is the cheapest part of the change and it is worth stating plainly, because
the screen looks like it needs new colour science and it does not.

`CoverAccent` exists on **both** platforms as a deliberate mirror — the same
32×32 colour census, the same dominant-colour rule, the same 3:1 contrast floor
that `docs/design.md` §10 requires and `pnpm tokens:check` holds the palette to,
and the same case-for-case unit tests. It already returns "no accent" for a
black-and-white cover rather than inventing a muddy sepia, which is the manga
case and the commonest one.

What is missing is only the calling:

| | Extractor | Slot | Called from |
| --- | --- | --- | --- |
| iOS | `StoryArcCore.CoverAccent` | `DesignSystem.Theme.coverAccent` + the `coverAccent(_:)` view modifier | the reader's thumbnails only |
| Android | `core.model.CoverAccent` | none | `ReaderViewModel` only |

So iOS needs a caller; Android needs a caller **and** an environment slot to put
the result in — a composition local paired with the palette, so a page can be
wrapped in it the way the iOS modifier already works. No new extraction code, no
new dependency, and no `androidx.palette`: adding one would give the same book
two different colours on the two platforms, which is exactly what the mirrored
extractor exists to prevent.

### When a cover is available to sample — answered, 2026-09-01

This was written as an assumption and task 0.1 exists to settle it. It is settled, and the
answer is worse than the assumption allowed for.

**Never synchronously, on either platform.** The cover is `nil` on first composition and
arrives after — `PublicationDetailView.swift:33` with its `.task(id:)` at `:102-105`, and
`PublicationDetailScreen.kt:117-121`. Both cover accessors hold a warm in-memory map, and
neither exposes a synchronous read, so **even an already-cached cover misses the first
frame**. There is no source type for which the page composes with its wash already known.

**And for one class of publication it never arrives at all.** Both pipelines bottom out on a
local file path — `LibraryLookups.swift:77` (`guard let url = locations[publication.id]`) and
`LibraryViewModel.kt:1543` — and `locations` is written only when bytes are on the device: a
download, an import, a folder scan, or the watcher. So:

| Source | Cover available to sample | Consequence for the wash |
| --- | --- | --- |
| Local folder | After the first frame | Placeholder, then adopt |
| Downloaded from OPDS / Kavita / SMB | After the first frame | Placeholder, then adopt |
| **In the library from OPDS / Kavita / SMB and not downloaded** | **Never** | The page is permanently washless, and that is the state it must be legible in |
| Any publication whose cover yields no usable colour (the manga case) | After the first frame, and it yields nothing | Permanently washless, by the extractor's own decision |

The last two rows are why the delta requires a legible page for a cover that yields nothing:
the case is not an edge, it is every remote publication a reader has not downloaded, which for
a server-backed library is most of them. **A design that needs the wash to be readable is a
design that is broken for that reader**, so the wash carries no meaning and is
`accessibilityHidden`.

**Placeholder-then-adopt, with no visible flash — both platforms have it now.**
`DetailHero.kt:94-98` crossfades with `animateColorAsState`. iOS did not: the wash was
assigned unanimated and drawn in a plain `ZStack`, so it arrived as a hard cut — the flash the
task forbids in as many words. `DetailBackground.swift` now draws the gradient **always** and
fades its `opacity`, rather than holding it in an `if let`: a view that is *inserted* has
nothing to interpolate from, which was the actual cause of the cut. The arithmetic is
unchanged, because an opacity on the layer multiplies through the stops exactly as the
strength used to be baked into them, and the one point that was contrast-checked is still the
point drawn at full strength. Reduced motion removes the animation rather than shortening it,
per `native-experience`.

## Composition, per platform

| | iOS | Android |
| --- | --- | --- |
| Container | `NavigationStack` push, or the detail column of the adaptable split | `NavigableListDetailPaneScaffold` detail pane |
| Header | Large cover over the derived wash; `backgroundExtensionEffect()` on iPad so art carries under the floating sidebar | `LargeFlexibleTopAppBar` collapsing onto the cover |
| Primary action | `.buttonStyle(.glassProminent)` — the one place in the app a prominent glass button is warranted, because it *is* the most important functional element on the screen | Filled button |
| Secondary actions | `Menu` | Overflow menu, with add-to-shelf as a modal bottom sheet |
| Nested corners | `ConcentricRectangle`, per the platform's corner-matching guidance | `MaterialTheme.shapes`, once it is wired |
| Provenance | One `footnote` line | One `bodySmall` line |
| Back | The stack's own | Predictive back, which the scaffold animates |

**Versions.** Every iOS API above is iOS 26 or earlier, against a floor of 26.0
([ADR-0003](../../../decisions/0003-platform-floors.md)).
`NavigableListDetailPaneScaffold` is
`androidx.compose.material3.adaptive:adaptive-navigation` **1.3.0**, stable, and
is a dependency the project does not have yet — it arrives with the navigation
work in the other proposal. `LargeFlexibleTopAppBar` is on the `material3`
`1.5.0-alpha26` line the project is already pinned to.

**Assumed, and the ordering risk:** that this screen can be built on Android only
after the navigation graph replaces the boolean cascade. A pushed screen with
predictive back and a two-pane presentation has nowhere to live in an
`if / else if` over fourteen flags. If the navigation work slips, this screen
ships as a phone-only push and the pane presentation waits — which is a partial
delivery, and the handoff has to say so rather than quietly dropping the
large-screen requirement.

## The provenance line

The delta says what it must convey and forbids what it must not name. The
mechanism is a small projection over data that already exists: the source's
user-given display name from the registry, plus the availability answer the other
proposal's projection computes. No new store, no new field on a publication, and
nothing read from a source to render it — a line that needs a network round trip
to draw is a line that will be blank on a train.

The wording itself belongs to the vocabulary slice, which owns every strings
file. This change ships no new string of its own.

## Accessibility consequences

- **The wash is decoration and must be labelled as nothing.** It carries no
  meaning, so it takes no accessibility label, and nothing on the page may depend
  on it to be found. Under increased contrast or reduced transparency it is
  replaced by a plain surface rather than softened — softening a wash is how a
  screen ends up marginally below the floor instead of clearly above it.
- **One primary action is an accessibility feature, not a layout preference.** It
  is the first control after the title in the reading order, and its label states
  which of *read* and *continue* will happen, so a screen-reader user learns the
  outcome before taking it.
- **The provenance line is read, not inferred.** Availability is in its text, so
  a screen-reader user gets the same answer as a sighted one. Dimming a
  publication elsewhere is never the only way that fact is conveyed.
- **The series shelf needs per-item state in its labels.** Read, unread and
  on-this-device are marks on a cover for a sighted reader and must be words in
  the label for everyone else.
- **Two panes need a focus order that survives a resize.** When a window narrows
  and the page takes the whole window, focus goes to the page, not back to the
  top of the library — otherwise a keyboard or switch user loses their place
  every time an iPad is rotated.
- **Dynamic Type at the largest sizes is where a hero screen breaks first.** The
  title, the metadata stack and the primary action have to reflow rather than
  truncate; the screenshots the tasks require at the largest text size are how
  that is checked.
