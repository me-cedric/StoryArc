# Design — named failures and quieter chrome

## Every claim was checked before it was written down

A design review is a set of observations from a device, and observations from a device are
sometimes about the device. Each item was read against the code first:

| The review said | Verdict |
| --- | --- |
| A toast says "1 couldn't be opened", names no book, offers no action | **Confirmed.** `LibraryStates.swift:76` / `LibraryScreen.kt:425`, string `library.skipped %lld`, a `dwell` of 6 seconds |
| The player draws a generic headphones placeholder | **Confirmed.** `FullPlayerView.swift:89` is `Image(systemName: "headphones")` |
| Five unlabelled toolbar icons | **Confirmed, and undercounted** — `LibraryToolbar.swift` has **six** `ToolbarItem(placement: .primaryAction)` |
| The iOS hero is nearly a full viewport, with no author, progress bar or Read button | **Confirmed in substance, overstated in size.** No `ProgressView`; the kicker is series-or-publisher so no author; the card is the only target. It is 4:5 at up to 420pt, so about **half** a phone's height, not nearly all of it |
| Android Home has no continue-reading hero | **Stale.** It has one, first on the surface, conditional on there being something in progress |
| Android's "Title" chip reads as a filter value | **Confirmed.** `library_sort_title` is "Title" and it is the chip's whole label |
| The iOS player's Close pill could be the sheet grabber | **Confirmed.** `FullPlayerView.swift:61` is an explicit `Button { dismiss() }` |

The one stale item is written into the proposal rather than dropped, because *"Android is
missing the hero"* is a plausible brief that would have sent somebody to build a second one.

## Where each item goes, and why not all of them are here

Three of the four capabilities involved are owned by **changes that are still open**, and
putting a second delta on a requirement another change already modifies is how scenarios get
silently dropped at archive time — which has already happened once in this repository and cost
six carried scenarios to repair.

| Item | Capability | Change that owns it |
| --- | --- | --- |
| The accent | `native-experience` | [`brand-identity-and-app-icons`](../brand-identity-and-app-icons/design.md) — and it caused a reversal there |
| The hero | `home-screen` | [`one-library-three-destinations`](../one-library-three-destinations/) — four scenarios added to *Keep reading* |
| The player's artwork | `audio-playback` | [`audiobooks-and-playback`](../audiobooks-and-playback/) — one scenario added to *One player for everything that speaks* |
| The failure notice, the toolbar | `library-browsing` | **here**, because this is the one capability with a main spec |

So this change is deliberately the smaller half. The alternative — one change carrying deltas
on four capabilities, three of them contested — would have been tidier to read and worse to
merge.

## The failure notice

**What exists.** A `Group` with `isShowing` and a six-second `dwell`, rendering
`library.skipped %lld` over the shelf. It is the same on Android. The count comes from the
scan; the *reasons* exist and are thrown away — `PublicationIndexer` produces
`IndexError.unsupported(format:)`, `.unreadable(reason:)` and `.contentProtected`, each already
worded, and the library keeps only the tally.

**What it becomes.** The reasons are kept alongside the count, so the notice can name one
publication or lead to a list of several. Three consequences worth stating because each is a
decision rather than an implementation detail:

- **It stops being timed.** A durable problem announced for six seconds is announced to nobody.
  Dismissal becomes the reader's.
- **It becomes reachable after dismissal**, which means it is state rather than an event, and
  something has to own it. The library's own model does, beside the scan results it already
  holds.
- **It clears itself when a publication starts working.** Otherwise the list becomes a graveyard
  of files that were fixed weeks ago, and a reader learns to ignore it — which is the same
  failure as the toast, arrived at slowly.

**No new text.** Every reason is already written and translated. This is about where the words
appear, not what they say.

## The toolbar

Six items in `.primaryAction`: a select `Button`, `ScopeMenu`, a show control, `SortMenu`,
`FilterMenu`, `AddSourceMenu`. Four are already menus, which is the shape the spec now asks
for; the work is folding the other two in and keeping select on its own.

**Select stays separate on purpose.** It changes the surface's *mode* — every cover becomes a
checkbox — where the rest present a choice and leave. Putting a mode switch inside a menu of
choices is how a reader ends up in selection without knowing they asked.

## Two smaller ones

**Android's sort chip.** `library_sort_title` is "Title", and the chip shows it alone. Beside a
chip that says "Filter", a chip that says "Title" reads as a filter value. It says what it is —
the ordering, not the field.

**The iOS player's close control.** The full player is a sheet, and a sheet has a grabber and a
downward swipe. An explicit Close is a third way out of a surface that already had two, and it
occupies the position the grabber wants. Android keeps its back affordance: its player is a
destination rather than a sheet, so there is no grabber to defer to — a divergence that comes
from the platforms rather than from taste.

## Proof

The notice, the toolbar and the hero are all visible changes, so §6 applies. The notice's
before is a shelf with a toast over it, which means the capture has to happen **within six
seconds of a scan that failed** — the fixture corpus has `refused.cb7` and
`rar4-solid.cbr` for exactly this, and `protected.aax` now too.
