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

**What a tick means here.** A task is ticked when the code and its host tests
have landed on **both** platforms, and when every capture the task names itself
exists under `docs/designs/screenshots/` with something on record saying what it
shows. A task whose code has landed and whose capture has not stays **unticked**
— its note says which capture is owed and what it has to prove. A task that asks
for something the change has since decided against is left unticked with the
decision cited, never ticked and never dropped. Six of twenty-three are ticked.

**Audited against `main` at `6c931e61`, 2026-08-31**, with `path:line` evidence
read from the source rather than from any note. Two ticks were **withdrawn** in
that audit — 2.3 and 3.4 — because reading the code found work each of them still
owes. What landed under them is kept in their notes; only the tick moved.

---

## ✅ Settled: the spec amendment this change needed is now declared

**Written 2026-08-31**, at
[`specs/reading-progress/spec.md`](specs/reading-progress/spec.md), with the
reasoning in the [proposal](proposal.md) under *Modified: `reading-progress`* so
it survives the sync that erases the delta. The banner below is kept as the
record of what was wrong, because the next reader of this file will want to know
why a third delta appeared late.

The delta listed `publication-detail` and `native-experience` as its specs. It
needed **`reading-progress` as MODIFIED as well**, and until that was written the
sync would have left two sentences in the main specs that the shipped app
contradicts:

- [`specs/reading-progress/spec.md:38-40`](../../specs/reading-progress/spec.md),
  *Continue from the library*: "**WHEN** a user taps a partially read
  publication / **THEN** it opens at the stored position without an intermediate
  screen." A tap on a cover now opens this page. The sentence describes the
  behaviour task 2.3 replaced.
- [`specs/reading-progress/spec.md:46`](../../specs/reading-progress/spec.md),
  *Restart deliberately*: the restart is on the long-press menu "rather than on a
  publication detail screen, **because the library opens a publication when its
  cover is tapped** and offers everything else on the long press." The
  justification is now false even though the placement it justifies is still
  right.

The [proposal](proposal.md) is explicit that the two entry verbs — a cover opens
the page, a resume affordance opens the book — are deliberate, so the **code
follows the delta and the delta is not in question**. What is missing is the
delta spec that says so. `reading-progress`'s *Resuming* requirement still holds
in full for the resume affordance; it is the two clauses above that were written
when a cover was the resume affordance. Whoever syncs should add a
`specs/reading-progress/` delta before merging, not discover this afterwards.

---

## Phase 0 — Answer before building

- [x] **0.1** Confirm a cover thumbnail is available to sample at the moment the
      page is composed, on both platforms, for each of the four source types.
      Deliverable: the answer, and if it is "not always", the placeholder-then-adopt
      behaviour the delta requires, with no visible flash.
      **Closed 2026-09-01. Both halves of the deliverable are in.** The four-source-type
      answer is now a table in `design.md` under *When a cover is available to sample*,
      replacing the paragraph that had it as an assumption — including the row the task did
      not anticipate: a publication in the library from OPDS, Kavita or SMB and **not
      downloaded** has no cover to sample ever, so the page is permanently washless and must
      be legible that way.
      **The iOS crossfade had already landed and this note had not caught up** — `a9a2f8d8`,
      *a cover's wash fades in instead of appearing*. `DetailBackground.swift` draws the
      gradient always and fades its opacity rather than holding it in an `if let`, because a
      view that is *inserted* has nothing to interpolate from, which was the cause of the hard
      cut. Reduced motion removes it rather than shortening it. Only the `design.md` half was
      outstanding today; the "iOS does not" below was true when written and stopped being
      true without the task being re-read.

      **The answer is "never synchronously, and for one class of publication never
      at all" — and it is written down nowhere.** On both platforms the cover is
      `nil` on first composition and arrives after: `PublicationDetailView.swift:33`
      with the `.task(id:)` at `:102-105`, and `PublicationDetailScreen.kt:117-121`.
      Both cover accessors hold a warm in-memory map but neither exposes a
      synchronous read, so even a cached cover misses the first frame.

      **The per-source-type answer is worse than the task assumed.** Both pipelines
      bottom out on a local file path — `LibraryLookups.swift:77`
      (`guard let url = locations[publication.id]`) and `LibraryViewModel.kt:1543` —
      and `locations` is written only when bytes are on the device: a download, an
      import, a folder scan or the watcher. So for an OPDS, Kavita or SMB
      publication that is in the library and **not downloaded**, the cover is not
      late, it never comes, and the page is permanently washless. That is the fact
      this task exists to record and `design.md:32-36` still states it as an
      assumption rather than an answer.

      **Placeholder-then-adopt: Android had it, iOS did not — as of `a9a2f8d8`, both do.**
      `DetailHero.kt:94-98` crossfades with `animateColorAsState`. iOS had no
      `withAnimation` or `.animation(` in any `Detail*.swift` file: the wash was assigned
      unanimated and drawn in a plain `ZStack`, so it arrived as a hard cut — the visible
      flash the task forbids in as many words. **This note is kept rather than deleted**
      because the *cause* is the reusable part: the gradient was inside an `if let`, and a view
      that is inserted has no previous value to animate from, so adding `.animation` to the old
      shape would have changed nothing and looked like a platform bug.
