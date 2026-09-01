# Design — one bar, a search page, and a word about what changed

## Where the guidance came from

Four research passes ran on 2026-08-31 against `m3.material.io`, the Compose
Material 3 API as it actually ships (`javap -v` over `material3-1.5.0-alpha26.aar`
in the Gradle cache, not the documentation's claims about it), and Apple's own
Human Interface Guidelines. Every Android claim below is either quoted from
Material or checked against the disassembled artifact. Where the two disagree, the
artifact wins and the disagreement is written down.

## The decision that governs the rest: search is a destination

Material states it directly: *"If search is the primary action, focused search can
be a standalone destination reached from a navigation bar."* That is permission,
conditioned on a judgement, and the judgement is ours to make.

**One of the four research passes argued the other way** — that StoryArc's primary
action is browsing a shelf, so search should stay a field belonging to the library
screen. That is a fair reading and it is being overruled, for a reason that is
about this app rather than about apps in general: StoryArc's publications arrive
from a device, a folder, an OPDS catalogue, a Kavita server and an SMB share, and
**no shelf shows all of them at once in a way a reader can scan**. Search is the
only surface that spans the sources. In an app whose library is one folder, search
is a filter; in this one it is the way in.

Four destinations sits inside Material's own range for both controls it will
appear in — 3–5 for the navigation bar, 3–7 for the collapsed rail — so nothing
about the count is strained.

## iOS

| Thing | Decision |
| --- | --- |
| The bar | `TabView` with four `Tab`s, `.tabViewStyle(.sidebarAdaptable)`, `.tabBarMinimizeBehavior(.onScrollDown)` — all already there |
| Search | `Tab(value: .search)` — **the `role: .search` is removed** |
| The search screen | `LibraryView(surface: .search)` with `.searchable(text:prompt:)` at the top of its own screen. **No `placement:`** — this row said there was one and there is not: the default placement is what a screen's own field wants, and naming a placement that is never passed sends the next reader looking for it |
| Scope | `.searchScopes` — the platform's segmented scope bar, which is the iOS idiom |
| Suggestions | `.searchSuggestions` is *not* used: it draws a list attached to the field, and what is wanted is a screen with headed sections. The screen draws them itself when the query is empty |
| What's new | A `.sheet` with `.presentationDetents([.large])`, presented from `AppShell` on the first appearance after a version change |

**What removing the role costs and buys.** `Tab(role: .search)` gives placement on
the trailing edge, a circular treatment, and the morph into a field. Removing it
loses all three and gains the thing the requirement asks for: a destination with a
screen behind it, drawn like its three neighbours, that does not change the shape
of the control the reader's thumb is resting on. `AppShell.swift`'s own comment
currently defends the role at length by quoting the old requirement text; that
comment is replaced along with the code, and the replacement says why the argument
changed rather than deleting it.

**The bar keeps its floating capsule**, because that is what iOS 26 draws and the
platform's own answer is the right one there.

## Android

| Thing | Decision | Why |
| --- | --- | --- |
| The bar | `ShortNavigationBar`, edge-to-edge, four destinations | Material states twice that the container "spans 100% of the window width" and is "always at the bottom" |
| Its shape | **Not a capsule.** No inset, no rounding | `ShortNavigationBar` exposes no `shape` parameter and `ShortNavigationBarDefaults` has no shape member — a capsule is not discouraged, it is inexpressible |
| Items at medium width | `iconPosition = NavigationItemIconPosition.Start`, `arrangement = ShortNavigationBarArrangement.Centered` | *"Use vertical items in compact windows … horizontal items in medium windows"*. Both APIs are public and stable; `AdaptiveNavigation.kt` composes its own items so it does not inherit this from the suite |
| The search screen's field | `AppBarWithSearch` in `Scaffold(topBar =)`, expanding to `ExpandedFullScreenContainedSearchBar` | The contained style is what `MaterialExpressiveTheme` mandates — Material marks the divided style *"Not recommended. Use contained"* |
| Its state | `rememberContainedSearchBarState`, and `rememberSearchBarWithGapState` for the docked branch | Each expanded bar names its required state partner in its own KDoc, and only those carry the content fade specs. One shared `rememberSearchBarState` cannot be right for both |
| Colours | `SearchBarDefaults.containedColors(state)`, fed to `appBarWithSearchColors` for the bar and to the input field **directly** as `searchColors.inputFieldColors` | The container colour interpolates as the bar expands; without it the contained bar is drawn with baseline colours. This row used to say the field's colours arrived *through* `appBarWithSearchColors`; they do not, and the code is right — that factory builds the app bar's colours and has no field in it |
| Scroll | `SearchBarDefaults.enterAlwaysSearchBarScrollBehavior()` | Material's scroll-away-and-return behaviour, which does not exist unless it is passed |
| Scope | `FilterChip`s, **not** a segmented control | Material retired the segmented button in the Expressive update; its named replacement is specified for *"two to five toggleable views"*, and our sources are an open, growing set. Material's own search page lists *"Filter chips to narrow down results"* |
| Leading icon | Hand-written swap: magnifier collapsed, back arrow calling `animateToCollapsed()` expanded | Material requires that *"the back icon releases focus"* and **no API supplies it** |
| Clear the query | Hand-written trailing icon | Material asks for *"an optional clear icon"*; `SearchBarDefaults` has no clear affordance of any kind — verified by `javap` over the whole class |
| Result rows | `ListItem(content =, supportingContent =)` with a transparent container; grouped by `ListItemDefaults.segmentedShapes(index, count)` rather than dividers | *"Use segmented gaps and filled list items to define a list group"*; dividers are for uncontained lists. Two corrections to what this row used to claim: there is **no `leadingContent`** — a result row carries no cover, and the second line is the series or the author, which is `supportingContent` — and the separation is not a *gap*: the `LazyColumn` sets no `verticalArrangement`, and the rounding of a group's first and last row is what reads as one group |
| What's new | `ModalBottomSheet` | Material's modal-sheet guidance describes this content almost exactly — *"when items require longer descriptions and icons"* — and a full-screen dialog meets none of Material's three criteria for one, while StoryArc runs on tablets where Material says to use a dialog or side sheet instead |

**Hiding the navigation bar during search needs no code.** The expanded full-screen
search bar is a full-screen dialog and covers the bar by construction — Material's
own navigation-bar page describes exactly this: *"temporarily covering the bottom
navigation bar until the search flow is completed."* Writing hide/show logic would
duplicate the component and fight predictive back.

## Where the two platforms deliberately differ

| | iOS | Android | Why not the same |
| --- | --- | --- | --- |
| The bar's container | Floating capsule, inset from the edges | Edge-to-edge, bottom-anchored | Material has declined the floating capsule for handheld navigation across two design eras, and the missing `shape` parameter makes the refusal structural. [ADR-0001](../../../decisions/0001-independent-native-cores.md) |
| Narrowing the scope | Segmented scope bar | Filter chips | The segmented button is retired in Expressive; iOS's scope bar is current and idiomatic |
| Hiding the bar in search | Authored | Free | The Android component is a full-screen dialog |
| What's new | Large sheet | Modal bottom sheet, one stop | Material routes a tablet-capable app away from full-screen dialogs. **The component diverges; the shape does not** — this row said Android's was "capped and expandable", and `WhatsNewSheet.kt` passes `setOf(SheetValue.Hidden, SheetValue.Expanded)` with no partial detent, which is the same single stop iOS's `[.large]` has. It was written that way on purpose and the source records why: a modal sheet lays its content out at full height and is translated down to a partial offset, so the pinned *Continue* sat below the visible edge |

## What is not designed from guidance

Two things are ours, and the delta should not dress them up as Material:

- **The suggestions before a query.** Material knows only *"historical suggestions"*
  before typing. Continue-reading, never-opened and next-in-series are a product
  choice. Permitted, not prescribed.
- **The "no recent searches" empty state and the clear affordance.** Material is
  silent on both. The existing `TextButton` is a free, defensible choice.

## Deferred, deliberately

- **A Downloads badge.** `BadgedBox` around the icon is the sanctioned case for a
  count, but Material requires the badge *beside the label* in the expanded rail and
  no API offers that, so it needs a hand-composed label slot branched on
  `railExpanded`. Its own change.
- **`ModalWideNavigationRail` for Shelves and Settings at compact width.** Material's
  named answer to overflow, stable and unused — but it adds a second dismissible
  surface to a project that deliberately keeps one back rule. Its own change.
- **`EntryLabel`'s `TextOverflow.Ellipsis`.** The rail guidance forbids truncation and
  permits a line break instead. The pinned font scale means it should never fire in
  the four shipped languages, so this is a latent contradiction rather than a live
  defect. Recorded, not fixed here.
