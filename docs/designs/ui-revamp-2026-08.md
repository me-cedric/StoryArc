# UI revamp — design direction

**Status:** proposal, awaiting the owner's approval or redirection.
**Date:** 2026-08-30. **Scope:** both apps, presentation layer.
**Supersedes nothing.** [`docs/design.md`](../design.md) stays the token and
material contract; this document is the *product* design that sits on top of it,
and it contradicts `design.md` in exactly one place, named in §4.6.

This is the synthesis of five research slices (platform APIs, Material 3
Expressive, comparable apps, a full string-and-screen audit, and a skills
evaluation). It is written to be approved, argued with, or redirected — and then
built from. Where it chooses, it says so and gives the reason. Where it cannot
choose without the owner, §8 says exactly what would settle it.

---

## 0. Constraints this design accepts

Stated up front because three of them shape the plan more than any visual
decision does.

| Constraint | Consequence for this work |
| --- | --- |
| **Tokens are one source.** `packages/design-tokens/tokens/*.json` generates `StoryArcTokens.swift` and `StoryArcTokens.kt`. Never hand-edit a generated file; run `pnpm tokens:sync` and commit the regenerated app copies in the same change. | A palette or radius change is one edit and two regenerated files. Cheap. It also means **no slice may invent a colour** — a new state mark takes an existing `status/*` token or a new token that clears `pnpm tokens:check`, which gates 37 contrast pairs across five ramps. |
| **There is no logging.** No backend, no analytics, no crash reporting ([AGENTS.md §2](../../AGENTS.md)). | The design cannot be validated by telemetry. Every claim about what readers do comes from comparable apps or from the owner. There is no "we'll measure it after ship". |
| **Every new string needs en, fr, de, es** ([`localization` spec](../openspec/specs/localization/spec.md)), and **the build fails on a missing key in any language.** | One label is 8 translated values across 5 files (iOS: 5 `Localizable.xcstrings`; Android: 20 `strings.xml` across 5 modules × 4 locales). A half-finished vocabulary pass is a broken build, not a partial improvement. §7 sequences it as one atomic slice. |
| **A screen change owes a screenshot from a booted simulator or emulator** ([AGENTS.md §6](../../AGENTS.md)), light and dark, default and largest text size. | **This has been impossible all session — the simulator control refuses to attach.** See §7.5. This is not a footnote; it is the gate every slice in this plan has to pass, and it is currently shut. |

---

## 1. The direction

**A private library, dimly lit — a shelf and a reading room, never a file
manager.** StoryArc's existing token direction is *editorial darkroom*, and this
revamp finishes the sentence: the artwork is not decoration on the interface,
the artwork **is** the interface, and everything the app draws is either a
window onto it or a floating layer of chrome that gets out of its way. That
produces two registers and the discipline to keep them apart. **Discovery
surfaces** — Home, publication detail, the reader — are editorial, generous and
few: large art, one hero moment per screen, serif titles, a colour wash pulled
from the cover itself, no more than two things asking to be looked at.
**Management surfaces** — the exhaustive library grid, downloads, collections,
settings — are dense, plain, quiet and reached by descending, never by
defaulting. The failure mode this design exists to kill is the one both apps have
today: the management surface is stapled to the discovery surface, so the first
thing a reader sees is a wall of undifferentiated thumbnails wearing a toolbar of
seven icons, a strip of server chips and a progress line that says *Scanning —
12 found*. Nothing in the browse path will ever again name a protocol, a
transport, a server product or a locator; where a book physically lives is a
single line on its detail page and a screen in Settings, and nowhere else. And
the two apps will be recognisably one product and unmistakably two platforms:
iOS is a Liquid Glass navigation layer floating over artwork, Android is a
Material 3 Expressive surface system with shape and motion doing the work that
glass does on iOS. **Where they diverge, they diverge because a platform rule
says so, and §4.9 lists every case with its rule.**

---

## 2. What is wrong today

All of the following was read in this worktree. File paths are repo-relative;
line numbers are from this checkout and will drift.

### 2.1 The information architecture the owner asked for does not exist at all

Not "is wrong" — **does not exist**.

- **iOS has no `TabView` in the app shell.** `apps/ios/App/StoryArcApp.swift` puts
  `LibraryView` directly in the `WindowGroup` body. The only `TabView`s in the iOS
  codebase are `ReaderFeature/ReaderContainers.swift:36` and the comments around
  `ReaderPages.swift`, where it is the page-swipe mechanism.
- **Android has no navigation bar and no navigation library.**
  `grep -rn "NavigationBar" apps/android --include='*.kt'` returns nothing. There is
  no `NavHost`. `apps/android/app/src/main/kotlin/app/storyarc/MainActivity.kt` is
  **1168 lines** holding roughly fourteen `mutableStateOf` flags (`catalogue`,
  `kavita`, `share`, `sharePath`, `openCollection`, `openList`, `openServerShelf`,
  `isShowingSettings`, `isShowingShelves`, `isShowingDownloads`, `reconnecting`,
  `offlineSource`, `refusedSource`, …) resolved by one `if / else if` cascade, with
  a `BackHandler` per branch and the rail's selection *re-derived* from which flag
  happens to be non-null.
- **There is no Home.** The closest thing is `ContinueReadingRow` inside the cover
  grid (`LibraryFeature/CoverGrid.swift`, `feature/library/CoverGrid.kt:207–245`),
  and it is **hidden the moment a search or a selection is active** — the app takes
  away the one editorial thing it has exactly when the reader is looking hardest.
- **There is no Downloads destination.** On both platforms it is a section inside
  the Settings modal: `SettingsFeature/DownloadsSettings.swift`,
  `feature/settings/DownloadsGroup.kt`. Android reaches it by setting two booleans
  at once (`MainActivity.kt:629–631`).
- **There is no publication detail screen.** `grep -rn "PublicationDetail"` finds
  nothing on either platform. `CoverCell.onTapGesture` opens the reader straight
  from the grid. The only detail screen that exists is `CatalogueDetailView.swift`
  / `CatalogueDetailScreen.kt` — **and it exists only for a remote OPDS entry.**

That last one is the largest single gap between the written design and the
shipped app: [`docs/design.md` §9](../design.md) already specifies a *Publication
detail* component, and the [`native-experience`
spec](../openspec/specs/native-experience/spec.md) already requires cover-derived
accent "when a publication detail screen or the reader is shown". The plumbing
exists — `DesignSystem/Theme.swift` has `coverAccent` — and **the library half of
the app never calls it.**

### 2.2 The library screen contradicts the design system it ships with

Four violations, each of a rule `docs/design.md` states by name.

| Rule in `design.md` | What the code does |
| --- | --- |
| "**Cover radius stays at 4 pt on purpose.** A comic cover is printed stock. Rounding it like an app icon reads as wrong." `StoryArcRadius.cover = 4` exists. | `LibraryFeature/CoverCell.swift:40` and `:45` use `StoryArcRadius.md` — **10 pt**. `StoryArcRadius.cover` is referenced **nowhere in `apps/ios`**. |
| "letterboxes onto `surfaceSunken` rather than distorting art" | `CoverCell.swift:151` is `.scaledToFill()` inside a fixed 2:3 frame. A manga volume or a square EPUB cover gets its edges cut off. `surfaceSunken` is defined in the palette and drawn by no view. |
| "Minimum cover width scales by size class: 104 / 132 / 158 pt" | `CoverGrid.swift:73` uses one `.adaptive(minimum:maximum:)` pair for every window. Android is worse: `CoverGrid.kt:125` is `GridCells.Adaptive(minSize = 108.dp)` and the `maximumWidth = 168.dp` declared at `:107` is **never applied to the grid** — it only sizes the bitmap decode. On a 1400 dp tablet that is roughly eleven columns of phone-sized covers. |
| "Downloaded state as a small filled mark in one corner" | `CoverCell` draws a progress rail and a selection tick. There is no downloaded mark on either platform, while `status/downloaded` sits in the palette described as "the one badge permitted to compete with cover art". |

Plus, Android only: `CoverGrid.kt:323` gives every cover a
`BorderStroke(1.dp, palette.borderSubtle)`. On a dense grid of full-bleed art that
reads as a wireframe.

### 2.3 iOS: glass is adopted in the wrong half of the app

The **reader is genuinely on-pattern** and should be the model, not the thing
replaced: `ReaderFeature/ReaderView.swift` and
`EpubReaderFeature/EpubReaderView.swift` both wrap chrome in a
`GlassEffectContainer`, use untinted glass, and declare a Reduce-Transparency
fallback in `DesignSystem/Glass.swift`. `EpubReaderFeature/ReadAloudBar.swift:16–20`
even carries a code comment recording that four `.buttonStyle(.glass)` buttons on
a `storyArcGlass()` surface made three glyphs vanish — that is glass-on-glass,
observed on a device, and it is the correct instinct written down.

The library has **one line** of glass adoption — `LibraryView.swift:381`,
`.scrollEdgeEffectStyle(.soft, for: .all)` — plus two `storyArcGlass(in: Rectangle())`
surfaces, one of which (`CatalogueStrip.swift`) is a full-width glass rectangle
installed by `safeAreaBar(edge: .top)` **underneath the navigation bar's own
glass**. That is the exact failure the `ReadAloudBar` comment documents. Not used
anywhere outside the two readers: `GlassEffectContainer`, `glassEffectID`,
`glassEffectUnion`, `.interactive()`, `backgroundExtensionEffect()`,
`ToolbarSpacer`, `sharedBackgroundVisibility`, `navigationSubtitle`,
`scrollTargetBehavior`, `containerRelativeFrame`, `scrollTransition`,
`visualEffect`, `tabViewBottomAccessory`, `tabBarMinimizeBehavior`, `TabRole`.