- [~] **0.2** Decide where the Android accent slot lives, and confirm it composes with the
      dynamic-colour scheme without tinting chrome.
      Deliverable: the slot, with a test that chrome colour is unchanged when an
      accent is set.
      **The decision is made and it is not the one the task assumed.** The task asked for "a
      composition local beside the palette, matching the shape of the iOS environment
      modifier". That clause is struck: the shipped parameter in
      `feature/library/…/DetailAccent.kt` is the right Compose answer, for the three reasons
      below. **The test is still owed** and is the only thing keeping this at a partial.

      **Neither half of the deliverable exists.** There is no composition local for
      the accent: `core/designsystem/…/theme/Theme.kt:139` declares
      `LocalStoryArcPalette`, `VolumeKeys.kt:31` declares `LocalVolumeTurns` and
      `back/PredictiveBack.kt:90` declares `LocalBackGesture`, and that is the
      complete census. What shipped instead is
      `feature/library/…/DetailAccent.kt:26-33` — an `internal data class`
      threaded by hand from `PublicationDetailScreen.kt:121` down through `:190`,
      `:266`, `:278` and `:281`. It works, it is `internal` to `:feature:library`,
      and it is therefore neither beside the palette nor the shape of iOS's
      environment modifier (`DesignSystem/Theme.swift:47-49`).

      **And there is no chrome test of any kind.**
      `feature/library/src/androidTest/` does not exist, so the screen has no
      Compose UI test at all; `DetailAccentTest.kt` runs 6 cases and every one is
      hex parsing or an extractor invariant — none reads
      `MaterialTheme.colorScheme`. The chrome/content separation is asserted only
      structurally, by `Theme.kt:178-182` and by the accent never entering the
      theme. That is an argument, and this task asks for a test.

      **Decided 2026-09-01: the parameter is the decision. The task is amended, not the
      code.** Three reasons, and the first is the one that settles it:

      - **A composition local is Compose's idiom for a value the whole tree may read** —
        theme, density, the back gesture, which is exactly the census above. The cover accent
        is read by one screen's own subtree. Putting it in `:core:designsystem` would mean the
        design system knows that an accent can be derived from artwork, which is a fact about
        a feature, not about the palette.
      - **The two platforms differ because their idioms differ, and ADR-0001 is why that is
        allowed.** SwiftUI's environment is how a parent hands a value to an arbitrarily deep
        subtree; the alternative there is threading it through every intervening initialiser,
        which is much worse. Compose's answer to the same problem *is* the parameter. Mirroring
        the SwiftUI shape into Compose would import an iOS structure with no Compose rule
        behind it — the thing ADR-0001 exists to stop.
      - **Material's own subtree mechanism would break the requirement.** Wrapping the page in
        `MaterialTheme(colorScheme = …)` is how Compose gives a subtree a different colour, and
        it would tint the chrome inside that subtree — which is the one thing this task's
        deliverable forbids. So the accent must travel *beside* the scheme rather than in it,
        and a parameter is what that looks like.

      **The test still stands and is the remaining work.** A Robolectric composition test in
      `feature/library/src/test/` — `GraphicsMode.NATIVE`, for `CompactPlayerTest`'s reason —
      that renders the screen with an accent set and asserts `MaterialTheme.colorScheme` is
      byte-identical to the same render with no accent. That is the assertion the structural
      argument was standing in for, and it belongs where the separation lives rather than in
      the design system.

## Phase 1 — The colour reaches the library half of the app

- [x] **1.1** iOS: call `CoverAccent` from the library half and put the result in
      `Theme.coverAccent`, which has had a slot and no caller since it was written.
      **Done, and the wiring is not inert.** `PublicationDetailView.swift:92` is the
      setter — `.coverAccent(wash.map { Color(hex: $0.tint) })` — and the value is
      read downstream through `theme.accent` at `DetailActions.swift:101` and `:110`,
      the two `.glassProminent` primary buttons inside the subtree the modifier
      wraps. The slot itself is `DesignSystem/Theme.swift:19`, with the fallback at
      `:21` and the modifier at `:47-49`, and `Tests/DesignSystemTests/PaletteTests.swift:73`
      (`coverAccentWins`) and `:66` (`fallsBackToBrand`) assert both directions.

      **One sentence in the code and one in `design.md` are wrong and should be
      corrected when this is synced.** `PublicationDetailView.swift:90-91` says
      "the reader's thumbnails were the only thing in the app that ever set it",
      and `design.md:22` says "Called from: the reader's thumbnails only". They
      never set it: `ReaderFeature/ReaderThumbnails.swift:78-79` calls
      `CoverAccent.pixels`/`derived` and assigns its own `coverColours` state, and
      `grep` finds no `.coverAccent(` anywhere in `ReaderFeature`. Before this
      change the property had **no setter at all**, which makes the task's own
      framing — a slot with no caller — more true than it claimed, not less.
- [ ] **1.2** Android: the slot from 0.2, plus the caller.
      **The caller shipped; the slot as specified did not.** The caller is
      `PublicationDetailScreen.kt:121` (`val accent = rememberDetailAccent(cover)`),
      feeding `DetailHero.kt:73`/`:94-101` for the wash and
      `PublicationDetailScreen.kt:351-352` for the primary button's container and
      content colours, with the extractor itself at `core/model/…/CoverAccent.kt:22`
      and the bridge at `DetailAccent.kt:83-91`.

      **What is missing is exactly what 0.2 is missing** — a composition local in
      `:core:designsystem` rather than a feature-internal data class passed through
      four call sites. This task cannot close before 0.2 decides; if 0.2 is amended
      to accept the parameter, this closes with it.
