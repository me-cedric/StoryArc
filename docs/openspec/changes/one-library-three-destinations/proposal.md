# One library, three destinations

**Platforms: both.** Presentation diverges in two named places — how search is
reached, and how the destination set behaves on a large screen. Behaviour, rules
and data are mirrored.

## Why

The information architecture this app is supposed to have is not merely unbuilt.
It is **unspecified**, and [AGENTS.md §3](../../../../AGENTS.md) forbids building
what is not specified. `grep` finds no mention of a tab bar, a navigation bar, a
home surface or a downloads destination anywhere in `docs/openspec/specs/`. What
the specs *do* say about navigation is wrong in three places, and each one is a
sentence a reader can feel.

**1. Every server the reader configures becomes a place to go.** Both apps build
primary navigation as *Library → one row per browsable source → Collections*. Add
a folder and a Kavita server and the reader's own navigation says *Kavita* to
them. Add four and Android is at Material's three-to-five ceiling for a
navigation bar; add eight and it is over it with nothing to catch the overflow.
`sources` and `library-browsing` both assume that shape — `library-browsing`
makes "narrow to one source" a *scope*, which is a mode you are in rather than a
filter you applied, and it narrows search as a side effect.

**2. The library asks the wrong question.** The scope axis is origin — *which
server did this arrive from*. The question a reader actually has is *can I read
this on the train*. The existing `library-browsing` spec already contains both
answers and lets them disagree: a source scope selector at the top, and a
"Filtering offline" scenario further down. One of its own open questions admits
the source axis is the odd one out.

**3. There is nowhere to be that is not the shelf.** "Continue reading" is
specified as a *row inside the library view*, and in both apps it is hidden the
moment a search or a selection is active — the app withdraws the one editorial
thing it has exactly when the reader is looking hardest. There is no downloads
destination either: everything a reader needs before a flight lives inside the
settings modal.

The direction this implements is
[`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md)
§3.1, §3.2, §3.3, §3.7, §3.11, §4.1, §4.2, §4.7 and §6. Its one-line summary: *a
private library, dimly lit — a shelf and a reading room, never a file manager.*

## What changes

### New capability: `navigation-shell`

Three destinations, permanently: a home surface, the whole library, and
everything readable on this device. How a reader moves between them, what
survives that move, how search is reached, how the set behaves on a large screen,
and — the load-bearing sentence — **that the number of destinations does not
change when sources are added or removed.**

Extracted as its own capability because it is the frame every other browse
capability draws inside, and because `native-experience` owns *how a platform's
navigation looks and adapts*, not *what the destinations are*.

### New capability: `home-screen`

The editorial surface. **Keep reading** and **Up next** as two separate ideas —
where you stopped, and the next unread issue of a series you have started.
Comparable readers that ship both are the ones readers stop complaining about;
conflating them is an argument other apps have been having for years. Then
recently added, pinned shelves, and finished as a dated timeline. Plus the part
that matters more than any of it: **how Home degrades when the library is two
comics old, and that it is assembled from local reading history alone and never
waits on a server.**

### Modified: `library-browsing`

- **Unified library** — the library is one library and stays one library. Scoping
  to a single source stops being a mode.
- **Search** — results are grouped by what the match is, never by which server
  answered, and remote results arrive late without holding up local ones.
- **Filtering** — availability becomes the primary axis, and source survives as
  one filter among the others.
- **Presentation** — a cover carries at most two marks, progress and
  on-this-device. The source line under a cover goes. An unavailable publication
  dims; it never disappears, because a shelf that shrinks when the Wi-Fi drops
  reads as data loss.
- **Continue reading** — *removed*, and moved whole into `home-screen`, where it
  becomes two requirements instead of one.

This also settles the spec's own open question — *"Source is the scope selector,
not a filter group"* — in the opposite direction. The sync that follows this
change should drop that question and keep the other two.

### Modified: `offline-downloads`

The downloads view becomes a destination rather than a page inside settings, and
its promise widens from *the queue* to *everything readable with no network*. The
queue is pinned inside it while anything is in flight and absent when nothing is.
Storage limits, network policy and freeing up space stay in settings, where a
reader goes deliberately.

### Modified: `native-experience`

Adaptive layout says what large-screen navigation carries, and what it does not:
library sections and shelves, never one row per configured source. It also
records that the two platforms reach the same destination set by different system
mechanisms, which is the divergence this change is most likely to be argued with
over.

### Modified: `sources`

One scenario. The first-run empty state currently specifies *"an empty state
naming the four source types with a one-line explanation of each"* — a taxonomy
of transport protocols on a brand-new reader's first screen, two entries of which
are inert because the feature is not built. It becomes one sentence, one action
that opens a comic with no configuration at all, and one plain secondary that
leads to the four types one level down.

## Non-goals

- **No data-layer change.** The source registry, the scan, the credential store,
  the certificate pinning, the source clients and the progress store are
  untouched. This change adds an availability projection for a filter and moves
  where things are presented. That is the reason a revamp this size is not
  dangerous.
- **The publication detail screen** — a separate proposal. This change stops
  short of saying what happens after a cover is tapped.
- **A docked transport for read-aloud** — a separate proposal. This change
  reserves nothing and promises nothing about one.
- **Shelves, the readers, cover-image loading, and the vocabulary pass.** Already
  specified, or not a behaviour change.
- **Series as a screen of its own.** *Up next* and section headers are what this
  change buys; a series detail screen is a second detail screen and its own
  increment. Direction §8.5.
- **Naming.** Whether the third destination is called *Downloads* or *On this
  device* is direction §8.4 and belongs to the vocabulary slice. The requirements
  below state the destination's promise, never its label.

## Risks

**Removing per-source destinations removes the only per-source browse Android
has.** iOS never shipped one — its scope menu has been written, translated and
unreachable for months — but Android's rail rows work today. The by-source filter
has to land in the same slice, or a reader who could narrow to their NAS this
morning cannot this afternoon. The requirement is written so the filter is the
replacement, not an addition to be done later.

**Home is a taste call made on the owner's behalf.** Three degradations —
carousel, single card, Home *is* the empty state — with thresholds chosen from
what comparable apps do rather than from anything measured. There is no telemetry
in this app and there never will be, so this cannot be settled after shipping.
Direction §8.3, and it is worth an explicit yes.

**One iOS behaviour is unverified.** Whether the platform's search role expands
into a field in place, or only sits apart and presents a search screen, could not
be sourced to the vendor's own documentation. The requirement is therefore
written as what a reader observes — search is one action away and takes over the
screen — which both renderings satisfy. If the field does not expand in place the
fallback is a presentation detail, not a spec change. Direction §8.1.

**The two navigation mechanisms will look more different than they do today.**
That is the intent, and it is the thing most likely to read as an inconsistency
in a screenshot pair rather than as nativeness. §4.9 of the direction carries the
rule for every case; this change's `design.md` carries the two that apply here.

**State restoration is a requirement, not a nicety, and Android does not have it
today.** A boolean cascade cannot restore a destination's scroll position,
selection and filters, and cannot give each destination its own back history. The
requirement that returning to a destination is a *return* and not a *reset* is
what forces the navigation rewrite — the largest and riskiest piece of work in
the whole revamp, and the reason this proposal has to land before any of it.
