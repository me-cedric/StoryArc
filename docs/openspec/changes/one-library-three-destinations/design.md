# Design — one library, three destinations

The spec deltas say what a reader observes. This says what each platform builds
it out of, and which parts of that are verified.

Visual composition is not repeated here. It lives in
[`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md) §3.1,
§3.2, §3.3, §3.7, §3.11, §4.1, §4.2 and §4.7, which this change implements.

## The shell, per platform

| | iOS | Android |
| --- | --- | --- |
| Container | `TabView` with three `Tab`s and `.tabViewStyle(.sidebarAdaptable)` | `NavigationSuiteScaffold` over a typed navigation graph |
| Search entry | `Tab(role: .search)` — the system separates it from the others and places it at the trailing edge | `TopSearchBar` + `SearchBarState` on Home and Library |
| Search expanded | The search role's own presentation | `ExpandedFullScreenContainedSearchBar` compact, `ExpandedDockedSearchBarWithGap` medium and up |
| Chrome receding | `.tabBarMinimizeBehavior(.onScrollDown)` | `MediumFlexibleTopAppBar` with hide-on-scroll |
| Wide window | The same `TabView` adapts into a sidebar | `WideNavigationRail`, collapsed for the three destinations, expanded for the secondary ones |
| Two panes | `NavigationSplitView` behaviour via the adaptable tab style | `NavigableListDetailPaneScaffold` |
| Breakpoints | `horizontalSizeClass`, the platform's own two states | Material's five window size classes |

**Versions.** iOS floor is 26.0 and every API above is iOS 26 or earlier
([ADR-0003](../../../decisions/0003-platform-floors.md)); there are no
compatibility shims and none are wanted. Android needs
`androidx.compose.material3.adaptive:{adaptive,adaptive-layout,adaptive-navigation}`
at **1.3.0**, which is stable and carries none of the material3 alpha risk, and a
navigation library the project does not currently have at all. `material3` is
pinned at `1.5.0-alpha26` today for `MaterialExpressiveTheme`; `TopSearchBar`,
`ExpandedFullScreenContainedSearchBar`, `WideNavigationRail` and
`MediumFlexibleTopAppBar` are on that same alpha line.

**Assumed, and it is the change's real technical unknown:** that the search-bar
and flexible-app-bar surface is non-experimental at the alpha the project ends up
on, and that adding `material3-adaptive` 1.3.0 alongside a `material3` 1.5.0
alpha resolves without a version conflict. Nobody has built it here. The version
catalogue has a single owner in a later wave for exactly this reason — this
design names versions, it does not edit the catalogue.

**Assumed, and it is a product unknown rather than a build one:** that
`Tab(role: .search)` expands into a field in place when selected. The
*separation* and the trailing placement are documented by the vendor; the
in-place expansion is well attested in practice and could not be sourced to
them. The spec is written so both renderings satisfy it. Fallback if it does not
expand: `.searchable()` with the minimizing search-toolbar behaviour, which the
vendor does document as rendering an inactive field as a button-like control.
Settling it costs one simulator screenshot.

## Why search diverges

This is the divergence most likely to be read as an inconsistency, so the rule
is written down rather than left to taste.

Material ranks search entry points explicitly: a **search bar** for searching
content in a view, a **search app bar** where search is the primary global
function, a **search icon button** where search is secondary. It permits the iOS
shape — a focused search destination reached from a navigation bar — but only as
the exception clause for apps whose primary action *is* searching. StoryArc's
primary action is browsing. Material also caps a navigation bar at three to five
always-labelled destinations, and a fourth search destination would spend one of
them on the exception clause.

So both platforms are asked for the same behaviour — *search is one action away
and takes over the screen* — and each expresses it with its own control. Putting
a separated circular search button into a Material navigation bar would read as a
port, which is the failure this whole revamp exists to fix.

## Two clauses this delta wrote, and why both were withdrawn

Settled **2026-08-31**, after search shipped on both platforms. Recorded here
rather than in a commit message because `/opsx:sync` erases the delta and keeps
nothing that explains it.

Both clauses were in *Mixed local and server search*. Both contradicted the main
spec or the app, and search had been built following the **main spec** — the main
spec is the contract and a delta is a proposal, so the code was right to. A sync
would have reverted shipped, tested behaviour in one case and shipped a promise
the code cannot keep in the other.

### "No result is labelled with the source that supplied it" — withdrawn

The main spec asks for results "each labelled with its source". The clause said
the opposite, and its reasoning was the revamp's own: origin is invisible on the
browse path, and the publication's page is the one place that names it.

That reasoning holds for a **shelf** and fails for a **search**, and the
difference is what the reader asked.

- A shelf is a wall of covers, and the reader is telling books apart by artwork.
  A source line under each one competes with the one thing doing the work. The
  argument is sound and *Unified library* keeps it.
- A search is a list of rows answering a question more than one place can answer.
  Here origin is not decoration; it is part of the answer. And a search result is
  the **choice itself** — a row a server supplied leads to that server's own
  browser, not to the publication page, so there is no page in between for the
  seam to be named on.

The evidence for it is on disk rather than in an argument.
`docs/designs/screenshots/after-2026-08-31/ios-search-remote-and-away-dark.png`
is a search with a catalogue and a folder configured. The server's log records
`200 GET /opds/all?q=Fine%20Print`. The catalogue's one match never reaches the
screen: it had the title the device already held, and the unlabelled merge folded
it out of existence with nothing on screen to say a catalogue had answered. That
is what an unlabelled list costs — with no label, two rows that read alike look
like a bug, so the merge deletes one; with a label, they are two facts a reader
can tell apart.

**What replaces it is narrower than the main spec, not a straight revert.** The
label is drawn when more than one *place* could have answered, the places being
the origins of what the device matched plus every library asked, decided once
when the question is put rather than as answers land. So the delta's intent
survives where it was right: a reader with one library sees no origin anywhere,
because there was never a question. The rule is deliberately **not** the shelf's
— the shelf gates on more than one *source configured*, and one server plus files
another app handed over is one source, which hid the label in the commonest mixed
search there is.

Two consequences, both taken:

- The fold rule is now a clause of its own. It is the half that makes the label
  more than decoration, and it is the half that was photographed failing.
- [`publication-detail`](../publication-detail/proposal.md)'s own delta named
  `search` among the surfaces that "state origin at all", which this decision
  makes false. That clause was corrected in the same pass; the two changes are
  independent proposals and were about to sync into a contradiction.

### "The arrival of remote results never reorders or displaces a result the reader is already reaching for" — withdrawn as unkeepable, replaced by what is true

This clause is in no main spec. It was a promise the delta invented, and the
implementation cannot keep it as written while also keeping a requirement the
same spec already makes.

Results are partitioned by match kind, because *Typing a query* asks for exactly
that — "grouped by match kind — series, publication, person, tag". Ranking runs
**across** kinds within one answer. So a late row whose kind already has a
heading lands inside that heading and pushes every later heading down by as many
rows as arrived. A result can move *down*.

The only way to fix the position is to append every late row at the very bottom
under a fresh heading of its own kind — and that shatters the device's own answer
into repeated headings before a server has said anything, because the device's
answer is already interleaved across kinds. One heading per kind and a fixed
position are not both available. The heading rule is the one a spec already
requires, so it wins.

**The honest promise, which the code does keep and which is now the clause:** no
result is removed, replaced or reordered against another. A result never moves
up, never past another result, and never under a different heading.

**What is genuinely lost, named rather than buried.** The clause's concern was a
reader's finger, not a data structure, and a list that pushes rows down under a
reader who is reaching for one is still a small betrayal. The data layer is
already append-only, which is the half a view cannot do for itself; the other
half is scroll anchoring in each platform's own list, so what is on screen stays
where the reader is looking when rows arrive above it. That is a view-level
behaviour, it is buildable on both platforms, and it is **not specified here** —
writing it into this clause would have put an unimplemented promise into a
delta whose whole problem was unimplemented promises. It belongs to whoever next
opens search.

## What must be rewritten before any of it

**Android navigation, entirely.** `MainActivity.kt` is 1168 lines holding roughly
fourteen `mutableStateOf` flags resolved by one `if / else if` cascade, with a
`BackHandler` per branch and the rail's selection re-derived from which flag
happens to be non-null. That shape cannot produce per-destination back history,
per-destination state restoration, deep links, or a pane scaffold — and the
delta requires all four. It becomes a real navigation graph with typed
destinations, which also drops the file under the project's 800-line cap.

**The per-source destination goes, on both platforms.** `LibrarySidebar.swift`
and `LibraryRail.kt` both build their list as *Library → one row per browsable
source → Collections*, from a destination case that carries a source identifier.
That case is deleted rather than hidden: as long as a source *can* be a
destination, something will put one there again. What replaces it is a filter
that names the source, and the settings screen that owns connections. The chip
strip above the shelf goes with it — its content is a way in to a server, which
is not shelf furniture, and on iOS its glass sits underneath the navigation bar's
own glass, which is the nesting the platform demotes and this codebase has
already recorded a device observation about.

**iOS is additive.** `StoryArcApp.swift` puts `LibraryView` directly in the
`WindowGroup` body; a `TabView` goes around it and the existing library view
becomes one destination's content. The toolbar shrinks — settings and add-source
leave it — but nothing existing is restructured.

## The availability projection

The only new data-shaped thing in the change, and it is small. The library is
assembled from a scan that never consults the download record, which is why the
existing `library-browsing` spec has an open question about exactly this. The
projection answers one question per publication — *can this be opened with no
network* — from the download record plus the local-file case, and it feeds three
things: the primary scope, the mark on the cover, and the on-device destination's
contents.

It is a projection, not a store. Nothing is written, no schema moves, and it is
recomputed rather than cached, because a stale answer here is a reader tapping a
publication that is not there.

## Accessibility consequences

Stated because they are consequences of *this* design, not general good practice.

- **Three destinations is a screen-reader win and the main reason not to have
  five.** Every configured source currently adds a navigation item a screen
  reader must read past to reach the library. Nine servers is nine.
- **The receding navigation control must not be a trap.** Chrome that hides on
  scroll is the one pattern here that can strand a switch-control or
  screen-reader user, which is why the delta requires that a gesture the platform
  already teaches always brings it back, and that reduced motion changes the
  animation but never the reachability.
- **Search that takes over the screen must return focus.** On dismissal focus
  belongs where the reader left it, not at the top of the destination.
- **Dimming is not a status.** An unavailable publication is dimmed *and* says so
  in its accessibility label, because opacity alone conveys nothing to a screen
  reader and little at low vision. Same rule for the on-device mark on a cover:
  the mark is the visual, the label is the fact.
- **Two marks on a cover is a ceiling for a reason.** A cover cell's
  accessibility label has to stay a sentence a person can listen to — title,
  progress, availability. A third mark makes it a list.
- **Dynamic Type and large text sizes are where a three-item bar earns itself.**
  The delta's largest-text-size screenshots are not decoration; a five-item bar
  at the largest text size is where labels truncate first.