- [ ] **1.3** Host tests, mirrored case for case per the project's rule for
      mirrored code: a colour that clears the floor, one that must be adjusted to
      clear it, a monochrome cover that yields nothing, and an undecodable cover.
      Both platforms assert the same answers.

      **The extractor suites are very nearly mirrored. The feature-level suites are
      not mirrored at all, and one of the four named cases is untested on both.**
      `Tests/StoryArcCoreTests/CoverAccentTests.swift` holds 14 cases and
      `core/model/…/CoverAccentTest.kt` holds 13; 13 of them correspond one to one,
      and the odd one out is iOS's `samplesToTheGrid` — deliberately absent on
      Android, as `CoverAccent.kt:165` records ("the one part of this file no JVM
      unit test reaches").

      **What is missing:** the four named cases live at the *feature* level, and
      there the two platforms test different things. iOS
      `Tests/LibraryFeatureTests/DetailWashTests.swift` has all four —
      `:30` clears the floor, `:45` must be adjusted, `:60` monochrome yields
      nothing, `:68` no pixels yield nothing — because iOS computes a gradient tint
      and strength walked down until body text clears 4.5:1
      (`DetailWash.swift:58-75`). Android has **no `DetailWash` at all** — it uses
      `CoverAccent.wash` as a flat hero `Surface` colour (`DetailHero.kt:101`) — so
      `DetailAccentTest.kt`'s 6 cases are four hex-parsing tests plus the monochrome
      and clears-the-floor cases. There is no Android "must be adjusted" and no
      Android "undecodable" at feature level.

      **And neither platform tests a genuinely undecodable cover.** iOS's
      `noPixelsYieldNothing` passes `[]`, which is the downstream shape, not the
      `CoverAccent.pixels(of:) == nil` path at `CoverAccent.swift:220`; Android's
      zero-size-bitmap path at `CoverAccent.kt:169` is uncovered. Before this can
      be ticked the two suites have to assert the same answers about the same
      thing, which first means deciding whether Android should have a `DetailWash`.
- [ ] **1.4** Screenshot the wash under increased contrast and reduced
      transparency, where the delta requires a plain surface rather than a softened
      one.

      **iOS replaces rather than softens, and it covers both switches.**
      `DetailBackground.swift:25-26` reads `colorSchemeContrast` and
      `accessibilityReduceTransparency`, `:53` combines them into `isPlain`, and
      `:34` drops the gradient entirely so the canvas at `:33` stands alone — a
      replacement, which is what the delta asks for.

      **Android answers increased contrast only, and says why.**
      `DetailAccent.kt:84-87` returns `null` under `rememberHighContrast()`
      (`core/designsystem/…/theme/HighContrast.kt:47`), and `DetailHero.kt:95` falls
      back to `palette.surfaceSunken`. Reduced transparency has no branch, and
      `DetailAccent.kt:73-77` argues it cannot have one — "the platform ships
      contrast stops and no transparency switch". The delta asks for both at
      [`specs/publication-detail/spec.md:145-148`](specs/publication-detail/spec.md).
      That is a reasoned divergence rather than an oversight, and it wants writing
      into the delta rather than leaving in a code comment.

      **The captures are the reason this stays open.** Four files exist —
      `after-2026-08-30/ios-detail-iphone-contrast-{light,dark}-{top,foot}.png` —
      and **nothing in the repository says that "contrast" there means *increased*
      contrast.** That directory has no README, unlike its two siblings, and no
      markdown file mentions those filenames. Reduced transparency is captured
      nowhere on either platform (`find` for `*transp*` and `*reduce*` under
      `docs/designs/screenshots/` returns nothing), and Android's high-contrast
      branch has no capture at all.

## Phase 2 — The screen

- [ ] **2.1** **[F1]** iOS: the page — cover over the wash, title block, one
      primary action, secondary actions in a menu, description, series shelf,
      provenance line. Screenshot: a downloaded local publication, a cached remote
      one, and one whose source is unreachable.

      **All seven elements are built, and the "one primary" rule is kept
      structurally rather than by convention.** Cover over the wash:
      `PublicationDetailView.swift:59` over `:88`'s `DetailBackground`, with
      `DetailHero.swift:25-46` keeping the artwork itself untinted. Title block:
      `DetailHero.swift:93-136`. **One** primary: `DetailActions.swift:89-113` is a
      single `@ViewBuilder` with three mutually exclusive branches — nothing when
      the publication is refused, Read/Continue when a file exists, Download when
      one does not — so exactly one button can render, and its label promises the
      outcome (`:116-122`). Secondaries in a menu: `DetailActions.swift:126-172`,
      with the menu's download gated on `file != nil` and the primary's on
      `file == nil`, so the two never both appear. Description
      `PublicationDetailView.swift:120-129`, series shelf `:131-137` →
      `DetailSeriesShelf.swift:14-77`, provenance `:81` →
      `DetailProvenanceLine.swift:22-75`.

      **What is owed is the three captures this task names by state.**
      `after-2026-08-30/` holds ten iPhone detail captures and
      `after-2026-08-31/ios-detail-from-a-cover-dark.png` holds one more, but they
      vary appearance, text size, contrast and coverlessness — **none is on record
      as a downloaded local publication, a cached remote one, or one whose source
      is unreachable**, which are the three states the provenance line and the
      primary action actually branch on.
- [ ] **2.2** **[F2]** Android: the same content model with Material
      composition. Same three screenshots.

      **Built, seven for seven, and composed as Material rather than transcribed
      from iOS.** Cover over the wash: `DetailHero.kt:100-113`, the wash animated at
      `:94-98`. Title and subtitle ride the app bar —
      `PublicationDetailScreen.kt:150-152` hands `DetailTitle` (`DetailHero.kt:188`)
      and `DetailSubtitle` (`:208`) to a `LargeFlexibleTopAppBar`, which is the
      Material answer to iOS's in-content title block. One primary:
      `PublicationDetailScreen.kt:341-342`, drawn only when `press != null`.
      Overflow: `:162-176` → `DetailOverflowMenu` at `:378-427`. Description `:303`,
      series shelf `:196-203`, provenance `:311`.

      **Two defects found while reading, reported and not fixed here.**
      `detail_action_refused` ("Cannot be opened", `res/values/strings.xml:343`,
      translated four ways) is **unreachable**: it is produced only by
      `DetailActions.kt:76` inside `label()`, which is called only at
      `PublicationDetailScreen.kt:356` inside `if (press != null)`, and `press` is
      `null` exactly when the action is `REFUSED` (`:338`). A refused publication
      gets the explanation and no button, so the label can never render. Second:
      a `NEEDS_DOWNLOAD` publication shows **two controls for one action** — the
      primary at `:339` and the overflow entry at `:408-416`, both gated on the
      same non-null `onDownload`. iOS forbids this by construction
      (`DetailActions.swift:136`); Android does not.

      **The same three captures are owed as on iOS** — the four Android detail
      captures show phone light, phone dark, the overflow and the provenance-plus-series
      pairing, none of them keyed to those three states.
- [ ] **2.3** Every cover on every surface leads here; every resume affordance
      still opens the book directly. Screenshot the two paths from the home
      surface.

      **Routed on both platforms — this is the largest thing this change landed —
      but the tick is withdrawn: three covers still do not lead here on iOS, and
      the two captures are owed.**

      The page was finished, translated and screenshotted a wave ago and reachable
      from nothing. On iOS `publicationDetail(model:onOpen:onGone:)` had no call
      sites, so the only `PublicationRoute` push in the app was the series shelf *on
      the page*; on Android `Screen.PublicationPage` was pushed only from that same
      shelf. Commit `82ad1d92` had reverted the iOS wiring to avoid a same-wave file
      conflict and said "one line attaches it". It is that line, at six navigation
      stacks — `HomeScreen.swift:91`, `LibraryView.swift:231`,
      `DownloadsDestination.swift:106` and `LibrarySidebar.swift:122`, `:135`,
      `:154`, `:185` — plus the cells that had to stop opening the reader.

      Both halves of the rule are kept, and every site was judged rather than swept:

      - **Covers, and they lead here.** iOS: `CoverCell.swift:54`, `CoverList.swift:104`,
        `HomeRow.swift:120`, `OnDeviceShelf.swift:94`, `SearchResultsView.swift:107`
        and `SectionedShelf.swift:88` (which composes `CoverCell`). Android:
        `CoverGrid.kt:506`, `CoverList.kt:180`, `HomeScreen.kt:358`,
        `DownloadsDestination.kt:156`, `LibrarySearchBar.kt:339`,
        `ShelfDetailScreen.kt:127` and `:352`, and the page's own series shelf
        through `AppScreens.kt:237`, so the never-push-the-page-you-are-on guard
        (`AppNavigation.kt:85-90`) applies to it too.
      - **A resume affordance, and it still opens the book.** iOS: `HomeHero.swift:163`,
        which is *Keep reading*. `home-screen` requires it to open "without an
        intermediate screen", and a reader who taps a card stating how much is left
        has decided. Its *heading* still leads to `HomeMore` — the library's own grid
        over the same set — so the covers there behave like every other cover in that
        grid. The affordance is the hero, not the set of publications behind it.
        Android keeps the same verb at `HomeScreen.kt:210`/`:240`, and adds three
        more callers of it: the reader's next-in-series offer (`ReaderHost.kt:100`,
        `:111`), a launcher quick action (`AppIntents.kt:121`) and a file the system
        hands over (`AppIntents.kt:67`) — each a reader asking to read rather than to
        look.
      - **Neither, and they keep opening the reader.** `CatalogueDetailView.swift:155`,
        `KavitaChapterList.swift:338` and `SmbBrowserView.swift:142`/`:158`, and their
        Android counterparts at `AppScreens.kt:316`, `:83`, `:92`, with the reasoning
        at `AppScreens.kt:58-68`. A remote catalogue entry, a server chapter and a
        file on a share are not publications the library holds: each is fetched and
        indexed *on the tap*, and this page resolves a route against the library's
        own set, so routing them here would show the "it is gone" sentence every
        time. **The page cannot serve those three until a catalogue entry can become
        a `Publication` before it is fetched**, which is not this change.

      **Three iOS covers that still do not lead here, and the audit that found them
      is why this is unticked:**

      1. **A publication no decoder can open is not tappable at all on iOS.**
         `CoverCell.swift:53` and `CoverList.swift:103` still gate the
         `NavigationLink` on `publication.isOpenable`. Android **removed exactly
         this gate** — `CoverGrid.kt:489-497` says so in its own comment, and
         `CoverList.kt:179-184` matches — precisely because the page explains a
         refusal through `PrimaryAction.REFUSED`. So the two platforms now disagree
         about the one case the page was extended to cover.
      2. **A dimmed card on iOS Home leads nowhere.** `HomeRow.swift:119` gates on
         `isReadableNow`, documented at `:113-118`. It is still a cover that does
         not reach the page, and the page's whole purpose is to say why the thing
         cannot be opened.
      3. **iOS reading-list rows open the reader; Android's open the page.**
         `ShelfDetail.swift:199-201` against `AppScreens.kt:145`. The row has no
         progress, no cover and no *Continue* wording, so it is not a resume
         affordance under the rule's own definition.

      Two things the rule forced, one per platform. iOS: `ContinueReadingRow` is
      deleted — the grid's own resume affordance had moved to Home's hero long ago
      and every caller had been passing it an empty array since, so it was already
      dead; only the tombstone at `CoverGrid.swift:173` remains. Android kept its
      equivalent (`CoverGrid.kt:399`, called at `:267`), which is a cross-platform
      difference recorded at the site (`CoverGrid.kt:441-456`): the requirement moved
      whole into `home-screen`, iOS passes its library an empty list, and removing
      Android's needs its own screenshots.

      **One correction to the previous note.** It said the wiring's mirror was "in
      `AppHost.openPage` beside `AppHost.open`". `AppHost` is Android-only
      (`app/…/AppHost.kt:26`, `open` at `:47`, `openPage` at `:62`); iOS has no such
      type — its equivalent is the `PublicationRoute` destination
      (`PublicationRoute.swift:51`, `:76`) plus each surface's own `onOpen` closure.

      **The captures owed:** the two paths *from the home surface* — a cover on Home
      reaching the page, and Home's hero reaching the reader. What exists
      (`after-2026-08-31/{ios-detail-from-a-cover-dark,android-detail-from-a-cover-light}.png`)
      is the library shelf's path, not Home's.
