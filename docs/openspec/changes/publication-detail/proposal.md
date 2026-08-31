# Publication detail

**Platforms: both.** The content model, the rules and the provenance sentence are
identical. The composition and the large-screen presentation diverge, and §4.9 of
the direction carries the rule for each.

## Why

**There is no publication detail screen.** `grep -rn "PublicationDetail"` finds
nothing on either platform. Tapping a cover in the grid opens the reader. The
only detail screen that exists anywhere is the one for a remote catalogue entry —
so the app has a detail screen *for the transport it supports least well* and
none for the books a reader actually owns.

That is the largest single gap between what is written down and what ships:

- [`docs/design.md`](../../../design.md) §9 already specifies a *Publication
  detail* component.
- The [`native-experience` spec](../../specs/native-experience/spec.md) already
  requires cover-derived accent "when a publication detail screen or the reader
  is shown".
- The plumbing exists on both platforms — the iOS cover-accent helper is written
  and tested — and **the library half of the app has never called it once.**

So this is not a new idea. It is the screen three existing documents assume, and
its absence has two consequences that cost more than the screen itself.

**First, there is nowhere to say where a book came from.** The direction's whole
argument (§6) is that the five library types become one library by making origin
invisible on the browse path — no per-source destinations, no server chips above
the shelf, no source line under a cover. That argument only works if origin is
*somewhere*. Take it off the shelf without a detail screen and a reader who owns
the same volume locally and on a server cannot tell which one they are about to
open. **The detail screen is the seam.** It is the one surface that can present a
local file, a catalogue entry, a server chapter and a share file identically and
then name, in one line at the bottom, which of them this is.

**Second, everything except reading has nowhere to live.** Download, remove the
download, add to a shelf, mark read, see the rest of the series: today these are
in a context menu on a cover, or nowhere. A reader who wants to know what a book
*is* before opening it has no screen to be on.

This is direction §3.4, §4.4, §6.2 and §6.3.

## What changes

### New capability: `publication-detail`

The screen, and the rules that make it the seam:

- **Reaching it.** A cover anywhere leads here. A resume affordance does not — it
  opens the book. The two are different verbs and the delta says which is which.
- **What it shows.** Cover, title, series, year, description, and the rest of the
  series as a shelf that behaves like every other shelf.
- **One primary action.** *Continue* or *Read*, with everything else secondary.
  The screen has one thing it wants you to do.
- **One provenance line.** The only place on the browse path where origin is
  named, stating both where it lives and whether it can be opened right now.
- **A publication that cannot be opened.** The screen still opens, from cached
  metadata, and says what it needs. It never becomes an error page.
- **The cover-derived wash**, adjusted until it clears the contrast floor, on the
  content and never on the chrome.
- **Large screens.** The detail is a pane beside the library rather than a screen
  pushed over it, and resizing does not lose it.

### Modified: `native-experience`

The *Dynamic colour* requirement's cover-derived accent scenario says "a
publication detail screen or the reader". It gains the home surface's hero, and —
the part that is currently unwritten and therefore keeps being got wrong — the
statement that **chrome never takes the cover's colour.** Untinted floating
chrome picking up the art beneath it is the design's own rule; a tinted tab bar
that changes hue as the reader scrolls past covers is the failure it prevents.

### Modified: `reading-progress`

**Declared late, and that is worth saying out loud.** This change shipped on both
platforms with no `reading-progress` delta, and two sentences in that spec were
written when a cover *was* the resume affordance. Syncing without this delta
would have left the contract describing an app that no longer exists.

The *Resuming* requirement is the one this change moves, and it holds in full for
the resume affordance — *Keep reading* still opens the book at the stored
position with nothing in between. What changes is that the requirement now
carries the two verbs rather than assuming one:

- *Continue from the library* said a tap on a partially read publication "opens
  at the stored position without an intermediate screen". That was one sentence
  covering both verbs because there was only one. It is now two scenarios: the
  resume affordance keeps the sentence unchanged, and the cover leads to this
  change's page, whose primary action continues from the same position and says
  so before it is taken.
- *Restart deliberately* justified putting "Start from the beginning" on the long
  press "because the library opens a publication when its cover is tapped". The
  **placement is still right and is unchanged**; only its reason was load-bearing
  on a premise this change removed. The replacement reason is the true one: the
  long press is on every cover on every browse surface, so starting over never
  needs a screen opened first — and it is never a page's primary action, because
  the primary action continues.

Nothing else in `reading-progress` moves. The local store, synchronisation,
conflict resolution and privacy requirements are untouched by a screen between
the shelf and the reader.

## Non-goals

- **A series screen.** *Other issues in this series* is a shelf on this screen,
  not a second detail screen. Whether a series deserves its own screen is
  direction §8.5 and its own increment.
- **Editing metadata.** Nothing here writes to a publication's title, series,
  tags or cover. The screen presents what the sources and the scan already
  supply.
- **Changing what the scan collects.** If a description is absent today it is
  absent on this screen, and the screen says nothing rather than inventing a
  placeholder.
- **The navigation shell.** This screen is pushed inside whichever destination
  the reader was on. That destination set is the other proposal's business.
- **Vocabulary.** The provenance line's exact wording belongs to the vocabulary
  slice. The delta specifies what it must convey, never the string.

## Risks

**The provenance line carries the whole argument, and it is one line.** If it is
wrong the seam leaks: too technical and the browse path has a protocol name on it
after all; too vague and a reader with the same volume in two places cannot tell
them apart. The delta therefore requires it to answer both questions at once —
where it lives, and whether it can be opened now — and forbids it from naming a
protocol, a transport, a server product or a path.

**Cover-derived colour is a contrast hazard, not a decoration.** A wash pulled
from a dark cover behind light text is a build-gate failure waiting to happen —
the project fails the build on a token pair below its WCAG floor. The delta
requires the derived colour to be adjusted until it clears the floor and never
used raw, and requires a legible screen when the cover is missing, monochrome, or
a single flat colour.

**Two entry verbs on one grid.** A cover opens the detail; a resume card opens
the book. That is deliberate and it is the thing most likely to be reported as an
inconsistency. It is written as a requirement so it is a decision rather than an
accident.

**On Android this depends on the navigation rewrite.** A detail screen with
predictive back and a two-pane presentation cannot be built on a boolean cascade.
The other proposal's Android navigation work has to land first, or this screen
ships on phones only and the tablet presentation waits.