And `LibraryToolbar.swift` puts **seven `.primaryAction` items** on an iPhone —
Select, Layout, Sort, Filter, Add-source, Collections, Settings — with no
`ToolbarSpacer` grouping at all.

### 2.4 Android: the theme is Expressive and the UI is not

`core/designsystem/.../theme/Theme.kt` already calls `MaterialExpressiveTheme` with
`MotionScheme.expressive()`. Then, across all of `apps/android`:

`NavigationBar` 0 · `SearchBar` 0 (search is 30 hand-built `OutlinedTextField`s) ·
`FloatingActionButton` 0 · `FloatingToolbar` 0 · `ButtonGroup` 0 ·
`HorizontalMultiBrowseCarousel` 0 · `MaterialShapes` 0 ·
`MediumFlexibleTopAppBar` / `LargeTopAppBar` 0 (all twelve app bars are the small
`TopAppBar`) · `MaterialTheme.shapes` override **0** — so the `StoryArcRadius`
scale is declared in tokens and every Material component draws the default M3
shape scale, while call sites pass `RoundedCornerShape(StoryArcRadius.md)` by
hand.

`core/designsystem/.../theme/Typography.kt` maps StoryArc's roles onto Material's
slots using **iOS's numbers**: `displayLarge` 34/41 where M3 says 57/64,
`bodyLarge` 17/22 where M3 says 16/24 — and `titleLarge`, `displayMedium` and
`displaySmall` are not set at all, so three slots fall through to Roboto defaults
in a different scale from everything around them. A 34 sp display cannot carry the
very large title the owner asked for.

`Theme.kt` also provides `LocalStoryArcPalette` **and** a dynamic `ColorScheme` in
parallel, with no rule about which a screen reads — so `MaterialTheme.colorScheme.surface`
and `LocalStoryArcPalette.current.surfaceRaised` are two different colours in one
app, chosen more or less arbitrarily per file.

There is **no `androidx.compose.material3.adaptive` dependency anywhere** — no
`ListDetailPaneScaffold`, no `SupportingPaneScaffold`, no `NavigationSuiteScaffold`,
no `currentWindowAdaptiveInfo()`. Tablet layout today is the phone layout plus a
rail in a `Row` (`MainActivity.kt:679–706`).

### 2.5 Four iOS screens are written, translated, and unreachable

Verified: each of these names appears in `apps/ios` **only at its own declaration**.

| View | File | What the reader loses | Android |
| --- | --- | --- | --- |
| `ScopeMenu` | `LibraryBrowsingControls.swift:43` | **iOS cannot narrow the library to one source at all** | live |
| `RecentSearchSuggestions` | `LibraryBrowsingControls.swift:150` | no recent searches, though `library.search.recent` ships in four languages | live |
| `CachedNotice` | `LibraryStates.swift:43` | no "showing what was here, checking for changes" | live |
| `AddSourceMenu` + `ImportPublicationButton` | `LibraryBrowsingControls.swift:251`, `LibraryImportAction.swift:15` | **there is no in-app file import on iOS.** `LibraryToolbar.swift:44–89` hand-builds a four-item Add menu that omits it. The only way a file reaches iOS StoryArc is the system Open-in handler. | live |

Nine string keys × four languages ship unreachable behind them.

### 2.6 The plumbing *is* the navigation

`LibrarySidebar.swift` / `LibraryRail.kt` both build their destination list as
**Library → one row per browsable source → Collections**. Every OPDS catalogue,
Kavita server and SMB share the reader adds becomes its own place to go. Add four
servers and Android's rail is at Material's 3–7 ceiling; add eight and it is over
it, with no expanded variant to catch the overflow. Above the shelf,
`CatalogueStrip` pins a chip per server. Under every cover, when more than one
source exists, `library.cell.source` prints the source's name as a third line — so
a reader with a folder and a Kavita server sees the word *Kavita* under half their
library.

### 2.7 Two files are already over the project's own limit

`MainActivity.kt` 1168 lines and `LibraryScreen.kt` 1166 lines, against an 800-line
cap. `LibraryFeature` is 64 Swift files; `feature/library` is 52 Kotlin files. Any
plan that edits these has to split them, and splitting them is what makes parallel
agents collide. §7 assigns one owner per file for exactly this reason.

---

## 3. The iOS design

Floor is iOS 26 ([ADR-0003](../decisions/0003-platform-floors.md)), no compatibility
shims. Every API named below is iOS 26 or earlier unless marked.

### 3.0 The glass budget — the rule that governs every screen below

Apple's own ceiling, quoted: *"Avoid overusing Liquid Glass effects… Limit these
effects to the most important functional elements in your app"*, and glass belongs
to *"the topmost layer of the interface, where you define your navigation"*,
distinct from the content. So, for StoryArc, exhaustively:

**Glass is:** the tab bar, the tab bar's bottom accessory, the iPad sidebar,
toolbars, the reader's two floating bars, and sheet chrome. **Glass is not:** the
cover grid, a cover cell, a section header, the publication-detail body, a Home
carousel card, a status chip, a badge, or any second bar stacked at the same
screen edge as the navigation bar. Nested glass is demoted by the system to a
vibrant fill — group with `GlassEffectContainer(spacing:)` instead. Tint only to
convey meaning; chrome glass stays untinted so it picks up the art beneath, which
is already what `design.md` says.

**First consequence: `CatalogueStrip` is deleted from the library.** Its content —
ways in to a server — is not shelf furniture, and its glass sits under the
navigation bar's glass. §6 says where that content goes instead.

### 3.1 The navigation shell

```swift
TabView {
    Tab("Home",      systemImage: "house")             { HomeScreen() }
    Tab("Library",   systemImage: "books.vertical")    { LibraryScreen() }
    Tab("Downloads", systemImage: "arrow.down.circle") { OnThisDeviceScreen() }

    Tab(role: .search) { NavigationStack { SearchScreen() } }
}
.tabViewStyle(.sidebarAdaptable)
.tabBarMinimizeBehavior(.onScrollDown)
```

- **`Tab(role: .search)` is the owner's requirement, and it is one line.** The
  system separates a search-role tab from the others and places it at the trailing
  edge — the circular button set apart in the Apple Music screenshot. It is also
  the bar Panels ships (Reading Now · Library · Store · Settings + a separate
  circular Search), which is the reference app the owner named.
- **Three content tabs, not five.** The HIG says avoid too many tabs and keep them
  consistent between iPhone and iPad. Home / Library / Downloads is the reader's
  relationship to their books — *what I'm in the middle of*, *everything I have*,
  *what works on a plane* — and no fourth axis earns a permanent seat.
- **`.tabBarMinimizeBehavior(.onScrollDown)`** so the bar recedes as covers scroll.
  This is the whole point of the material: chrome that gets out of the artwork's way.
- **Choose the standard search tab, not `Tab(role: .prominent)`** (WWDC26). Apple's
  own rule: prominent when the user already knows what they want, standard when
  search is exploratory and should land on a browsable page first. StoryArc's search
  lands on recent searches, collections and continue-reading — exploratory. §3.8.
- **Settings leaves the toolbar.** It becomes the trailing item of the Home
  navigation bar only, and the sidebar footer on iPad. It is not a tab; it is not
  on the shelf.

**The docked transport (`tabViewBottomAccessory`).** The slot exists and does
exactly what the Apple Music screenshot shows: above the tab bar at normal size,
inline when the bar collapses, with the glass capsule for free, keyed off
`tabViewBottomAccessoryPlacement`. **This design reserves the slot and does not
fill it in the first pass**, for one honest reason: the only transport StoryArc
has is EPUB read-aloud, it lives inside the reader
(`EpubReaderFeature/ReadAloudBar.swift`), and the reader is a `.fullScreenCover`
(`StoryArcApp.swift`) — speech ends when the reader is dismissed and there is no
tab bar behind it to dock to. **Making read-aloud outlive the reader is a
capability change, not a layout change**, and per [AGENTS.md §3](../../AGENTS.md)
it needs `/opsx:propose` on its own. A "continue reading" dock is a *different*
product idea and is open question §8.2.

### 3.2 Home — new screen, editorial, generated

The single most important new surface, and it must never try to be exhaustive. A
comics library has no editors, so **StoryArc generates its editorial**, the way
Komga, Kavita and KMReader do.

Vertical `ScrollView`, in order:

1. **A very large title**, `.navigationTitle`, large by default, with `.navigationSubtitle`
   for the second line where one earns its place. Nothing competes with it in the
   navigation bar — Settings is the only trailing item.
2. **Keep reading** — the hero. A horizontally paged carousel of the publications
   the reader is actually mid-way through: full-bleed art, a small uppercase kicker
   over the image (`.textCase(.uppercase)` with tracking over an `.overlay(alignment:)`
   gradient scrim — **not** a glass chip; the HIG says non-interactive status text
   does not take the material), the title in `editorial`, and a resume caption
   ("14 pages left"). `ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetLayout()`
   + `.scrollTargetBehavior(.viewAligned)`, cards sized with
   `.containerRelativeFrame(.horizontal, count:span:spacing:)` so the next card
   peeks by an exact fraction, and `.scrollTransition` for the depth as cards pass.