- [ ] **2.4** The page for a publication with no series, no year, no description
      and no cover — the composition has to hold up with a title and a placeholder.
      Screenshot both platforms.

      **All four absences are handled on both platforms, each as an absence rather
      than a placeholder — and the Android capture says the composition does not
      hold up.** iOS: no cover `DetailHero.swift:68-83` (a `surfaceRaised` well with
      the format glyph, and the title stated underneath rather than scaled into the
      well); no series `:120`, whose rule at `SeriesLine.swift:28-33` also drops a
      series that merely repeats the title; no author or year `:127` guarded by
      `:146-151`; no description `PublicationDetailView.swift:122`; and the wash
      itself absent when there is no cover (`:172`). Android: `DetailHero.kt:152-172`,
      `:210-215` (`listOfNotNull` then an early return, so the app-bar subtitle slot
      is empty rather than blank-filled), `PublicationDetailScreen.kt:303`,
      `DetailSeriesShelf.kt:61`, and the wash falling back to `surfaceSunken` at
      `DetailHero.kt:95`.

      **The capture exists on both and Android's is a failure.**
      `after-2026-08-31/android-detail-from-a-cover-light.png` **is** this degenerate
      case, and that directory's README says so in as many words: the wash card
      fills most of the window with a format glyph in the middle and the action
      pinned to the foot, so roughly three fifths of the page is empty. "The
      composition has to hold up with a title and a placeholder" is the question
      this task asks, and on that evidence the answer is no. **That is a layout
      decision still owed, not a bug to patch**, which is why the task stays open
      with its code complete. iOS's own bare captures are
      `after-2026-08-30/ios-detail-iphone-bare-{light,dark}-{top,foot}.png` and
      `ios-detail-iphone-nocover-dark-{top,foot}.png`.

      No test on either platform asserts the four-absence composition.

      **One correction for whoever picks this up:** `CoverlessWell.swift` is *not*
      this page's coverless branch. `coverlessWellDrawsTitle(at:)`
      (`CoverlessWell.swift:37`) has two callers and both are browse surfaces —
      `CoverCell.swift:211` and `HomeArtwork.swift:76`. The page's branch is
      `DetailHero.swift:68-83`, and it never draws the title into the well.

