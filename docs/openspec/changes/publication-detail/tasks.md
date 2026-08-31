# Tasks

Slices **F1** and **F2** of
[`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md) §7.1,
plus the colour wiring neither of them names as work because it looks like it is
already done.

**Every task that changes a screen owes a screenshot from a booted simulator or
emulator** — light and dark, default and largest text size — per
[AGENTS.md §6](../../../../AGENTS.md). Previews are not proof.

**Ordering:** on Android, Phase 2 onwards depends on the navigation graph from
`one-library-three-destinations`. On iOS there is no such dependency; the screen
can be pushed onto the existing stack.

## Phase 0 — Answer before building

- [ ] **0.1** Confirm a cover thumbnail is available to sample at the moment the
      page is composed, on both platforms, for each of the four source types.
      Deliverable: the answer, and if it is "not always", the placeholder-then-adopt
      behaviour the delta requires, with no visible flash.
- [ ] **0.2** Decide where the Android accent slot lives — a composition local
      beside the palette, matching the shape of the iOS environment modifier — and
      confirm it composes with the dynamic-colour scheme without tinting chrome.
      Deliverable: the slot, with a test that chrome colour is unchanged when an
      accent is set.

## Phase 1 — The colour reaches the library half of the app

- [ ] **1.1** iOS: call `CoverAccent` from the library half and put the result in
      `Theme.coverAccent`, which has had a slot and no caller since it was written.
- [ ] **1.2** Android: the slot from 0.2, plus the caller.
- [ ] **1.3** Host tests, mirrored case for case per the project's rule for
      mirrored code: a colour that clears the floor, one that must be adjusted to
      clear it, a monochrome cover that yields nothing, and an undecodable cover.
      Both platforms assert the same answers.
- [ ] **1.4** Screenshot the wash under increased contrast and reduced
      transparency, where the delta requires a plain surface rather than a softened
      one.

## Phase 2 — The screen

- [ ] **2.1** **[F1]** iOS: the page — cover over the wash, title block, one
      primary action, secondary actions in a menu, description, series shelf,
      provenance line. Screenshot: a downloaded local publication, a cached remote
      one, and one whose source is unreachable.
- [ ] **2.2** **[F2]** Android: the same content model with Material
      composition. Same three screenshots.
- [x] **2.3** Every cover on every surface leads here; every resume affordance
      still opens the book directly. Screenshot the two paths from the home
      surface.

      **Routed on both platforms. The screenshots are still owed.**

      The page was finished, translated and screenshotted a wave ago and reachable
      from nothing. On iOS `publicationDetail(model:onOpen:onGone:)` had no call
      sites, so the only `PublicationRoute` push in the app was the series shelf *on
      the page*; on Android `Screen.PublicationPage` was pushed only from that same
      shelf. Commit `82ad1d92` had reverted the iOS wiring to avoid a same-wave file
      conflict and said "one line attaches it". It is that line, at six navigation
      stacks, plus the cells that had to stop opening the reader — and its mirror in
      `AppHost.openPage` beside `AppHost.open`.

      Both halves of the rule are kept, and every site was judged rather than swept:

      - **Covers, and they lead here.** iOS: `CoverCell` (the library grid, the
        sectioned shelf, every *see all*, a collection's grid), `ListRow`,
        `HomeShelfCard` (Up next, Recently added, Finished), `OnDeviceShelf`, and a
        search result for a publication the device already holds — which is a cover
        written as a line, and search is named in the delta. Android: the same set,
        plus the reading-list rows and the page's own series shelf, which now goes
        through `openPage` so the never-push-the-page-you-are-on guard applies to it
        too.
      - **A resume affordance, and it still opens the book.** iOS: `HomeHero`, which
        is *Keep reading*. `home-screen` requires it to open "without an intermediate
        screen", and a reader who taps a card stating how much is left has decided.
        Its *heading* still leads to `HomeMore` — the library's own grid over the
        same set, which `home-screen` words as "the full list in the library" — so
        the covers there behave like every other cover in that grid. The affordance
        is the hero, not the set of publications behind it. Android keeps the same
        two verbs, and adds three more callers of the resume one: the reader's
        next-in-series offer, a launcher quick action, and a file the system hands
        over — each a reader asking to read rather than to look.
      - **Neither, and they keep opening the reader.** `CatalogueDetailView`,
        `KavitaChapterList` and `SmbBrowserView`, and their Android counterparts. A
        remote catalogue entry, a server chapter and a file on a share are not
        publications the library holds: each is fetched and indexed *on the tap*, and
        this page resolves a route against the library's own set, so routing them
        here would show the "it is gone" sentence every time. They are also already
        past the question the page answers — the reader is standing in the library
        they chose, looking at the thing they asked for. **The page cannot serve
        those three until a catalogue entry can become a `Publication` before it is
        fetched**, which is not this change. They keep the detail screens
        `opds-catalog` and `kavita-server` already give them.

      Two things the rule forced, one per platform. iOS: `ContinueReadingRow` is
      deleted — the grid's own resume affordance had moved to Home's hero long ago
      and every caller had been passing it an empty array since, so it was already
      dead, and would otherwise have become the one cover on the browse path still
      opening the reader. Android kept its equivalent row, which is now a
      cross-platform difference recorded at the site: the requirement moved whole
      into `home-screen`, iOS passes its library an empty list, and removing
      Android's needs its own screenshots.

      Android also took the `isOpenable` gate off covers: the page explains a
      refusal through `PrimaryAction.REFUSED`, so a cover with no way in was the one
      hole left in "reachable from every surface".

      **A spec conflict this surfaced, for whoever syncs the delta.**
      `reading-progress`'s *Continue from the library* says a tap on a part-read
      publication "opens at the stored position without an intermediate screen", and
      its *Restart deliberately* says the restart is on the long-press menu "rather
      than on a publication detail screen, because the library opens a publication
      when its cover is tapped". Both sentences describe the behaviour this task
      replaces, and the delta does not list `reading-progress` as MODIFIED. The
      proposal is explicit that the two entry verbs are deliberate, so the code
      follows the delta — but that spec now contradicts the shipped app and wants
      amending rather than being left to be discovered.
- [ ] **2.4** The page for a publication with no series, no year, no description
      and no cover — the composition has to hold up with a title and a placeholder.
      Screenshot both platforms.

## Phase 3 — Provenance and the seam

- [ ] **3.1** The provenance projection: the source's user-given name plus the
      availability answer, computed with no network call.
- [ ] **3.2** The same-publication-in-two-places case: the line names the copy
      this page will open and says another exists. Test with one publication
      present locally and on a server.
- [ ] **3.3** The removed-source case: the download survives, the line says "on
      this device", and no removed library is named. Test, not inspection — this
      is the case that will silently render a stale name.
- [x] **3.4** Confirm by inspection of the browse path that origin appears
      nowhere else: home, library, on-device destination, search, shelves. This is
      the seam's only test and it is a `grep` plus four screenshots.

      **Grepped on iOS. The four screenshots are owed** and are named in the
      handoff.

      Two findings, and only one of them was a leak.

      *The leak was already dead code.* `LibraryModel.sourceName(of:)` answers
      "which source is this publication from", which is the question no browse
      surface may ask. The grid stopped calling it, then the list did, then the
      spoken labels did, and it was left behind as public API with a doc comment
      describing "the callers that remain" — of which there were none. It is
      removed rather than left as an invitation to put the line back. Nothing else
      on home, the library, the on-device destination or search names a
      publication's origin: the four cell types and both spoken labels were read,
      and each already says so in a comment.

      *The shelves card is not the same fact and stays.* `ShelvesView` draws
      `"<source> · N items"` under a collection, and that names which server
      **defines the collection**, not where a publication came from.
      `collections-and-reading-lists` requires it in as many words — server-defined
      and local collections are presented "in the same places, distinguished by a
      source label rather than segregated into separate sections", and "each
      labelled with its source". Removing it would break a scenario in the main
      specs to satisfy a clause in a delta that is about publications. The two
      facts share a word and nothing else.
- [ ] **3.5** No new user-facing string ships from this change. If the provenance
      line needs one, hand it to the vocabulary slice rather than adding it here.

## Phase 4 — Large screens

- [ ] **4.1** iPad: the page as the split's detail column, with the hero art
      carrying under the floating sidebar. Screenshot portrait, landscape and Split
      View.
- [ ] **4.2** Android: the detail pane, with predictive back animated by the
      scaffold. Screenshot expanded width, and the narrow-then-widen path.
- [x] **4.3** The empty second pane before a publication is chosen — one
      sentence, not an arbitrary publication. Screenshot both platforms.
      *Done on Android; the screenshot is outstanding.* Android had a third
      answer to this — hide the pane until something goes in it — and it is out.
      The scaffold gave the whole width to the shelf, so the shelf reflowed its
      columns on the reader’s first tap and reflowed back on their last press of
      Back, which is the library rearranging itself in answer to something that
      was not about the library. §4.7 of the direction settles it from the other
      side: “expanded and above: two panes”, and a pane that is only sometimes
      there is not two panes. So the pane is always drawn at expanded width and
      `PublicationPanePlaceholder` puts `detail_pane_empty` in it — iOS’s
      sentence, to the word, in all four locales.

      **Answered on iOS, and the answer is that there is no second pane** — so
      there is nothing to screenshot, and the scenario is unmet rather than met.
      Android is separate and reports for itself.

      `PublicationDetailPlaceholder` existed, was translated into four languages
      and had no caller, which made it the third piece of dead code behind this
      change. It is deleted rather than wired, with its `detail.empty` string.

      The iOS shell is a `TabView` with `.tabViewStyle(.sidebarAdaptable)`, not a
      `NavigationSplitView` — `AppShell` and `LibraryView` both say why, and it is
      the same reason: the platform draws the same three destinations as a tab bar
      on a phone and as a sidebar on an iPad, and a split view inside one of them
      would be a second, disagreeing navigation. Every sidebar row is its own
      `NavigationStack` and a row is always selected, so the app never reaches a
      state where a pane is waiting for a publication to be chosen. A placeholder
      for an unreachable state is not a placeholder.

      This makes **4.1** the task that owes the sentence: whoever gives iOS a real
      split column writes it back with the pane it belongs to. Until then the
      delta's *pane before anything is chosen* scenario is not met on iOS, and this
      note is where that is written down.

## Phase 5 — Gates

- [ ] **5.1** `corepack pnpm spec:validate`.
- [ ] **5.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm build:ios`. The new screen must not put any Swift file over 400 lines —
      compose it from several.
- [ ] **5.3** Android: `./gradlew test lint`, 800-line cap.
- [ ] **5.4** `corepack pnpm lint`, which includes `tokens:check` — the derived
      colour has to clear the same contrast gate the palette does.
- [ ] **5.5** The screenshot set is complete and referenced in the handoff.
