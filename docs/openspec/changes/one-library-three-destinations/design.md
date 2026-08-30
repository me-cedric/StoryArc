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