## Phase 3 — Provenance and the seam

- [x] **3.1** The provenance projection: the source's user-given name plus the
      availability answer, computed with no network call.
      **Built, pure and tested to the same depth on both platforms.**
      `PublicationProvenance.swift:72` (`of(_:isOnDevice:hasFile:source:)`) takes a
      value, two `Bool`s and an in-memory `Source`; `PublicationProvenance.kt:66`
      (`provenanceOf`) is likewise non-suspending. Neither file contains a
      `URLSession`, an `await` or a `suspend`, and both call sites pass state that is
      already resident — `PublicationDetailView.swift:151-161` and
      `PublicationDetailScreen.kt:114-123`. The composition is place plus
      availability: `PublicationProvenance.swift:24-43` joined at
      `DetailProvenanceLine.swift:49-51`, and `PublicationProvenance.kt:114-133`.
      `PublicationProvenanceTests.swift` and `PublicationProvenanceTest.kt` hold
      **8 cases each**.

      **They are not mirrored, and the divergence is worth settling before sync.**
      Android returns `Place.DEVICE` for a `LOCAL_FOLDER` publication
      (`PublicationProvenance.kt:81-88`, asserted at `PublicationProvenanceTest.kt:54`),
      so a comic scanned from a picked folder reads *"On this device"*. iOS has no
      such branch — `isOnDevice` there means "inside the download store" only
      (`LibraryLookups.swift:44-52`) — so the same file falls through to
      `PublicationProvenance.swift:99-103` and reads *"From ‹folder name›, readable
      now"*. Both are defensible against the delta: a picked folder **is** "a named
      library the reader added", and it **is** also on this device. Neither suite
      asserts the other's answer. One reader, one file, two sentences: pick one and
      mirror it.
- [ ] **3.2** The same-publication-in-two-places case: the line names the copy
      this page will open and says another exists. Test with one publication
      present locally and on a server.

      **Implemented on both, but the two platforms compute "elsewhere" from
      different facts, and Android's test is not the one this task asks for.**
      iOS's `alsoIn` (`PublicationProvenance.swift:59`) is set **only** inside the
      `isOnDevice` branch at `:82-88` and is `nil` in every other
      (`:95`, `:96`, `:102`), so iOS's "second place" is always *the server this
      download came from* — it never looks in the library for a duplicate. Android's
      `isAlsoElsewhere` (`PublicationProvenance.kt:43`) is computed at `:73` by
      scanning the library for a same-`id`, different-`sourceId` publication.

      **What is missing:** iOS's `onDeviceNamesItsLibrary`
      (`PublicationProvenanceTests.swift:34-48`) is the case the task describes —
      a download plus its live source. Android's `theSameBookFromTwoSourcesSaysSo`
      (`PublicationProvenanceTest.kt:137-155`) builds **two server copies** with
      `isOnDevice = false`, so **no Android test covers "present locally and on a
      server"** at all. Add it, and decide which of the two definitions of
      "elsewhere" the delta means — they answer differently for a book downloaded
      from one server that also exists on a second.