3. **Up next** — the *next unread issue of a series you have started*. This is
   Komga's On Deck, and splitting it from Keep reading is the highest-value pattern
   the research found: Mihon has years of open issues precisely because it conflated
   "resume where I stopped" with "open the first unread chapter". `Publication.series`
   already exists on both platforms (`StoryArcCore/Publication.swift:81`,
   `core/model/Publication.kt:187`), so this is a view-model projection over data
   the app already holds — **no store change**.
4. **Recently added ›** — a horizontal shelf.
5. **Pinned lists** — a reader's pinned collections and reading lists as first-class
   rows, KMReader's move. Curation you can see beats curation you navigate to.
6. **Finished, as a dated timeline** — Apple Books' idea, and it costs nothing:
   the progress store already holds completion timestamps. Optional, last on the
   screen, and it turns a dead state into something worth revisiting.

Every "… ›" header is a `NavigationLink` wrapping an `HStack { Text; Image(systemName: "chevron.right") }` —
there is no dedicated API; that is how Apple builds it too.

**Home degrades honestly.** Nothing in progress → no Keep reading section (absent,
not empty, per `design.md`). Fewer than three in-progress items → the carousel
collapses to one large card rather than a carousel of one. Empty library → Home
*is* the empty state (§3.10) and the Library tab is not offered as a wall of
nothing.

### 3.3 Library — the exhaustive shelf, and only that

`LibraryView.swift` survives as this tab's content, considerably lighter.

- **Large title, nothing beside it but a grouped toolbar.** The seven undifferentiated
  `.primaryAction` items become two groups separated by `ToolbarSpacer(.fixed)`:
  *[Select]* · *[Layout · Sort · Filter]*. **Add-source and Settings leave the
  toolbar entirely** (§6). That is Apple's stated rule — group items that affect the
  same part of the interface — and it is the problem WWDC26's `visibilityPriority`
  and `ToolbarOverflowMenu` were introduced for, which is the availability-gated
  second pass.
- **Section structure, not a uniform lattice.** Photos' answer: one continuous grid
  with pinned section headers (by series where `Publication.series` is non-nil, else
  by the current sort key) and a density control, rather than 4 000 cells at
  identical weight.