- [x] **3.3** The removed-source case: the download survives, the line says "on
      this device", and no removed library is named. Test, not inspection — this
      is the case that will silently render a stale name.
      **Implemented and genuinely tested on both platforms.** iOS:
      `PublicationProvenance.swift:82-88` lets `isOnDevice` win unconditionally, and
      `alsoIn` comes from `source?.displayName`, which is `nil` for a removed source
      because the call site resolves through the registry
      (`PublicationDetailView.swift:159`). The test is
      `PublicationProvenanceTests.swift:52-64`, `removedSourceIsNotNamed` — the
      publication carries a `UUID()` the registry does not hold, and it asserts
      `.thisDevice`, `.offline` and `alsoIn == nil`. Android:
      `PublicationProvenance.kt:81-88` returns `DEVICE` with a null name when the
      source is absent, asserted by
      `PublicationProvenanceTest.kt:121-135`,
      `aRemovedSourceIsNotNamedAndTheCopyIsStillHere`. This is the one task in the
      phase that was closed the way it asked to be — with a test rather than a look.
- [ ] **3.4** Confirm by inspection of the browse path that origin appears
      nowhere else: home, library, on-device destination, search, shelves. This is
      the seam's only test and it is a `grep` plus four screenshots.

      **Grepped on iOS, and that was half the job. The tick is withdrawn: the same
      dead API iOS deleted is still on Android, and the four screenshots are still
      owed.**

      *The iOS half stands, and it was verified again.* `LibraryModel.sourceName(of:)`
      answered "which source is this publication from", which is the question no
      browse surface may ask. The grid stopped calling it, then the list did, then
      the spoken labels did, and it was left behind as public API with a doc comment
      describing "the callers that remain" — of which there were none. It is removed
      rather than left as an invitation to put the line back; only the tombstone at
      `LibraryLookups.swift:16-23` remains. Nothing on home, the library, the
      on-device destination or search names a publication's origin: `CoverCell.swift`,
      `CoverList.swift`, `HomeRow.swift`, `HomeArtwork.swift`, `HomeHero.swift`,
      `OnDeviceShelf.swift`, `SearchResultsView.swift` and `SectionedShelf.swift`
      carry no registry read at all, and every `displayName` in them is
      `publication.format.displayName`.

      ***The Android mirror was never removed.*** `LibraryViewModel.kt:1360` is
      `fun sourceName(publication: Publication): String?`, returning
      `_registry.value.nameOf(publication.sourceId)` — the forbidden question, in
      the same shape, with **zero callers**, and its doc comment at `:1355-1358`
      still quotes the *superseded* rule about showing a source when more than one
      is configured. Delete it as iOS's was deleted. Android's cells are otherwise
      clean: no source name reaches `CoverGrid.kt`, `CoverList.kt`, `HomeScreen.kt`,
      `HomeCards.kt`, `LibrarySearchBar.kt` or `DownloadsDestination.kt`, and the
      grid's spoken label says so at `CoverGrid.kt:516-521`. One borderline case,
      judged not a leak: `LibrarySearch.kt:140` names a **server that failed to
      answer a search**, surfaced at `LibrarySearchBar.kt:305-315` — that names a
      source that did not reply, not a publication's origin.

      *The shelves card is not the same fact and stays.* `ShelvesView.swift:374`
      draws `"‹source› · N items"` under a collection, and `ShelvesScreen.kt:413`
      does the same on Android; both name which server **defines the collection**,
      not where a publication came from. `collections-and-reading-lists` requires it
      in as many words — server-defined and local collections are presented "in the
      same places, distinguished by a source label rather than segregated into
      separate sections", and "each labelled with its source". Removing it would
      break a scenario in the main specs to satisfy a clause in a delta that is
      about publications. The two facts share a word and nothing else.

      **The four screenshots — home, library, on-device, search, with no origin on
      any of them — are named in an earlier handoff and are not in the tree.**
- [ ] **3.5** No new user-facing string ships from this change. If the provenance
      line needs one, hand it to the vocabulary slice rather than adding it here.

      **The constraint was violated, and it is recorded here rather than ticked or
      quietly dropped. Thirty-two new strings shipped: 11 on iOS and 21 on
      Android.** Every one is translated into de, es and fr as well as en, so
      nothing is broken and no reader sees an English fallback — but zero was the
      requirement and thirty-two is not zero.

      **iOS, 11 keys in `LibraryFeature/Resources/Localizable.xcstrings`:**
      `detail.availability.notAnswering`, `detail.availability.notHere`,
      `detail.availability.now`, `detail.availability.offline`,
      `detail.download.working`, `detail.gone`, `detail.more`,
      `detail.provenance.alsoIn %@`, `detail.provenance.unattributed`,
      `detail.series.title`, `detail.unavailable`. Commit `6de261f5` created eleven
      in a table of their own, `82ad1d92` added `detail.more`, and one —
      `detail.empty` — was later deleted with `PublicationDetailPlaceholder` under
      task 4.3; commit `7a6d3a6a` folded the table into `Localizable` because
      `pnpm strings:ios` reads one table per module.

      **Android, 21 keys at `feature/library/…/res/values/strings.xml:338-358`**,
      twenty of them added in one commit (`e3cff4ac`) in all four locales at once,
      plus `detail_pane_empty` from task 4.3.

      **Why the constraint was overtaken, honestly.** The page has states no
      existing string covers — four availability clauses, a refusal that has to
      explain itself, and a whole "this one is gone" screen — and the delta requires
      the line to say both where a publication lives and whether it can be opened
      now. The page *does* reuse where it can: iOS takes `source.onThisDevice`,
      `library.continueReading`, `catalogue.detail.read`, `catalogue.acquire.download`,
      `downloads.remove` and `library.cell.cannotOpen` from the vocabulary already
      there. **What the vocabulary slice should do is adopt these thirty-two rather
      than be handed a blank sheet** — and it should reconcile the two string
      models while it does, because they are not the same design: iOS composes two
      clauses with a comma (`DetailProvenanceLine.swift:49-51`, four availability
      clauses against three places) and Android ships four whole sentences plus a
      wrapper (`strings.xml:347-351`). One of the twenty-one is unreachable — see
      task 2.2.

## Phase 4 — Large screens

- [ ] **4.1** iPad: the page as the split's detail column, with the hero art
      carrying under the floating sidebar. Screenshot portrait, landscape and Split
      View.

      **The detail column does not exist and cannot, in the shell as it stands. The
      hero half is built.** There is no `NavigationSplitView` anywhere in
      `apps/ios` — the only two hits are comments explaining its absence
      (`PublicationRoute.swift:137`, `LibraryView.swift:19`). The shell is a
      `TabView` (`AppShell.swift:72`) with `.tabViewStyle(.sidebarAdaptable)`
      (`:118`), every sidebar row is its own `NavigationStack`
      (`LibrarySidebar.swift:116`, `:133`, `:152`, `:167`, `:183`), and the page is
      only ever *pushed* onto one of them (`PublicationRoute.swift:120`).

      The hero clause does not depend on the split and is done:
      `DetailHero.swift:42` is `.backgroundExtensionEffect()`, citing §3.4, with the
      wash ignoring the safe area at `DetailBackground.swift:46`. Whether it reads
      as art carrying under a sidebar in a `TabView` rather than a split is
      unverified, and that is what the three captures would settle. None exists.

      **This task also owes iOS the empty-pane sentence.** Task 4.3 is met on
      Android and unmet on iOS for exactly one reason — there is no second pane to
      put a sentence in. Whoever gives iOS a real split column writes that sentence
      back with the pane it belongs to.
- [ ] **4.2** Android: the detail pane, with predictive back animated by the
      scaffold. Screenshot expanded width, and the narrow-then-widen path.

      **The pane is real and it is Material's own scaffold. Predictive back is not
      animated by it, or by anything.** `core/designsystem/…/navigation/Panes.kt:57`
      is `ListDetailPaneScaffold`, wrapped as `StoryArcListDetailPanes` (`:51`) with
      `calculatePaneScaffoldDirective` at `:58` and `AnimatedPane` at `:66-67`;
      the call site is `AppPanes.kt:100`, split at `:47-56`, gated on
      `windowClass.showsTwoPanes` (`WindowClass.kt:62`, ≥ 840 dp). It is
      deliberately **not** `NavigableListDetailPaneScaffold` — one back rule, in
      `AppNavigation.back`, stated at `Panes.kt:25-33` and `AppPanes.kt:77-78`.

      **What is missing is the animation the clause names.** The pane's only back
      handling is `AppShell.kt:83`, a plain `androidx.activity.compose.BackHandler`
      with no progress and no preview. The app owns a real implementation and the
      pane does not use it: `PredictiveBack` (`back/PredictiveBack.kt:139`) is
      called only from `SettingsScreen.kt:131-132`, and **`PredictiveBackHost`
      (`PredictiveBack.kt:105`), the piece that draws the shrink-and-round
      transform, has zero call sites anywhere in `apps/android`.** The delta asks
      for it at [`specs/publication-detail/spec.md:171`](specs/publication-detail/spec.md).

      **A second defect, reported and not fixed.** The pane draws a back arrow with
      the list permanently beside it. `PublicationDetailScreen.kt:153-159` sets
      `navigationIcon` unconditionally and the composable takes no pane or
      window-class parameter (`:95-112`), so it cannot know. Material's own
      `ListDetailPaneScaffold` hides that affordance when both panes are visible;
      this pane is composed by hand, so it does not. `after-2026-08-31/`'s README
      records the same observation from the emulator.

      **Captures:** expanded width exists three times over —
      `after-2026-08-30/android-detail-tablet-two-panes.png`,
      `after-k2-android-tablet/android-large-list-detail-{panes,back}.png` and
      `after-2026-08-31/android-tablet-two-panes-light.png`. **The narrow-then-widen
      path is captured nowhere** — `android-large-list-detail-back.png` is a back
      press, not a resize.