- **The scope selector changes axis.** Today it is *Source* / *All sources*. It
  becomes **availability**: *Everywhere* / *On this device*. This is Kindle's
  All/Downloaded and Mihon's Downloaded-only, and it is the axis readers actually
  care about — "can I read this on the train", not "did this arrive over OPDS".
  Source-scoping survives as a `From …` chip inside the filter sheet, which is what
  the [`library-browsing` spec's own open question](../openspec/specs/library-browsing/spec.md)
  already proposes.
- **Cover cell, corrected against `design.md`:** `StoryArcRadius.cover` (4 pt), art
  letterboxed onto `surfaceSunken` rather than `.scaledToFill()`, minimum cover
  width driven by size class (104 / 132 / 158 pt), a progress rail across the bottom
  edge, a small filled `status/downloaded` mark in one corner, title *below* the
  cell. **No source line, ever** — `library.cell.source` is deleted.
- **`.scrollEdgeEffectStyle(.soft, for: .all)` stays.** The existing rationale in
  the code — a hard cut across a cover looks like a rendering fault — is right.
- Recent searches, the cached notice and the scope menu are **wired up**, not
  redesigned. They already exist and are already translated (§2.5).

### 3.4 Publication detail — the new screen that makes the seam disappear

Pushed on a `NavigationStack` from any cover on any surface. Already specified in
`design.md` §9 and implied by the `native-experience` cover-accent scenario; the
`Theme.coverAccent` plumbing exists and has no library caller.

Composition, top to bottom:

1. **A large cover** over a **cover-derived background wash** — `Theme.coverAccent`,
   lightness-adjusted until it clears the contrast floor, never raw
   (`design.md` §7). On iPad this cover gets `.backgroundExtensionEffect()` so the
   art mirrors and blurs under the floating sidebar; applied **before** any text
   overlay, and the image must touch the leading and trailing edges.
2. **Title in `editorial`**, series and year in a tight metadata stack at `xs`, so
   the three read as one object.
3. **One primary action** — *Continue* or *Read* — and everything else in a menu:
   download, add to a list, mark read, remove. `.buttonStyle(.glassProminent)` is
   the one place a prominent glass button is warranted, because it *is* the most
   important functional element on the screen.
4. **Description**, then **Other issues in this series** as a horizontal shelf.
5. **One `footnote` provenance line at the bottom** — "On this iPhone" / "From
   *Home NAS*" / "From *Comics* — not downloaded". **This is the only place in the
   browse path where origin is named.**

`ConcentricRectangle` for any rounded container nested inside another, per Apple's
corner-matching guidance.

### 3.5 Reader — mostly leave it alone

The reader is the best work in the app. Changes are surgical:

- Keep `GlassEffectContainer`, the untinted chrome, the Reduce-Transparency
  fallback and the curl.
- Give the transition menu a **stable accessible name**: `ReaderChrome.swift:237`
  labels the `Menu` with the *current mode's title*, so the control's VoiceOver name
  changes as its value changes. Add a `theme.pageTurn`-equivalent title for the
  comic reader.
- Group the reader bar's controls with `ToolbarSpacer` / `glassEffectUnion(id:in:)`
  so related buttons read as one capsule rather than a row of separate pills.
- Where a control appears and disappears with mode, `glassEffectID(_:in:)` +
  `.glassEffectTransition(.matchedGeometry)` so it morphs rather than pops.
- **Do not add glass anywhere new.** `ReadAloudBar.swift:16–20` is the local proof
  of what happens.

### 3.6 Collections and reading lists

`ShelvesView.swift` keeps its two-section shape, and its doc comment — *"Two
sections here because they are two different ideas, not two different origins —
the origin is a label on a row"* — is the best sentence in the codebase and the
design principle for this whole revamp. Refinements:

- **Give them covers.** A collection with no artwork is a folder listing. Each row
  gets a `ShelfCover` mosaic (the component already exists).
- **Adopt Komga's metaphor in the copy.** A collection groups series by theme; a
  reading list is an ordered list of issues *from anywhere* — "playlists for books"
  is the sentence, and it is the one non-technical readers already understand.
- **Rename the screen.** It is titled *Collections* and contains a section also
  called *Collections*. Call the screen **Shelves**.
- **Demote "Copy to a server".** `PromoteList.swift` is good engineering and it is
  a power feature; it belongs behind the "…" on a list's own detail screen.

### 3.7 Downloads — a destination, not a settings page

The tab is **On this device**: everything readable offline, presented as the same
cover grid with the same cells, with the active download queue pinned at the top
while anything is in flight and absent when nothing is. Storage limits, Wi-Fi-only
and "free up space" stay in Settings, where they belong. (Whether the tab is named
*Downloads* or *On this device* is open question §8.4.)

### 3.8 Search — one surface for every library type

Today there are six search fields with six prompts: the library, this catalogue,
this server, this book, this PDF, settings. The search tab unifies the first three.

- The search tab lands on a **browsable page**: recent searches, pinned lists,
  Keep reading — not an empty field over a blank screen.
- Field placement is automatic and correct: bottom on iPhone (thumb reach),
  top-trailing on iPad; `placement: .sidebar` moves it into the sidebar.
- Results are grouped by **what the match is** — Titles, Series, People — and
  never by which server answered.
- **Remote results arrive late and say so**, inline, without blocking local
  results. That is the whole seam in one interaction: local hits render instantly,
  remote hits fill in, and the reader is never asked which they wanted.
- In-book and in-PDF search stay where they are. They are a different verb.

### 3.9 Settings

Structurally fine; it is where technical vocabulary is *allowed* (§5). Two changes:
**Downloads content moves out** (§3.7), and **Sources becomes "Your libraries"** —
the one screen that owns connections, credentials, certificates, scan state, per-source
cache and the coloured connection dots that currently leak onto the shelf.
`maxContentWidth` 720 pt so a settings list on an iPad does not stretch to a
1200 pt measure.

### 3.10 Empty states

`EmptyLibraryView` (`LibraryStates.swift:81`) currently renders one row per
`SourceKind` — four rows, three of them unintelligible to the target reader, two of
them inert because the feature is not built. It is a taxonomy of transport
protocols on a brand-new reader's first screen.

Replace with `ContentUnavailableView` and Apple's onboarding guidance (essential
information only, don't force setup before core functionality):

1. One sentence in reader language.
2. **One primary action: "Open a comic"** — the file importer. Zero configuration,
   two taps to a readable page. This is HIG's "try before you configure", and on iOS
   it also fixes §2.5 by wiring `ImportPublicationButton`, which is already written.
3. One plain secondary: **"Add a folder or a library"**, which opens the *Add books*
   flow. The four-way taxonomy lives one level down, where it is a deliberate choice
   rather than a wall.
4. No illustration without an action.

### 3.11 iPad

One `TabView`, `.tabViewStyle(.sidebarAdaptable)` — iPadOS renders a tab bar that
adapts into a sidebar; the adaptation is non-destructive, so rotating back to
portrait morphs it back. Apple's own guidance is that the tab bar is the
*recommended starting point* and can grow into a sidebar.

- **Sidebar structure follows Apple Music's**, which is what the owner sent:
  Search · Home · Library · Downloads, then a **Library section** (All books,
  Series, Recently added, Downloaded), then **Shelves** (collections and reading
  lists, pinned ones first). **No section lists servers.** Settings sits in the
  footer, outside the selection, as it does today.
- **`backgroundExtensionEffect()`** on the publication-detail hero and on Home's
  hero card, so art peeks under the floating glass sidebar. This is the single
  detail that most makes an app read as iPadOS 26, and it is used nowhere today.
- **Horizontal shelves touch the leading and trailing edges** so the system scrolls
  them under the sidebar automatically.
- **Cover width by size class** — 158 pt on a regular-width iPad, which is fewer,
  larger, more confident covers, not the same phone lattice widened.
- **`ScrollEdgeEffectStyle` and safe areas audited** next to the sidebar and any
  inspector, per Apple's adoption checklist.
- Publication detail is the **detail column** of the split, not a push, when the
  window is regular-width.

---

## 4. The Android design

Foundation is better than the brief implies — `MaterialExpressiveTheme` with
`MotionScheme.expressive()` is already there. Everything above the foundation is
missing. **This section deliberately does not mirror §3**; §4.9 is the register of
every divergence with the Material rule that justifies it.

### 4.1 The navigation shell — and the first, biggest divergence

```kotlin
NavigationSuiteScaffold(
    navigationSuiteItems = {
        AppDestination.entries.forEach { item(icon = …, label = …, selected = …, onClick = …) }
    }
) { … }
```

**Three destinations: Home, Library, Downloads. Search is not one of them.**

Material's search guidance ranks the entry points: a **search bar** for searching
content in a view; a **search app bar** when search is the primary global function;
a **search icon button** when search is secondary. It *permits* the iOS shape —
"if search is the primary action, focused search can be a standalone destination
reached from a navigation bar" — but that is the exception clause, and StoryArc's
primary action is browsing, not searching. Material also caps a navigation bar at
three to five destinations, always labelled.

So on Android, search is a **top search bar** on Home and Library:
`TopSearchBar` + `SearchBarState`, expanding to
`ExpandedFullScreenContainedSearchBar` on compact and
`ExpandedDockedSearchBarWithGap` on medium and up — both non-experimental since
material3 1.5.0-alpha23/24. Container is `surfaceContainerHigh`, and M3 warns not
to place `surfaceContainerHigh` on a `surfaceContainer` background, so the page
ground stays a step apart.

**Why this is the right divergence, in one sentence for the owner:** both platforms
are being asked for the same *behaviour* — search is one tap away and takes over
the screen — and each expresses it with its own control; putting an iOS-shaped
floating circular search button into an M3 navigation bar would read as a port,
which is exactly the failure this revamp exists to fix.

**Navigation must be rewritten first.** The boolean cascade in `MainActivity.kt`
(§2.1) blocks per-destination predictive back, state restoration, deep links and
pane scaffolds simultaneously. It becomes a real navigation graph with typed
destinations, and `MainActivity` drops well under the 800-line cap.

**No bottom accessory.** Material has no slot above the navigation bar for a
persistent mini transport, and inventing one would be the port failure in the
other direction. Android's transport surface is the **media notification** —
`ReadAloudService.kt` already runs a foreground service on a `readaloud_channel`.
That is the platform answer, it already exists, and it is better than a docked bar
because it survives the app being backgrounded.

### 4.2 Home

Same content model as iOS, different components:

- **`MediumFlexibleTopAppBar`** (or `LargeFlexibleTopAppBar`) carrying the large
  title and the search bar, non-experimental since alpha23. Not the small
  `TopAppBar` all twelve current bars use.
- **Keep reading is a `HorizontalMultiBrowseCarousel`** — Material's own carousel,
  which is the single most obvious component in an app of this kind and is used
  zero times today. `ContinueReadingRow` is currently a bare `LazyRow` of fixed
  128 dp cells.
- **One hero moment, not two.** M3 Expressive's own guidance: combine tactics for
  a hero moment, but "stick to one or two"; more is "overwhelming or distracting".
  Keep reading is the hero. It earns its emphasis through **shape and containment**,
  not tint — Expressive tactic #1 is to break from the surrounding shape style to
  draw attention, which is how you emphasise a card without putting colour on
  someone's artwork.
- Up next, Recently added, Pinned lists, Finished: plain shelves under
  `titleLarge` headers with a trailing chevron.

### 4.3 Library

- `MediumFlexibleTopAppBar` with the search bar, and **`hide-on-scroll`** so the
  bar gets out of the artwork's way — Android's equivalent of
  `tabBarMinimizeBehavior`, and step four of the `adaptive` skill's own workflow.
- **The six-plus-two control toolbar goes.** Select becomes a contextual top app
  bar on long-press; Layout / Sort / Filter become a **`ButtonGroup`** (stable
  since alpha22) or a filter-chip row; Add-source and Settings leave the shelf
  (§6); the explicit **Refresh button goes** — pull-to-refresh already exists and
  Android is the only platform carrying both.
- Cover cell: same corrections as iOS (4 dp radius, letterbox onto `surfaceSunken`,
  progress rail, downloaded mark, no source line), **plus** drop the
  `BorderStroke` hairline at `CoverGrid.kt:323`. M3 Expressive separates surfaces
  with shape and tone, not outlines.
- `GridCells.Adaptive` gains a real maximum and a per-breakpoint minimum; the
  declared-but-unused `maximumWidth` becomes load-bearing.
- **Delete the scroll-to-top on continue-reading arrival** (`CoverGrid.kt:116–119`).
  The comment acknowledges it; it is still a jump the reader did not ask for.
- **Scan progress becomes an Expressive `LoadingIndicator`** with "Adding your
  comics…", not "Scanning — 12 found". `LoadingIndicator` and `MaterialShapes` are
  still `@ExperimentalMaterial3ExpressiveApi`, so the `@OptIn` lives in exactly one
  file in `:core:designsystem` and nowhere else.

### 4.4 Publication detail

Same content, Material composition: `LargeFlexibleTopAppBar` collapsing onto the
cover, cover-derived wash from `Theme.coverAccent`'s Android twin, one filled
primary button, everything else in an overflow menu, provenance as one
`bodySmall` line. At expanded width and above it is the **detail pane**, not a
pushed screen — §4.7.

### 4.5 Reader

`ReaderScreen.kt` is 2156 lines in which roughly ten controls are each written as
`IconButton { Surface(color = scrim.copy(alpha = 0.6f), shape = CircleShape) { … } }`.
That is a hand-built floating toolbar. **`HorizontalFloatingToolbar`** has been
non-experimental since alpha23 and supplies the Expressive container, motion and
insets for free. Keep the curl, the AGSL path and the API-31 fallback exactly as
they are.

`core/designsystem/.../back/PredictiveBack.kt` is genuinely good work and stays —
but its **scope should shrink, not grow**, as `NavigableListDetailPaneScaffold` and
Material's own modal components take over what it currently hand-rolls.

### 4.6 Type, shape and colour — three rules the codebase currently lacks

**Type.** `MaterialTheme.typography` gets **Material's own scale**, not iOS's, and
the three unset slots are filled. StoryArc's `editorial` serif role stays exactly
as it is and carries publication titles. **This contradicts `design.md`'s
implication that the eleven roles map one-to-one onto both platforms, and it is
deliberate:** a type scale is a platform artifact, Material slots should carry
Material sizes, and a 34 sp `displayLarge` cannot carry the very large title the
owner asked for. It needs no token change — `Typography.kt` stops mapping
StoryArc's chrome sizes onto Material's slots. The Expressive **emphasized** styles
carry section headers, which is the point of "guide attention with typography".

**Shape.** `MaterialTheme.shapes` is wired from `StoryArcRadius`, once, in
`Theme.kt`. Today it is never set, so every Material component draws the default M3
scale while call sites pass `RoundedCornerShape(StoryArcRadius.md)` by hand. One
line, wide blast radius.

**Colour.** The `LocalStoryArcPalette` / `MaterialTheme.colorScheme` fork gets a
rule, scoped by surface class:

| Surface class | Colour source |
| --- | --- |
| **Chrome** — navigation bar and rail, search bar, app bars, sheets, dialogs, settings, download queue | Dynamic colour in full. This is where Material You earns its keep and where the app reads as an Android 16 app. |
| **Content** — cover grid ground, detail hero, reader | StoryArc neutrals: `surfaceCanvas`, `surfaceSunken`, `surfaceReader`. A wallpaper-derived tonal wash across a wall of covers destroys the one thing a reader is using to tell one book from another. |
| **State that must survive a wallpaper** — downloaded, offline, unread | Fixed `Status` tokens, which already exist and are already correct (`downloaded` #2DC08E, `offline` deliberately neutral). |

`Theme.kt` already handles the one genuinely incompatible pair correctly — its
comment that "a wallpaper-tinted true black is neither" is right. Keep it.

**Motion.** Custom animations consume the scheme —
`MaterialTheme.motionScheme.defaultSpatialSpec<Float>()` and
`defaultEffectsSpec<Color>()` — not `tween()`. The theme already declares
`MotionScheme.expressive()`; today nothing consumes it, so the motion is real and
invisible.

### 4.7 Tablets and the five breakpoints

Add the missing dependency — `androidx.compose.material3.adaptive:{adaptive,
adaptive-layout,adaptive-navigation}` at **1.3.0, stable since 12 Aug 2026**, which
carries none of the material3 alpha risk.

- **Replace the two-valued `StoryArcWindowClass`** (COMPACT / EXPANDED at 600 dp)
  with Material's five breakpoints. 600 dp is Material's *medium* boundary, not
  expanded (840 dp), so today a portrait tablet and a 1400 dp landscape tablet get
  the identical layout. Compact and medium: one pane, navigation bar. Expanded and
  above: two panes and an **expanded rail**.
- **`WideNavigationRail`, not `NavigationRail`.** Collapsed it holds the three
  destinations, inside Material's 3–7 rule. **Expanded — behind the menu icon — it
  reveals secondary destinations**: Shelves, pinned lists, and (if the owner wants
  them visible at all) connected libraries. That is Material's own mechanism for
  exactly the overflow problem §2.6 describes, and it means adding a ninth server
  can never again break the navigation.
- **`NavigableListDetailPaneScaffold`** for library ↔ publication detail, with
  built-in predictive back. `android:enableOnBackInvokedCallback="true"` is already
  in the manifest.
- **`SupportingPaneScaffold`** for reader ↔ thumbnails, so the thumbnail strip
  becomes a real supporting pane on a tablet instead of an overlay.
- Keep 40–60 characters per line across all breakpoints — relevant to the EPUB
  reader, which is currently full-bleed.

### 4.8 Empty states

Material 3 publishes no empty-state component or page; the pattern only exists in
Material 1's guidance. So Android composes the same content model as §3.10 by hand
— one sentence, one primary action ("Open a comic"), one plain secondary — rather
than importing iOS's `ContentUnavailableView` shape. Also fix the genuine mislabel:
`LibraryScreen.kt:995`'s primary button reads **"Refresh the library"**
(`library_scan_folder`) while actually launching the folder picker, because one
string serves both that button and the toolbar refresh icon's content description.

### 4.9 The divergence register

Every place the two apps deliberately differ, and the rule that makes it right.

| # | iOS | Android | The rule |
| --- | --- | --- | --- |
| 1 | Search is a separated `Tab(role: .search)` in the tab bar | Search is a top `TopSearchBar` on Home and Library | M3 ranks search bar / search app bar / icon button above a nav destination; a nav destination is the exception clause for apps whose primary action *is* search. Nav bar caps at 3–5 destinations. |
| 2 | `tabViewBottomAccessory` slot reserved for a docked transport | No docked transport; the media notification is the transport surface | Material has no persistent accessory slot above the nav bar. Android already runs `ReadAloudService` on a foreground channel. |
| 3 | Tab bar morphs to a sidebar via `.tabViewStyle(.sidebarAdaptable)` | `NavigationSuiteScaffold` → `WideNavigationRail`, collapsed 3 / expanded reveals secondary destinations | iPadOS's own adaptation vs. Material's collapsed/expanded rail with its 3–7 rule. |
| 4 | Two size classes (regular/compact), 600 pt | Five M3 breakpoints; two panes at 840 dp | SwiftUI's size class is the platform's own two-state answer; Material specifies five and ties pane count to them. |
| 5 | Detail pushes on `NavigationStack`; on iPad it is the split's detail column | `NavigableListDetailPaneScaffold` with predictive back | Predictive back is an Android system gesture with no iOS analogue; Material ships the scaffold that animates it. |
| 6 | Bulk undo is a `safeAreaBar` | Bulk undo is a `Snackbar` | Snackbar is Material's undo affordance; iOS has no snackbar and should not grow one. |
| 7 | Add to a shelf is a `Menu` | Add to a shelf is a modal bottom sheet | Already diverges today, correctly. Both are the platform-idiomatic shape. |
| 8 | Chrome depth is untinted Liquid Glass | Chrome depth is tonal elevation + shape; **dynamic colour scoped to chrome only** | `design.md` §5: "The two platforms do not converge here." Material You is Android's, and scoping it protects the artwork. |
| 9 | Chrome type is StoryArc's scale (17 pt body) | Chrome type is Material's scale (16/24 body, 57/64 display) + Expressive emphasized styles | A type scale is a platform artifact. Material slots carry Material sizes. |
| 10 | Emphasis via a prominent glass button and scale contrast | Emphasis via shape break + containment (`MaterialShapes` morph) | M3 Expressive tactics #1 and #2, and it emphasises without tinting artwork. |
| 11 | Motion from StoryArc spring tokens | Motion from `MaterialTheme.motionScheme` spatial/effects specs | M3 Expressive motion theming; its speed tokens are device-aware in a way fixed durations are not. |
| 12 | `ContentUnavailableView` | Hand-composed empty state, same content model | M3 has no empty-state component. |
| 13 | Reduce-Motion copy names the iOS setting | Copy says "your system is set to remove animations" | Already divergent today, and correct — do not "fix" it. |

---

## 5. The vocabulary change

**Rule:** technical vocabulary is banned on the browse path (Home, Library,
Downloads, Search, publication detail, shelves, empty states) and **allowed, even
required, in setup and error copy**, where the reader has deliberately gone to
connect a NAS and the acronym is the thing they typed into their router. The
existing *error* strings are genuinely good — plain, specific, they name the fix —
and this pass must not flatten them.

**Mechanics:** change **values, not keys**, wherever a key's name is not itself
misleading. A value-only pass touches five string files on iOS and twenty on
Android and collides with no view slice, which is what makes it safe to land
first. Key renames ride with the slice that rewrites the view that uses them.

### Tier A — browse path. Must change.

| Key (iOS / Android) | Today | Replacement |
| --- | --- | --- |
| `source.kind.opdsCatalog.title` / `source_kind_opds_title` | OPDS catalogue | **Online library** |
| `source.kind.opdsCatalog.explanation` / `..._explanation` | Any server that speaks OPDS, such as Calibre-Web or Komga | **A library you connect to over the internet. Works with Calibre-Web, Komga, Kavita and others.** |
| `source.kind.networkShare.title` / `source_kind_network_share_title` | Network share | **A computer on your network** |
| `source.kind.networkShare.explanation` / `..._explanation` | An SMB share on a NAS or another computer | **A folder another computer or home server shares with you** |
| `source.kind.kavitaServer.title` / `source_kind_kavita_title` | Kavita server | **Kavita library** (the reader typed the name; keep it, drop "server") |
| `source.kind.localFolder.explanation` / `..._explanation` | On this device, iCloud Drive, or any Files provider | iOS: **On this iPhone, in iCloud Drive, or anywhere in Files** · Android: **On this phone, in Google Drive, or anywhere in Files** |
| `catalogue.title` / `catalogue_title` | OPDS catalogue | **Add an online library** |
| `catalogue.add` / `catalogue_add` | Add catalogue | **Add** |
| `smb.title` / `smb_title` | Network share | **Add a shared folder** |
| `library.addSource` / `library_add_source` | Add a source | **Add books** |
| `library.import` / `library_import` | Import a File… | **Open a file** |
| `library.empty.subtitle` / `library_empty_subtitle` | Add a source, or just open a file — StoryArc works without any setup. | **Add somewhere to read from, or just open a file. StoryArc works with no setup at all.** |
| `library.scope` / `library_scope` | Source | **Show** (values: *Everywhere* / *On this device*) — see §6 |
| `library.scope.all` / `library_scope_all` | All sources | **Everywhere** |
| `library.search.widen` / `library_search_widen` | Search all sources | **Search everything** |
| `library.scanning` / `library_scanning` | Scanning — %lld found | **Adding your comics — %lld found** |
| `library.skipped` / `library_skipped` | %lld skipped | **%lld couldn't be opened** |
| `library.filter.readState` / `library_filter_read_state` | Read state | **Read or unread** |
| `library.filter.format` / `library_filter_format` | Format | **Kind of file** — or delete it; a reader does not filter by CBZ vs EPUB |
| `library.sort.fileSize` / `library_sort_file_size` | File size | **Size on this device** |
| `library.cell.source` / `library_cell_source` | *(source name under every cover)* | **deleted** (§6) |
| `catalogue.strip.hint` / `catalogue_strip_hint` | Browses this catalogue | *(strip deleted; string retired)* |
| `shelves.title` / `shelves_title` | Collections *(screen also contains a Collections section)* | **Shelves** |
| `shelves.list.unavailable` / `shelves_list_unavailable` | No longer available from its source | **No longer where it used to be** |
| `shelves.promote` / `shelves_promote` | Copy to a server… | **Copy to %@…** *(name the library)* |
| `shelves.pending.entry` / `shelves_pending_entry` | Waiting for the server | **Not saved yet** |
| `shelves.serverOnly.local` / `shelves_server_only_local` | Create a local list instead | **Make a list on this device instead** |
| `source.state.unreachable` / `source_state_unreachable` | Offline — showing cached content | **Offline — showing what's on this device** |
| `sources.state.unreachable` / `sources_state_unreachable` | Unreachable | **Not answering** |
| **`publication` — 26 iOS keys, 34 Android** | "Keep %lld publications on this device?", "This publication has no pages StoryArc can show.", "Where you stopped in every publication." | **book** where reflowable, **comic** where fixed-layout, a bare count otherwise. Both apps already branch on `publication.format` / `isFixedLayout`, so the plurals split per kind rather than flattening to "item". **This is the largest single rename in the pass.** |

**One state, one name.** *Offline — showing cached content* (library chip),
*Unreachable* (Settings row) and *Not answering* (full screen) are three phrasings
of one state. **"Not answering" everywhere.**

### Tier B — setup and source screens. Soften, keep the precision.

| Key | Today | Replacement |
| --- | --- | --- |
| `catalogue.address.hint` | …anything else that speaks OPDS. | **Works with Calibre-Web, Komga, Kavita, Ubooquity and most other library servers.** |
| `catalogue.signIn.stored` | Stored in the device keychain / keystore… | **Kept in this device's secure storage. Never in a backup or a log.** |
| `kavita.key.hint` | From your Kavita account settings. Stored in the device keychain. | **Copy it from your Kavita account settings. It is kept in this device's secure storage.** |
| `sources.action.reconnect` | Re-enter credentials | **Sign in again** |
| `source.unauthorized.body` | This device no longer holds the key for %@… | **StoryArc has lost its sign-in for %@. Open it in Settings and sign in again.** |
| `sources.detail.lastSync` | Last successful sync | **Last updated** |
| `settings.sources` | Sources | **Your libraries** |
| `sources.action.clearCache`, `privacy.clear.cache` | Clear cache | **Free up space** |
| `privacy.cache.note` | Decoded pages and web-view data. Rebuilt as you read. | **Pages StoryArc kept ready so they open fast. Rebuilt as you read.** |
| `downloads.limit` | Most disk to use | **How much space to use** |
| `catalogue.error.http` | The server answered %1$d %2$@. | **The server refused: %1$d %2$@.** — plain words first, keep the code |

### Tier C — leave exactly as it is

`smb.host.label`, `smb.share.label`, `smb.host.hint` (`\\server\share`),
`smb.error.smb1` and `smb.error.encryption` (they name the NAS setting to change),
`catalogue.untrusted.fingerprint` and the certificate copy, `kavita.key.label`,
`kavita.error.tooOld`, `sources.detail.lastError`, the diagnostic export, and
`reader.pageUnavailable.codec` — the codec name is the only thing that makes the
bug reportable. Vagueness here makes a problem unfixable.

### Also in the readers

`theme.pageTurn.reflowable` "Not available yet for text that reflows: it needs a
picture of the page" → **"Not available for books whose text resizes."** ·
`reading.defaults.fixed` "Comics and fixed pages" → **"Comics and picture books"** ·
`reader.spreads.offset` "Shift the pairing by one" → **"Line up the two-page view
differently"** · `theme.axis.value.em` "%@ em" → a plain multiple; *em* is
typesetter's jargon on a reader-facing slider · `theme.pageColour.ratio` "Contrast
%@ to 1" → keep the fact, drop the arithmetic: **"Easy to read" / "Harder to read
than the built-in themes" / "Too hard to read — the text and the page are too close
in colour."** · `reader.pdf.tab.marks` "Marks" → **"Highlights"**, since the same
objects are called *Notes* elsewhere in the module.

---

## 6. How the library types become one library

**The single most important item, so it gets a mechanism, not a principle.**

The reference apps all agree, and the one that disagrees is the most
engineer-facing of them. Panels — the owner's own reference — supports every
transport StoryArc does and puts **none** of them in the navigation: *"A Panels
library is just a folder"*, and an OPDS feed is navigated *"as if it was on your
own device"*. Infuse connects over SMB, NFS, FTP, WebDAV, Emby, Jellyfin and Plex,
then presents one library. Mihon organises by user category, Apple Books by
collection, Komga by series and collection. Only YACReader makes local-vs-remote a
navigation split, and it reads as a limitation.

### 6.1 The one structural change

**Delete `SidebarDestination.source(id)` and `SidebarDestination.OneSource` from the
primary navigation on both platforms.** As long as each server is a place a reader
can *go*, no amount of copy editing will make the library feel like one library.

Everything else follows from that.

### 6.2 The honest hard part, and the rule that resolves it

Local publications are rows in a store. An OPDS catalogue, a Kavita server and an
SMB share are **remote trees you walk**. You cannot merge a 4 000-entry remote
catalogue into one local grid without caching its metadata, and pretending
otherwise produces either a lie or a hang. So the seam is resolved by a **three-tier
rule**, not by flattening:

| Tier | What it is | Where it appears |
| --- | --- | --- |
| **Known** | Anything the app holds metadata for: local files, scanned share entries, cached catalogue entries, Kavita series the reader has opened. | **The one Library grid.** Ranked together, sorted together, filtered together. Origin invisible. Availability marked. |
| **Reachable** | The rest of a remote catalogue — everything the server has that the app has not cached. | **Search results, and a "More from *Home NAS* ›" row at the foot of a filtered library view.** Rendered by the *same* cover grid, the *same* cells, into the *same* detail screen. Never a destination in the navigation. |
| **Configuration** | Connections, credentials, certificates, scan state, per-source cache, the coloured connection dots. | **Settings → Your libraries.** Nowhere else. |

That is buildable against the stores that exist today, and it is what "seamless
across every library type" actually means in code.

### 6.3 The nine consequences

1. **The scope axis changes from origin to availability.** *Everywhere* / *On this
   device* replaces *Source* / *All sources*. Kindle filters on "is it on this
   device", not on which server it came from, because that is the question a reader
   has. Source-scoping survives as a `From …` chip inside the filter sheet, exactly
   as the `library-browsing` spec's own open question proposes.
2. **The publication detail screen is the seam.** It is the one screen that can
   present a local file, an OPDS entry, a Kavita chapter and an SMB file
   *identically*, and it is the only place in the browse path that names origin —
   one `footnote` line at the bottom.
3. **`CatalogueStrip` is deleted from the library** on both platforms. Server chips
   above the shelf are the plumbing wearing the shelf's clothes.
4. **The source line under a cover is deleted.** A reader with a folder and a Kavita
   server should not see the word *Kavita* under half their library. Badge budget on
   a 2:3 cover is two: the progress rail and the downloaded mark. Neither is origin.
5. **The Continue rows are assembled from the local progress store alone**, and
   never wait on a server. This is Plex's documented failure — watched state syncs
   across servers but the Continue Watching row itself does not, so home becomes a
   union of libraries and a *fragment* of progress. `LibraryModel.continueReading`
   already looks like it does the right thing; **protect that property explicitly
   and test it with every source unreachable.**
6. **Split Keep reading from Up next.** Two hubs, two semantics: *where you stopped*
   and *the next unread issue of a series you started*. Komga ships both; Mihon
   conflated them and has been arguing about it in its issue tracker for years.
   Both are view-model projections over `Publication.series`, which already exists
   on both platforms — no store change.
7. **An unavailable publication dims; it never disappears.** A shelf that shrinks
   when the Wi-Fi drops reads as data loss to a non-technical reader. `SourceList`
   already dims a row at `opacity(0.55)`; that treatment moves to the grid cell.
8. **Reading lists are origin-blind by definition.** Komga's read lists *"can include
   books from any library and any series"* — "playlists for books". A crossover
   reading order walking three series from two servers and a local folder is the
   normal case, not an edge case.
9. **The offline freshness ladder stays and gets finished.** `CachedNotice` is
   already the right pattern and is already dead on iOS (§2.5) — wire it. Keep
   `status/offline` neutral. Keep `retryUnreachableSources` on the library task, so
   a reader whose Wi-Fi came back while they were looking at the shelf does not
   watch it stay grey. One recovery affordance ("Try again"), and the diagnostics
   panel goes to Settings.

### 6.4 What does *not* change

The data layer. `Source`, `SourceKind`, the scan, the credential store, the
certificate pinning, the Kavita client, the SMB client, `ProgressStore` — none of
it moves. This is a presentation change with two additions: an availability
projection for the scope filter, and a provenance string on one screen. That is the
reason this revamp is large but not dangerous.

---

## 7. What this costs

**Be honest about the scale: this is a ground-up rework of the presentation layer
of two apps.** 64 Swift files in `LibraryFeature`, 52 Kotlin files in
`feature/library`, plus both readers, both settings modules and both shells. Two
files (`MainActivity.kt`, `LibraryScreen.kt`) are already over the project's
800-line cap and must be split, which is precisely where parallel agents collide —
so **one owner per file, always**, and the file set of each slice below is
disjoint from every other slice in the same wave.

### 7.0 Gate: specifications, before any code

[AGENTS.md §3](../../AGENTS.md): every behaviour is specified before it is built.
`grep` finds no mention of a tab bar anywhere in `docs/openspec/specs/` — only one
passing reference in `docs/design.md`. The following are **unspecified today** and
need `/opsx:propose` first:

1. **One library, three destinations** — the shell, Home, Downloads as a
   destination, and the availability scope axis. One proposal; it is one idea.
2. **Publication detail** — the screen, and cover-derived accent reaching the
   library.
3. **Read-aloud outliving the reader** — only if the owner wants the docked
   transport (§8.2). Separate proposal; it is a capability change, not layout.

### 7.1 The slices

Size is effort, not danger; **Risk** is danger.

| # | Slice | Platform | Files | Size | Risk |
| --- | --- | --- | --- | --- | --- |
| **A** | **Vocabulary pass** — §5 Tier A + B values, plus the `publication` rename | both | 5 `.xcstrings` + 20 `strings.xml` only | L | **Med** — the build fails on any missing locale, so this is atomic or it is broken |
| **B1** | Cover truth: radius 4, letterbox on `surfaceSunken`, size-class widths, downloaded mark | iOS | `CoverCell.swift`, `CoverGrid.swift` | S | Low |
| **B2** | Same, plus `MaterialTheme.shapes` wiring, `Typography.kt` Material scale, the colour rule, drop the hairline and the scroll-jump | Android | `CoverGrid.kt`, `Theme.kt`, `Typography.kt` | M | Low |
| **B3** | Cover image pipeline: a real image loader, memory/disk tiers, crossfade, placeholder | Android | `CoverGrid.kt` *(sequence after B2 — same file)* | S | Low |
| **C** | **Navigation rewrite**: `MainActivity` boolean cascade → typed graph + `NavigationSuiteScaffold`; add `material3-adaptive` 1.3.0; bump material3 alpha | Android | `MainActivity.kt`, `libs.versions.toml`, `build.gradle.kts` | **XL** | **High** — blocks E2/F2/K2 |
| **D** | **Shell**: `TabView` + `Tab(role: .search)` + `.sidebarAdaptable` + minimize behaviour; Settings and Add-books leave the toolbar | iOS | `StoryArcApp.swift`, new `AppShell.swift`, `LibraryToolbar.swift` | M | Med — blocks E1/F1/K1 |
| **E1/E2** | **Home** | each | new files | M each | Low |
| **F1/F2** | **Publication detail** + cover-derived accent | each | new files | M each | Low — highest product value after the shell |
| **G1/G2** | Library rework: sections, availability scope, toolbar grouping, wire the four dead iOS views | each | `LibraryView`/`LibraryStates`/`LibraryBrowsingControls`; split `LibraryScreen.kt` | L each | Med |
| **H1/H2** | Search surface: one search across local + remote, late remote results | each | new + `LibraryView`/`LibraryScreen` *(sequence after G)* | M each | Med — the remote-latency behaviour is the interesting part |
| **I1/I2** | Downloads becomes a destination; content leaves Settings | each | `DownloadsSettings.swift` / `DownloadsGroup.kt` + new | S–M | Low |
| **J1/J2** | Shelves: covers, Komga metaphor, demote promote-to-server | each | `ShelvesView`/`ShelfDetail`, `ShelvesScreen`/`ShelfDetailScreen` | M each | Low |
| **K1** | iPad: `backgroundExtensionEffect`, sidebar sections, edge-touching shelves, `maxContentWidth` | iOS | `LibrarySidebar.swift` + detail/Home | M | Med |
| **K2** | Five breakpoints, `WideNavigationRail`, `NavigableListDetailPaneScaffold`, `SupportingPaneScaffold` | Android | `WindowClass.kt`, `LibraryRail.kt` + panes | L | Med |
| **L1** | Reader chrome: `ToolbarSpacer` grouping, `glassEffectID` morphs, stable accessible name for the transition menu | iOS | `ReaderChrome.swift` | S | Low |
| **L2** | Reader chrome: ~10 hand-rolled `IconButton { Surface }` → `HorizontalFloatingToolbar` | Android | `ReaderScreen.kt` | M | Low |
| **M1/M2** | Empty states and first run | each | `LibraryStates.swift` / `LibraryScreen.kt` *(sequence after G)* | S | Low |

### 7.2 Waves that do not collide

- **Wave 0 (blocking):** the three spec proposals, and **fixing the screenshot path**
  (§7.5). Nothing can be declared done until the latter works.
- **Wave 1 — 4 agents, disjoint:** **A** (strings only) · **B1** (iOS cover) ·
  **B2** (Android theme/cover) · **L1 + L2** (reader chrome, untouched by everything
  else in the plan).
- **Wave 2 — 2 agents:** **C** (Android nav, alone — it owns `MainActivity.kt`) ·
  **D** (iOS shell). B3 tails B2.
- **Wave 3 — 6 agents:** **E1 E2 F1 F2 I1 I2 J1 J2** — all new files or narrow
  modules.
- **Wave 4 — 4 agents:** **G1 G2 K1 K2**.
- **Wave 5:** **H1 H2 M1 M2**.

### 7.3 The risky parts, named

1. **C, the Android navigation rewrite.** One 1168-line file, fourteen flags, a
   `BackHandler` per branch, and a rail selection re-derived from a race of
   nullables. It will not extend cleanly and it blocks three later slices. Give it
   one agent, alone, and land it before Wave 3.
2. **The material3 alpha pin.** Expressive APIs are only on the 1.5.0 alpha line
   (1.4.0 went stable 26 Aug 2026 without them, per the risk note already in
   `apps/android/README.md`). Bumping to a newer alpha for `ShortNavigationBar` /
   `WideNavigationRail` can break a build under other agents mid-wave. **One agent
   owns the version catalogue, in slice C, and nobody else touches it.**
3. **`MaterialShapes` and `LoadingIndicator` are still experimental.** One `@OptIn`
   in one file in `:core:designsystem`. If they are opted into across twenty call
   sites, an alpha bump becomes a twenty-file fix.
4. **The docked transport is a capability change, not a layout change.** Do not let
   it ride along inside D.
5. **The string pass is all-or-nothing.** 8 values per string, ~60 strings in Tiers
   A and B, plus the `publication` rename across 60 keys — and a build gate that
   fails on a missing locale. Land it as one commit-able unit.
6. **The contrast gate.** `pnpm tokens:check` covers 37 pairs across five ramps.
   The downloaded mark sits over artwork; if it needs a new token, it must clear the
   gate, and the gate is not negotiable — fix the token, never the floor.
7. **Rebase pain on the two oversized files.** `MainActivity.kt` and
   `LibraryScreen.kt` are split by slices C and G2. Any other agent touching them in
   the same wave will conflict badly. The wave table above keeps them apart; keep it
   that way.
8. **A design that adds glass everywhere fails.** Apple's ceiling is explicit and
   StoryArc already has device evidence of the failure mode in
   `ReadAloudBar.swift:16–20`. §3.0 is a budget, not a suggestion.

### 7.4 What is cheap and should be done regardless

Even if the owner redirects the whole direction: the four dead iOS views (§2.5) are
written, translated and live on Android — wiring them is cheaper than designing
anything; the four `design.md` violations in the cover cell (§2.2) are a small diff
with a large visual return and they close a documented spec-to-code drift; the
Android `MaterialTheme.shapes` wiring is one line; and the mislabelled Android empty
-state button (§4.8) is a genuine defect.

### 7.5 Visual proof — SETTLED, the capture path works

> **Correction, 2026-08-30, after this document was written.** Slice zero has been run and
> the blocker below is **false**. `xcrun simctl io booted screenshot` works: it captured the
> iPhone 17 Pro and the iPad Pro 13-inch, both already booted, writing 227 KB and 331 KB
> PNGs. They are committed at `docs/designs/screenshots/before-2026-08-30/`. The researcher
> was right about the distinction it drew — the MCP *attach* is what fails, and the capture
> path is a plain shell command that never needed it. So **every slice in §7.1 can be
> verified, and none of them may ship `partial` for want of a screenshot.**
>
> What the two captures show, which no amount of code reading had established:
> - **The iPhone has no tab bar at all** — only a floating Search pill. The Home / Library /
>   Downloads bar this document specifies is not a redesign of something, it is new.
> - **Cover titles render *behind* that pill.** "The Third Chapter / Fixture Manga #3" and
>   "Undeclared Direction" are legible through it. The grid has no bottom safe-area inset for
>   the floating bar. That is a live layout defect, not a taste question.
> - **Six unlabelled icon buttons** sit in a floating pill at the top of the phone, and seven
>   on the iPad. No labels, no grouping, no overflow — the single clearest example of the
>   "management surface stapled to the discovery surface" this document names in §1.
> - **`Attic NAS` is a primary navigation destination** on both, exactly as §6 predicted —
>   and it says *NAS* to a reader, which §5 has to fix.
> - **The iPad wastes most of its width**: phone-sized cells, eight of them, in a 13-inch
>   window, with no section structure and no use of the space.
>
> Android capture is still unproven — `adb devices` reports none attached, so an emulator has
> to be started before that half can be verified. That is a smaller slice zero, still owed.
>
> The rest of this section stands as written, for its reasoning about what proof means.


[AGENTS.md §6](../../AGENTS.md) is unambiguous: a change a user can see owes a
screenshot from a **booted simulator or emulator**, in light and dark, at default
and largest text size. A `#Preview` and a `@Preview` are not proof. There are two
exceptions and the handoff must name which applies — code behind a flag that
nothing renders yet, and a pure refactor whose screenshots are byte-identical.

**Neither exception covers this work.** Every slice in §7.1 changes something a
reader can see.

**The simulator control has refused to attach for the whole of this session.** The
consequence, stated plainly so nobody discovers it at the end:

- **No UI slice in this plan can be honestly marked complete until a capture path
  works.** They ship `partial`, with the blocker named — that is what §4 of the
  compass contract requires, and "we'll screenshot it later" is not a handoff.
- **The interactive panel and the capture path are not the same thing.** The
  MCP attach is what failed; `xcrun simctl boot` followed by
  `xcrun simctl io booted screenshot` is a plain shell command that does not need
  it, and `adb exec-out screencap -p` on Android is entirely independent of the iOS
  tooling. **Testing those two commands is the true slice zero** — before any spec
  proposal, because it decides whether this plan is executable at all.
- **The "before" set already exists.** `docs/designs/screenshots/` holds
  `ios-library-empty-{light,dark}.png`, `android-library-empty-{light,dark}.png`,
  the theme sheet at largest text size, and the diagnostic screens. Those are the
  comparison baseline; every slice adds its "after" beside them.
- If capture genuinely cannot be made to work, the honest options are to build
  behind a flag and accept a long unproven branch, or to stop. **Do not redefine the
  gate.**

---

## 8. What I am unsure about

Ordered by how much each would change the work.

1. **Does `Tab(role: .search)` morph into a search field, or only sit apart?** Apple
   documents the *separation* and the trailing placement; the *morph into a field on
   selection* is well attested in practice but I could not source it to Apple
   directly. It is the exact behaviour the owner described. **Settle it:** boot an
   iOS 26 simulator, build a four-tab shell, tap the search tab, screenshot. Thirty
   minutes — once §7.5 is fixed. If it does not morph, the fallback is
   `.searchable().searchToolbarBehavior(.minimize)`, which Apple *does* document as
   rendering the field as a button-like control when inactive. (Note: Apple's prose
   writes `.minimized`; the enum case is `.minimize`.)
2. **Does the owner want a docked transport at all, and of what?** The Apple Music
   screenshot shows a mini player. StoryArc's only transport is EPUB read-aloud,
   which today dies with the reader. A *continue reading* dock is a different
   product idea and might be better than either. **Settle it:** the owner picks one
   of three — reserve the slot and fill it later, propose read-aloud outliving the
   reader, or a continue-reading dock. Each is a different proposal.
3. **What fills Home on day three?** A library with two comics has no editorial. My
   proposal — hero carousel only when there are three or more in-progress items or
   at least one pinned list, otherwise a single large Keep-reading card, otherwise
   Home *is* the empty state — is a taste call I am making on the owner's behalf and
   would rather they made. **Settle it:** the owner looks at the three degradations.
4. **Is the third tab called *Downloads* or *On this device*?** They are different
   promises: the queue, or everything readable offline. I chose the latter with the
   queue pinned inside it, because it is what a reader wants before a flight — but
   it makes the tab's name wrong. **Settle it:** the owner picks the name; the
   design does not otherwise change.
5. **Is series grouping in scope?** Plotra's series rows ("4 albums", a read tick)
   and Komga's series/collection split are the strongest organising patterns the
   research found, and StoryArc's grid has no series concept at all.
   `Publication.series: String?` already exists on both platforms, so grouping is a
   view-model projection — but *series detail as its own screen* is a second detail
   screen and a real increment. **Settle it:** the owner says whether "Up next" and
   section headers are enough for now, or whether a series screen is wanted.
6. **Does the owner accept Android chrome getting Material's type scale?** It is the
   right call (§4.6) and it makes the two platforms' screenshots differ more than
   they do today — a 57 sp Android display beside a 34 pt iOS one. That is
   nativeness, and the brief asks for it, but it is visible and it contradicts an
   implication in `design.md`, so it should be an explicit yes.
7. **Does source-scoping survive at all?** I kept it as a `From …` chip in the filter
   sheet. It might be dead weight the moment availability is the primary axis, and
   deleting it is cheaper than keeping it. **Settle it:** the owner decides after
   seeing the filter sheet.
8. **What is the state of the agent-compass changes from the skills slice?** Four
   SwiftUI skills were installed into a worktree, and the registry edits that make
   them refreshable live **uncommitted in a separate repository**
   (`/Users/me-cedric/Documents/Projects/agent-compass`), with StoryArc's submodule
   pointer still predating them. The installed skills work regardless; the tracking
   does not. **Settle it:** the owner commits agent-compass and bumps the submodule,
   or says to drop the tracking.
9. **panels.app's own screens were only partially observable.** Its marketing site
   is thin on UI structure and its guides carry exactly one page on organising
   content. What this document takes from Panels is its *vocabulary* and its
   *refusal to navigate by transport*, both well sourced. If the owner likes
   something specific about how Panels looks that is not in here, it did not survive
   the fetch and should be described rather than assumed.

---

## Sources

**Apple.** [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass) ·
[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) ·
[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) ·
[Landmarks: background extension effect](https://developer.apple.com/documentation/swiftui/landmarks-applying-a-background-extension-effect) ·
[Landmarks: horizontal scrolling under a sidebar](https://developer.apple.com/documentation/swiftui/landmarks-extending-horizontal-scrolling-under-a-sidebar-or-inspector) ·
[Landmarks: refining glass in toolbars](https://developer.apple.com/documentation/swiftui/landmarks-refining-the-system-provided-glass-effect-in-toolbars) ·
[TabRole.search](https://developer.apple.com/documentation/swiftui/tabrole/search) ·
[tabViewBottomAccessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) ·
[tabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)) ·
[TabViewStyle.sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable) ·
[searchToolbarBehavior](https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)) ·
[ScrollEdgeEffectStyle](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle) ·
[containerRelativeFrame](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:alignment:)) ·
[ScrollTargetBehavior.paging](https://developer.apple.com/documentation/swiftui/scrolltargetbehavior/paging) ·
HIG [Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars),
[Searching](https://developer.apple.com/design/human-interface-guidelines/searching),
[Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) ·
WWDC25 [323](https://developer.apple.com/videos/play/wwdc2025/323/),
[356](https://developer.apple.com/videos/play/wwdc2025/356/),
[208](https://developer.apple.com/videos/play/wwdc2025/208/) ·
WWDC26 [269](https://developer.apple.com/videos/play/wwdc2026/269/),
[292](https://developer.apple.com/videos/play/wwdc2026/292/) ·
[Newsroom, June 2025](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/) ·
[Apple Books redesign, 2018](https://www.apple.com/newsroom/2018/06/apple-books-all-new-for-iphone-and-ipad-celebrates-reading/)

**Google / Material.** [Building with M3 Expressive](https://m3.material.io/blog/building-with-m3-expressive) ·
[M3 Expressive motion theming](https://m3.material.io/blog/m3-expressive-motion-theming) ·
[Breakpoints](https://m3.material.io/foundations/layout/applying-layout/window-size-classes) ·
[Navigation bar](https://m3.material.io/components/navigation-bar/guidelines) ·
[Navigation rail](https://m3.material.io/components/navigation-rail/guidelines) ·
[Search](https://m3.material.io/components/search/guidelines) ·
[Empty states (Material 1 — no M3 equivalent)](https://m1.material.io/patterns/empty-states.html) ·
[compose-material3 release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3) ·
[compose-material3-adaptive release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3-adaptive) ·
[Build adaptive navigation](https://developer.android.com/develop/adaptive-apps/guides/build-adaptive-navigation) ·
[List-detail layouts](https://developer.android.com/develop/ui/compose/layouts/adaptive/list-detail) ·
[Predictive back](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture) ·
[ShortNavigationBar](https://developer.android.com/reference/kotlin/androidx/compose/material3/ShortNavigationBar.composable) ·
[MaterialShapes](https://developer.android.com/reference/kotlin/androidx/compose/material3/MaterialShapes)

**Comparable apps.** [panels.app](https://www.panels.app/) ·
[Panels guides](https://guides.panels.app/) ·
[Panels: multiple libraries](https://raw.githubusercontent.com/Produkt/panels-guides/main/docs/organize-content/multiple-libraries.md) ·
[Panels: library FAQs](https://raw.githubusercontent.com/Produkt/panels-guides/main/docs/FAQs/library-faqs.md) ·
[Plotra on Google Play](https://play.google.com/store/apps/details?id=com.plotra.app) ·
[Komga read lists](https://komga.org/docs/guides/readlists/) ·
[Komga #131 — On Deck vs Keep Reading](https://github.com/gotson/komga/issues/131) ·
[Kavita customization](https://wiki.kavitareader.com/guides/features/customization/) ·
[KMReader](https://kmreader.everpcpc.com/) ·
[Mihon library FAQ](https://mihon.app/docs/faq/library) ·
[Mihon #698](https://github.com/mihonapp/mihon/issues/698),
[#2774](https://github.com/mihonapp/mihon/issues/2774) ·
[YACReader for Android](https://android.yacreader.com/user-guide/) ·
[Infuse](https://firecore.com/infuse) ·
[Plex: Continue Watching across servers](https://forums.plex.tv/t/continue-watching-across-multiple-servers/940594) ·
[Kindle library filters](https://www.idownloadblog.com/2021/01/18/sort-filter-manage-kindle-paperwhite-library/)

**Offline patterns.** [LeanCode](https://leancode.co/blog/offline-mobile-app-design) ·
[Android offline-first](https://developer.android.com/topic/architecture/data-layer/offline-first)

**This repository.** `AGENTS.md` · `docs/design.md` ·
`docs/openspec/specs/{native-experience,library-browsing,localization,collections-and-reading-lists}/spec.md` ·
`docs/decisions/0003-platform-floors.md` · `packages/design-tokens/tokens/*.json` ·
the iOS `LibraryFeature`, `ReaderFeature`, `EpubReaderFeature` and `SettingsFeature`
sources · the Android `app`, `feature/library`, `feature/reader`,
`feature/epubreader`, `feature/settings` and `core/designsystem` modules · all five
`Localizable.xcstrings` and all twenty `strings.xml`.