- [x] **4.3** The empty second pane before a publication is chosen — one
      sentence, not an arbitrary publication. Screenshot both platforms.
      **Done on Android, and the screenshot the previous note called outstanding
      has landed:** `after-2026-08-31/android-tablet-empty-pane-light.png`, which
      that directory's README describes as the library as two panes with nothing
      chosen and the sentence written for it this wave.

      Android had a third answer to this — hide the pane until something goes in it
      — and it is out. The scaffold gave the whole width to the shelf, so the shelf
      reflowed its columns on the reader's first tap and reflowed back on their last
      press of Back, which is the library rearranging itself in answer to something
      that was not about the library. §4.7 of the direction settles it from the other
      side: "expanded and above: two panes", and a pane that is only sometimes there
      is not two panes. So the pane is always drawn at expanded width
      (`AppPanes.kt:106`) and `PublicationPanePlaceholder`
      (`PublicationDetailScreen.kt:480`, called at `AppPanes.kt:115`) puts
      `detail_pane_empty` in it — iOS's sentence, to the word, in all four locales
      at `strings.xml:358`. `PaneSplitTest.kt:53-62` pins it.

      **Answered on iOS, and the answer is that there is no second pane** — so
      there is nothing to screenshot, and the scenario is unmet rather than met.
      Android is separate and reports for itself.

      `PublicationDetailPlaceholder` existed, was translated into four languages
      and had no caller, which made it the third piece of dead code behind this
      change. It is deleted rather than wired, with its `detail.empty` string —
      both confirmed gone: the only trace is the tombstone at
      `PublicationRoute.swift:133`, and `detail.empty` is in none of the five
      `.xcstrings` files.

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
      delta's *pane before anything is chosen* scenario is met on Android and unmet
      on iOS, and this note is where that is written down.

## Phase 5 — Gates

- [x] **5.1** `corepack pnpm spec:validate`. **Green**, 2026-08-31 at `6c931e61`:
      23 items passed, 0 failed, this change among them.
- [ ] **5.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm build:ios`. The new screen must not put any Swift file over 400 lines —
      compose it from several.
      **The composition clause is comfortably met and the four commands were not
      run in this documentation pass.** The page is eight files and none is near
      the cap: `DetailActions.swift` 201, `PublicationDetailView.swift` 185,
      `DetailSeriesShelf.swift` 165, `DetailHero.swift` 152, `PublicationRoute.swift`
      148, `DetailWash.swift` 96, `DetailProvenanceLine.swift` 93,
      `DetailBackground.swift` 91 — 1131 lines across the eight, which is what
      "compose it from several" bought. Repository-wide, no Swift file is *over* 400 —
      the largest of 468 is `Sources/Formats/EpubReader.swift` at exactly 400.
      Note that no script enforces this: `package.json:22` runs ten checks and none
      counts a line.
- [ ] **5.3** Android: `./gradlew test lint`, 800-line cap.
      **This change's own file is inside the cap and the commands were not run
      here.** `feature/library/…/PublicationDetailScreen.kt` is 492 lines,
      `DetailHero.kt` and `DetailActions.kt` are smaller again. Five Kotlin files in
      the repository are over 800 and none of them belongs to this change; the list
      and the counts are in `one-library-three-destinations` task 6.3, which owns
      that gate.
- [x] **5.4** `corepack pnpm lint`, which includes `tokens:check` — the derived
      colour has to clear the same contrast gate the palette does.
      **Green**, 2026-08-31 at `6c931e61`, exit 0. `tokens:check` passes, and it is
      worth being precise about what that does and does not cover: it gates the
      **palette**, pair by pair, against its WCAG floor. The *derived* colour is not
      a token and cannot be, so it is gated in code instead —
      `DetailWash.swift:58-75` walks the blend down until body text over it clears
      4.5:1, asserted by `DetailWashTests.swift:79` (`everyAnswerIsLegible`, five
      colours against both palettes), and `CoverAccent`'s own suites assert the same
      floor on both platforms. The gate is green; the derived colour is not what
      makes it green.
- [ ] **5.5** The screenshot set is complete and referenced in the handoff.

      **Not complete. Seven captures are owed, and this is the list:**

      1. **The three states of the page** — a downloaded local publication, a
         cached remote one, and one whose source is unreachable — on both platforms.
         Tasks 2.1 and 2.2. Eleven iOS and four Android detail captures exist and
         none is keyed to those states.
      2. **The two paths from the home surface** — a cover on Home reaching the
         page, Home's hero reaching the reader. Task 2.3.
      3. **The four browse surfaces with no origin on them** — home, library,
         on-device, search. Task 3.4.
      4. **The wash under reduced transparency**, either platform, and Android's
         high-contrast branch. Task 1.4. Nothing under
         `docs/designs/screenshots/` matches `*transp*` or `*reduce*`.
      5. **iPad portrait, landscape and Split View.** Task 4.1.
      6. **The narrow-then-widen path on Android.** Task 4.2.
      7. **A capture of the degenerate page that holds up.** Task 2.4 — the one
         that exists shows that it does not.

      One thing that would make this cheaper next time: `after-2026-08-30/` has
      **no README**, unlike its two siblings, so its 133 captures are identified by
      filename alone. Four of this change's are among the ones that cannot be:
      `ios-detail-iphone-contrast-{light,dark}-{top,foot}.png` is read as *increased*
      contrast by convention, and nothing in the repository says so.

## Delta merge, 2026-09-04 — not this change's own work

`pnpm delta:drop` gained a check for **two active changes carrying a `## MODIFIED` delta on
one requirement**, and this change was one side of a pair. A MODIFIED requirement replaces the
whole block, so whichever of the two synced second would have deleted the other's scenarios —
silently, after the first change had archived and its delta was gone.

The pair was `native-experience` → *Dynamic colour*, with
`brand-identity-and-app-icons`. That change adds one clause to *Chrome accent* — that the
accent is a single colour, and the brand's pink-to-violet arc belongs to the mark rather than
to chrome — and carries the requirement's other scenarios unchanged. **This change's block now
carries that clause**, so its later sync keeps rather than deletes it, and the order
(`brand-identity-and-app-icons` first) is recorded in `.delta-drops.json`.

Nothing here changes what this change builds or what its tasks say. It is recorded because the
edit lands in this change's delta and `openspec-guard` would otherwise report the plan as
having moved after the task list for no visible reason.
