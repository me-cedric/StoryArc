# Tasks

> **Its delta moved on 2026-09-01 and no task changed, which is what the guard's stale
> flag is reporting.** `quiet-shell-and-search` and `quiet-reader` synced requirements this
> change also modifies, and a MODIFIED requirement replaces the whole block — so archiving
> this change would have silently dropped what they added. `openspec validate --all` caught
> it the moment the main specs moved, and two scenarios into its `library-browsing` delta were carried across under a note saying
> where they came from.
>
> **No task here is affected**: nothing this change builds changed, and the carried
> scenarios are already implemented by the changes that wrote them.
>
> **Its `navigation-shell` delta gained a requirement on 2026-09-01, for the same reason.**
> `quiet-shell-and-search` carried a MODIFIED *Reaching search* against a capability with no
> main spec — the one **this** change creates — so it had nothing to merge into and archiving
> it would have carried the requirement off. Both deltas named the same requirement, which
> that change's proposal said must trigger a reconciliation. Its newer statement, which is
> the one the app implements, replaced the superseded first draft here. **Task 1.2 changed
> with it** and says so; no other task did, because this change does not build search's
> entry point.
>
> **Its `library-browsing` delta gained two things later the same day, and the reason is that
> lesson applied one capability further.** The reconciliation above was found by reading; a
> re-verification of `quiet-shell-and-search` then asked whether the *sibling* capability had
> been checked too, and it had not. That change's delta had added a normative sentence —
> "Search SHALL say what it is about to search, and SHALL let a reader narrow it to what can be
> read with no network" — and rewritten *No results* to offer **widening** rather than clearing
> filters. Its two new scenarios had been carried across by hand; its **prose had not**, and
> nothing looked, because scenarios are listed and prose is read. Both are carried now, with the
> note beside them.
>
> **No task changed for that one**, and a gate now refuses the whole class: `pnpm delta:drop`,
> inside `pnpm lint`, fails when a MODIFIED delta would drop a scenario or a normative clause
> the main spec already holds.

Ordered so that the two things that block everything else — the Android
navigation rewrite and the iOS shell — are answered first, and so that no two
tasks in the same phase write the same file. The slice letters in brackets are
[`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md) §7.1.

**Every task that changes a screen owes a screenshot from a booted simulator or
emulator** — light and dark, default and largest text size — per
[AGENTS.md §6](../../../../AGENTS.md). A SwiftUI `#Preview` or a Compose
`@Preview` is not proof. Put them beside the before set in
`docs/designs/screenshots/`.

**What a tick means here.** This change is a two-platform change, so half of it
is not a tick: a task is ticked when the code and its host tests have landed on
**both** platforms, and when every capture the task names itself exists under
`docs/designs/screenshots/` with something on record saying what it shows. A task
whose code has landed and whose capture has not stays **unticked**, and its note
says which capture is owed and what it has to prove — a screen nobody has watched
is not a screen that works. Where a task asks for something the app has since
decided not to do, it is left unticked with the decision cited, never ticked and
never quietly dropped.

**The `library-browsing` delta moved after this list, and no task changed with it.**
`ec9551d6`, 2026-08-31 12:09, withdrew two clauses this change's delta had written into
*Mixed local and server search* — that no result is labelled with the source that supplied it,
and that a remote arrival never reorders or displaces a result the reader is reaching for — and
replaced them with what the shipped app actually does. Search was built against the **main**
spec deliberately, because a main spec is the contract and a delta is a proposal, so a sync
would have reverted working behaviour to a promise nothing kept.

No task in this list described either withdrawn clause, so none needed revising; the delta was
corrected to match the code rather than the code to match the delta. `openspec-guard` reports
this list as `stale` on a timestamp comparison, which is the right heuristic and the wrong
conclusion here. Recorded rather than silently re-touched, so the next reader can tell the two
apart.

**Audited against `main` at `6c931e61`, 2026-08-31**, with `path:line` evidence
read from the source rather than from any note. Earlier notes here described a
tree that has moved a great deal since; where an old number is now wrong the new
note says so and gives the current one. Eight of twenty-five are ticked.

## 0b. What a design review found on the hero (2026-09-01)

Four scenarios added to `home-screen`'s *Keep reading*. Verified against the code first: the
card carries a kicker, a title and one line, has **no** `ProgressView`, names no author (the
kicker is series-or-publisher), and is its own only tap target. It is 4:5 at up to 420pt — about
**half** a phone's height, where the review said "nearly a full viewport".

- [~] 0b.1 Both: progress is visible as well as stated, and the author is named where the card
      has room. A title alone is not enough to recognise a book by.

      **Code landed on both platforms 2026-09-05; the frames are owed.**

      **The task's own preamble was half wrong, and the half it got wrong saved work.**
      It says the card "has **no** `ProgressView`" — true of iOS, and not of Android, which
      has drawn `LinearWavyProgressIndicator` in `HomeKeepReadingCard` since the card was
      written. So *progress is visible* was already met on one platform and only iOS needed
      it. What neither platform had was the author.

      iOS: `HomeHero.swift` gains a byline under the title and a hand-drawn capsule bar fed
      by `LibraryModel.readFraction(of:)`. Hand-drawn rather than a `ProgressView`, because
      a linear progress view takes its tint from the environment and this bar sits on a dark
      scrim in **every** theme — the accent that is legible on paper is not legible there.
      The bar is `accessibilityHidden`: the line beside it already states what is left in
      pages, and a bar announcing a percentage next to it is one fact in two units, which is
      the thing *Resuming* names as not to do.

      Android: `HomeCards.kt` gains the byline. The carousel's height budget went from
      `homeCaptionHeight(lines = 5)` to `6` with it — a budget that had not moved would clip
      the last line at exactly the text sizes it matters most at.

      **The two rules are deliberately not the same rule, and that is worth reading before
      "fixing" it.** iOS's card carries a kicker above the title, and its byline is
      suppressed when it would repeat that kicker — a self-published author is their own
      publisher, and the publisher is the kicker's fallback. Android's card has no kicker,
      so there is nothing to repeat and the rule is the shorter one. Each test says so.

      Tests: `Tests/LibraryFeatureTests/HomeCardIdentityTests.swift` (7 cases over the new
      pure `HomeCardIdentity`, which is where the kicker and byline decisions moved out of
      the view so a host test could reach them) plus a two-case wiring guard that the hero
      still asks for a fraction and still draws it;
      `feature/library/…/HomeCardBylineTest.kt` (3 cases). All green.

      **Frames owed** — the hero, before and after, on both platforms:
      - iOS, iPhone, Home with at least two publications in progress: light and dark, at
        default and largest text size (4 frames). The byline and the bar have to be legible
        over a **pale** cover as well as a dark one, so the walk must put a light-covered
        publication first — that is what the scrim exists for and it is the one thing a
        dark-cover capture cannot show.
      - Android, phone, Home carousel: light and dark, default and largest text size
        (4 frames). At largest text size the point is the `lines = 6` budget — the "what is
        left" line must not be clipped.
      - Route: `pnpm capture:android Home --dark --font-scale 2.0` and the matching light
        and default runs; iOS by the `LibrarySelectionCapture`-style walk that opens a book,
        reads a page, backs out, and lands on Home with something in progress.
- [~] 0b.2 Both: a named resume action on the card, as well as the card being tappable. Both do
      the same thing — a card that is a button with no button on it teaches nothing about what
      tapping does.

      **Code landed on both platforms 2026-09-05; the frames are owed.** Neither card had a
      button before this — iOS was an `.onTapGesture` on the artwork and Android a
      `Modifier.clickable` wrapped round the whole card, so on both platforms the only reader
      who learned the card was a control was the reader who tried.

      iOS: a `.glassProminent` **Resume** in the caption, which also makes the divergence
      register's #10 true for the first time. `HomeCards.kt`'s own KDoc has claimed since it
      was written that "iOS emphasises with a prominent glass button and scale contrast,
      Android with shape and containment" — and iOS's half of that sentence described a
      button that did not exist. Android: a filled `Button`, which is safe on this card for
      the reason #10 gives — the card emphasises by shape and containment, so there is no
      tint on it for a filled button to compete with.

      **Both are hidden from assistive technology, and that is deliberate.** Each card is
      already one combined element carrying a button role — iOS by
      `accessibilityElement(children: .combine)`, Android by `clearAndSetSemantics` — so the
      action is there. A nested button would be a second stop offering the same book the same
      way. The button exists to teach a *sighted* reader what the artwork does, which is the
      gap the scenario is about.

      **Neither draws the button where the book cannot be opened.** An action that would fail
      is worse than no action, and the line above it already says why. That absence is the
      assertion nothing else in either build would notice going, so it is a test on both.

      New strings in all four languages on both platforms: `home.resume` /
      `home_resume` — Resume, Fortsetzen, Continuar, Reprendre.

      Tests: `HomeHeroProgressWiringTests` gains two cases (iOS), and
      `HomeHeroResumeWiringTest.kt` is new (Android, 3 cases, reading `HomeCards.kt` and
      `HomeScreen.kt` through the module's existing `storyarc.library.projectDir` wiring —
      both files are declared as task inputs so the guard cannot sit UP-TO-DATE while the
      card changes underneath it). All green.

      **Frames owed**, same walk as 0b.1 and takeable in the same pass:
      - iOS iPhone and Android phone, Home with something in progress: light and dark, at
        default and largest text size (8 frames). What each has to show is the button
        legible **over a pale cover** on iOS — it sits on the scrim, not on a surface — and
        on Android that the button did not push the card past the carousel's height budget,
        which grew by `HOME_RESUME_ROW` for it.
      - One frame per platform of a publication whose source is away, showing **no** button
        under the dimmed card.
- [~] 0b.3 Both: a publication with a page or less left offers to **finish** it and offers the
      next in its series, rather than offering to reopen its last page. Finishing removes it
      from Keep reading by the same rule finishing normally does.

      **Code landed on both platforms 2026-09-05; the frames are owed.**

      **The rule could not be derived from anything either platform already had, and that
      was the whole of the work.** iOS's `HomeShelves.remainder` answers `.nothingToSay` to
      four different situations — never opened, finished, an audiobook, and a book on its
      last page — and Android's `pagesRemaining` answers null to several. Only one of them
      is *the reader has finished all but the last page*. A card reading either would have
      offered to **finish a book nobody had opened**. So `HomeShelves.isAtTheEnd` is a
      question of its own on both platforms, answering false wherever it cannot honestly
      answer true: an audiobook, whose unit is not pages and whose *time remaining* is not
      derivable from what the position carries, and a reflowable book with no declared spine
      count, where "a page or less" needs a page to be a thing.

      The next issue comes from `LibraryIndex.next` on both platforms — the shared ordering
      both already mirror, whose issue-number parsing ("3.5" and "Annual 1" are both real) is
      asserted against one table on each side. A second ordering written on this screen is
      exactly how the two would drift. Android asks it for Keep reading only: it is a scan of
      the library per entry, cheap over a shelf of six and wasteful over every shelf on the
      surface for an answer nothing would draw.

      **Finish is prominent even beside a next issue** — the reader is on the last page of
      *this* book, and finishing is what they came to do; the next issue follows it rather
      than replacing it. iOS: `.glassProminent` Finish, `.glass` Next in series. Android:
      filled `Button` and `OutlinedButton`.

      **One rule for leaving the row, which is the clause easiest to break.** Neither card
      writes a record. iOS calls `LibraryModel.mark(_:read:)` and Android reports the choice
      out through a new `onFinish` on `HomeScreen` to `AppHost.mark` — the same call the
      publication page and the bulk bar already make, which is what makes "the same rule that
      finishing normally does" true rather than merely claimed. Both platforms have a test
      asserting the card touches no progress store.

      New strings in all four languages on both platforms: `home.finish` / `home_finish`
      and `home.nextInSeries` / `home_next_in_series`.

      Tests: `HomeRemainderTests` +6 and `HomeShelvesTest` +4 over the new predicate — each
      including the never-opened and finished cases, which are the ones that share a spelling
      with the true case; `HomeCardIdentityTests` +3 and `HomeHeroResumeWiringTest` +2 over
      the wiring. All green.

      **Frames owed** — this is the state hardest to reach and the frames matter most:
      - Both platforms, a comic stopped on its **last page**, on Home: light and dark, at
        default and largest text size (8 frames). What each has to show is *Finish* where
        *Resume* was, and **Next in series** beside it — so the walk needs two issues of one
        series in the library, the first read to its last page.
      - One frame per platform of the same card where the library holds **no** next issue,
        showing Finish alone rather than a gap where the second button would be.
      - One frame per platform *after* Finish is taken, showing the publication gone from
        Keep reading and present under Finished — which is the clause about one rule, seen
        rather than asserted.
      - Route: on Android, `pnpm capture:android Home` after a walk that opens the first
        issue and pages to its end; on iOS the equivalent walk before the shutter.
- [ ] 0b.4 Both: the next section's heading is visible without scrolling on a phone at the
      default text size, while the card stays the surface's one emphasis.
- [ ] 0b.5 Both: captures before and after, at default and largest text size.
      **Android needs no new hero** — it has one, first on the surface, conditional on something
      being in progress exactly as iOS is. The review reported it missing because the device had
      nothing in progress. Do not build a second one.

## Phase 0 — Answer before building

- [x] **0.1** Settle whether the iOS search role expands into a field in place.
      Build a throwaway four-destination shell, tap it, screenshot. Deliverable: a
      screenshot and a go/no-go on the fallback named in `design.md`.
      **Settled on a device, and the answer is that it morphs.** Recorded at
      [`ui-revamp-2026-08.md:1069-1078`](../../../designs/ui-revamp-2026-08.md) —
      selecting the search tab on a booted iPhone 17 Pro replaces the three
      destinations with a field in place, at the foot of the window. The capture is
      `docs/designs/screenshots/after-2026-08-31/ios-search-role-morphs-dark.png`.

      **The go/no-go is a no.** `design.md:43-45` of this change named
      `.searchable()` with the minimizing search-toolbar behaviour as the fallback;
      the direction now says in as many words that it "is not needed and should not
      be built", and `grep` finds no `.searchToolbarBehavior` anywhere in
      `apps/ios`. The throwaway shell was never built, because the real one answered
      the question first: `apps/ios/App/AppShell.swift:107` is
      `Tab(value: .search, role: .search)`, and `LibraryView.swift:311` puts the
      field inside it. `proposal.md:148` still says "One iOS behaviour is
      unverified" and is stale — it wants correcting when this change is synced.
- [x] **0.2** Confirm `androidx.compose.material3.adaptive` 1.3.0 resolves
      alongside `material3 1.5.0-alpha26`, and that `TopSearchBar`,
      `ExpandedFullScreenContainedSearchBar`, `WideNavigationRail` and
      `MediumFlexibleTopAppBar` are reachable without an experimental opt-in
      spreading past `:core:designsystem`. Deliverable: a resolved dependency
      graph, or the alpha that does resolve. **Version-catalogue edits belong to
      its owner** — this task reports, it does not commit the bump.

      **The versions resolve; the containment clause is answered and the answer is
      no.** `apps/android/gradle/libs.versions.toml:38` pins `material3` at
      `1.5.0-alpha26` and `:53` pins `material3Adaptive` at `1.3.0`, with
      `adaptive-navigation-suite` taking `version.ref = "material3"` for the strict
      reason the catalogue records at `:39-46`; `core/designsystem/build.gradle.kts:41-48`
      declares both lines together and the module compiles, which is the resolution
      proof the task wanted. **What is missing is the artefact** — no resolved
      dependency graph was ever written down; `grep` finds the phrase only in this
      task.

      Two of the four named symbols were not reachable as named. `TopSearchBar` no
      longer exists under that spelling in alpha26 — the app calls `AppBarWithSearch`
      (`feature/library/…/LibrarySearchBar.kt:16`, `:188`), with the rename recorded
      at `LibrarySearchBar.kt:143-145`. `WideNavigationRail` needs no opt-in and sits
      where it should (`core/designsystem/…/navigation/AdaptiveNavigation.kt:14`,
      `:163`). But `ExpandedFullScreenContainedSearchBar` (`LibrarySearchBar.kt:19`,
      `:207`) and `MediumFlexibleTopAppBar` (`LibraryTopBar.kt:13`, `:65`;
      `HomeScreen.kt:28`, `:116`) both need `ExperimentalMaterial3Api`, annotated at
      `LibrarySearchBar.kt:153` and `LibraryTopBar.kt:47`.

      **The opt-in did spread, into four modules, and one file claims otherwise.**
      `core/designsystem/…/navigation/Panes.kt:17` says it is "the one place
      `ExperimentalMaterial3AdaptiveApi` is opted into";
      `feature/library/…/PublicationDetailScreen.kt:90-92` opts into that same API
      plus the other two. Beyond `:core:designsystem`, annotations sit in fifteen
      files of `:feature:library`, in `:feature:reader` (`ReaderScreen.kt:283`,
      `AdjustmentsSheet.kt:65`) and in `:feature:epubreader`
      (`EpubReaderActivity.kt:281`, `:939`, `:1016`). No module-wide `optIn` exists
      in any `build.gradle.kts`, so every one is a deliberate per-file annotation.
      **To close this:** produce the graph, and either re-scope the containment
      promise or correct `Panes.kt:17`.

      *Done, 2026-09-05. Both halves, and the graph is written down.*
      `apps/android/README.md` gains **"The resolved graph, and what it costs"**, which
      is the artefact: the resolved `:core:designsystem:dependencies
      --configuration debugCompileClasspath` tree, with the two upgrades named. The suite
      asks for `material3` 1.4.0 and gets the alpha; it asks for `adaptive` 1.2.0 and gets
      1.3.0 from the higher direct declaration. **Nothing is downgraded, nothing is forced
      and no `resolutionStrategy` is involved**, which is the part "the module compiles"
      never established — a forced resolution compiles too.

      The containment promise is corrected rather than re-scoped, because the divergence
      turned out to be defensible and worth keeping. `Panes.kt` now says it is one of
      **two** places opting into `ExperimentalMaterial3AdaptiveApi`, names the other, and
      says why neither of its wrappers fits it: `PublicationDetailScreen` asks the pane
      directive whether the window has room *before* deciding to draw a scaffold at all,
      and draws its one-pane case as a plain `Column` — a hidden supporting pane would be a
      series shelf the reader cannot reach. The README also records that the other two
      annotations are **not** contained, across five modules, with the `grep` that counts
      them, because the file count is what a reader needs before the alpha bump and not
      after.

      **The audit above was right about the opt-in spread and wrong about its shape.**
      `ExperimentalMaterial3AdaptiveApi` — the API `Panes.kt` was claiming — is in exactly
      two files, not the fifteen-plus the note implies; the wider spread is the other two
      annotations, which `Panes.kt` never claimed. Both facts are now written where the
      bump will be planned.

      **A third stale comment was found on the way and corrected.**
      `libs.versions.toml` said `adaptive-layout` and `adaptive-navigation` "are not
      applied to a module yet". `adaptive-layout` has been `api`-scoped in
      `core/designsystem/build.gradle.kts` since the pane scaffolds landed;
      `adaptive-navigation` is still applied to nothing. No version was touched — the
      task's own rule that catalogue edits belong to their owner holds, and a comment that
      describes the tree wrongly is not a version.
- [x] **0.3** Confirm the availability projection can be computed from the
      download record plus the local-file case for every source type, with no
      source consulted. Deliverable: a host unit test that answers it for one
      publication of each type with the network off.

      **The projection is built and is pure on both platforms; the per-source-type
      test is not complete on either.** iOS: `LibraryFeature/ScopeMenu.swift:43`
      (`keeps(_:)`) and `:70` (`isReadableNow(_:location:registry:)`). Android:
      `feature/library/…/LibraryAvailability.kt:41` (`isReadableOffline`) and
      `LibraryMarks.kt:107`. Every test is a plain host test over an in-memory
      `SourceRegistry`; no network is reachable from any of them.

      **What is missing is one case per platform, and they are different cases.**
      There are four source kinds (`StoryArcCore/Source.swift:4-8`,
      `core/model/Source.kt:6-10`). iOS `LibraryAvailabilityTests.swift` runs 11
      cases and exercises `.networkShare`, `.opdsCatalog`, `.kavitaServer` and the
      no-source case — **`.localFolder` is never used**. Android
      `LibraryAvailabilityTest.kt` runs 5 and exercises `LOCAL_FOLDER` and
      `KAVITA_SERVER` — **`NETWORK_SHARE` and `OPDS_CATALOG` are never named**;
      `LibraryMarksTest.kt:183` loops all four kinds but only for the *Connecting*
      case. Add a `localFolder` case on iOS and `networkShare` + `opdsCatalog` cases
      on Android and this closes.

      *Done, 2026-09-05.* One test per platform, each looping all four `SourceKind`
      values so a fifth kind cannot be added without answering here.
      `Tests/LibraryFeatureTests/LibraryAvailabilityTests.swift` — *"Every source kind
      is answered from the download record alone, none of them asked"* — asserts for
      every kind that bytes on the device outrank a downed library, that no bytes plus
      a downed library is not readable, and that a reachable library's publications
      are. `feature/library/src/test/…/LibraryAvailabilityTest.kt` — *"every source
      kind is answered from the shelf alone, none of them asked"* — asserts the
      Android rule, which is the different one: only `LOCAL_FOLDER` can answer no, and
      it does so only when the system withdrew the persisted permission. Both
      registries are in memory and neither implementation has a call that could reach
      a source, which is what "with the network off" means here. 12 tests in the iOS
      file, 8 in the Android one; `swift test --filter LibraryAvailabilityTests` and
      `:feature:library:testDebugUnitTest --tests '*LibraryAvailabilityTest*'` both
      green.

      **Two claims in the audit above were wrong and are corrected here.** The iOS
      implementation is `Sources/LibraryFeature/LibraryAvailability.swift`, not
      `LibraryFeature/ScopeMenu.swift` — there is no file by that name in the package.
      And the Android suite ran **7** tests before this task, not 5. Neither error
      changed what was missing.

      **What the two implementations do *not* share is worth recording.** iOS's
      `isReadableNow` never reads `Source.kind` at all — location and state are the
      whole answer — while Android's `isReadableOffline` branches on kind and returns
      `true` unconditionally for the three network kinds. They agree on every case a
      reader can produce because on Android a network row is on the shelf only if it
      was downloaded; the divergence is in what each platform has to be told, not in
      what a reader sees. Pinned from both sides now, so a change to either is a
      failing test rather than a silent split.

## Phase 1 — The shells

- [x] **1.1** **[C] Android navigation rewrite.** Replace the boolean cascade in
      `MainActivity.kt` with a typed navigation graph and `NavigationSuiteScaffold`
      carrying the three destinations. Per-destination back history, per-destination
      state restoration, predictive back preserved. `MainActivity.kt` ends under
      800 lines. Screenshot: each destination, phone and tablet.
      *Done. `MainActivity.kt` 1168 → 179 lines; the state is one `AppNavigation`
      value with one back rule, covered by 21 host tests.* **Two numbers in the
      previous note have drifted and are corrected here:** the file is 179 lines,
      not 170, and `app/src/test/…/navigation/AppNavigationTest.kt` holds 21 `@Test`
      methods, not 17. The graph is `navigation/Destinations.kt:31` (the enum) and
      `navigation/AppNavigation.kt` (the state); restoration is
      `AppShell.kt:69-71`'s `rememberSaveable(stateSaver: AppNavigation.Saver)`.

      **The API is `NavigationSuiteScaffoldLayout`, not `NavigationSuiteScaffold`**
      — `core/designsystem/…/navigation/AdaptiveNavigation.kt:19`, `:159` — chosen
      so the bar-or-rail decision comes from the app's own window class rather than
      Material's suggestion, for the 800×360 landscape-phone reason recorded at
      `AdaptiveNavigation.kt:126-134`.

      Predictive back is preserved in the sense the task means — the screens that
      hand-roll it keep their own handler and the shell's single `BackHandler`
      (`AppShell.kt:83`) is the fallback under them. It is worth writing down that
      **nothing in the app animates a predictive back**: `PredictiveBackHost`
      (`core/designsystem/…/back/PredictiveBack.kt:105`) is the piece that draws the
      shrink-and-round transform and it has no call site anywhere in `apps/android`.
      That is not this task's to fix; it is the reason `publication-detail` task 4.2
      cannot be ticked. Screenshots in
      `docs/designs/screenshots/after-2026-08-30/android-shell-*.png`, plus the
      tablet rail in `after-2026-08-31/android-tablet-rail-home-light.png`.
- [ ] **1.2** **[D] iOS shell.** `TabView` with three `Tab`s, a **fourth destination for
      search**, `.tabViewStyle(.sidebarAdaptable)` and the minimize behaviour, around the
      existing library view. Settings and add-source leave the library toolbar.
      Screenshot: each destination, iPhone and iPad, portrait and landscape.

      **This task asked for "the search role" until 2026-09-01, and the requirement it was
      written against has since been rewritten.** `Tab(role: .search)` morphs the tab into a
      text field in place, which is what *Reaching search* now forbids — task 0.1 found it on
      a device and `quiet-shell-and-search` replaced it with a destination. The clause is
      corrected here rather than left to read as an instruction to rebuild the thing that was
      removed. **No work is added to this task by the correction**: the destination is
      shipped, by that change, and its captures are on its own list.

      **The shell is built. Two of the task's clauses are not met, one on purpose.**
      `apps/ios/App/AppShell.swift` has the three `Tab`s at `:73`, `:83` and `:93`,
      `.tabViewStyle(.sidebarAdaptable)` at `:118` and
      `.tabBarMinimizeBehavior(.onScrollDown)` at `:119`, wrapped around
      `LibraryView` at `:165-173`. The search role that used to sit at `:107` is gone, and
      that is the fix above, not a regression.

      **Settings left the library toolbar; add-source did not.**
      `LibraryToolbar.swift:13-15` records the move and `HomeScreen.swift:99-107`
      is where Settings landed — the home destination's trailing bar item. But
      `LibraryToolbar.swift:71-79` still carries `AddSourceMenu`, and
      `LibraryToolbar.swift:15-19` says why in its own words: add-books stays "for
      now and against the direction's end state", because both places it is meant to
      go — the rebuilt empty state and Settings' connected-libraries screen — belong
      to later slices. That is a defensible hold, and it is still half a clause
      unmet.

      **The landscape captures are owed.** Every iPad PNG in
      `after-2026-08-30/` is 2064 × 2752 — portrait, all sixteen of them. iPhone
      light, dark and largest-text are all present
      (`ios-shell-iphone-{home,home-dark,library-light,library-dark,downloads-dark,search-dark,library-ax5-light}.png`).
      What is missing is one landscape pass per destination on iPad.
- [x] **1.3** Verify against the delta that the destination count does not change
      when a source is added, renamed, reordered or removed. A test with nine
      configured sources, on both platforms.

      **iOS has exactly this test; Android has nothing that could be it.**
      `Tests/LibraryFeatureTests/LibraryDestinationTests.swift:45-52` is
      *"Nine servers do not put a navigation control over its ceiling"*, building
      nine `.kavitaServer` sources and asserting `LibraryDestination.all(for:)`
      still returns three; `:39-43` does the same for one source of every kind. The
      suite holds 8 tests.

      **What is missing on Android is the whole test.** `AppDestination`
      (`navigation/Destinations.kt:31`) is a bare enum with no source parameter, so
      there is nothing for a nine-source test to call, and
      `AppNavigationTest.kt:48-55` asserts the enum's three entries with zero
      sources configured. `Destinations.kt:16-19` argues the promise is kept by
      construction — "there is no expression anywhere that could produce a fourth" —
      which is a real argument and not the test the task asks for. Close it either
      by giving Android the same source-taking function iOS has, or by recording the
      by-construction argument as the answer and saying so here.

      *Done, 2026-09-05, by the first of the two routes.* `AppDestination.all(sources)`
      (`navigation/Destinations.kt`) now takes a registry and discards it, mirroring iOS's
      `LibraryDestination.all(for:)` — which reads its parameter exactly as much, and for
      the same stated reason: an answer that cannot be handed a registry cannot be tested
      against one. Three cases in `AppNavigationTest.kt` call it — with nothing configured,
      with one source of every kind, and with nine Kavita servers, the last also asserting
      that reversing the list and dropping four of them changes nothing, which is *renamed,
      reordered and removed* in the same assertion. `:app:testDebugUnitTest --tests
      '*AppNavigationTest*'` green; the suite is 24 tests, up from 21.

      **Three claims in the audit above were stale, and the third one mattered.**
      (1) `AppDestination` is not a three-entry enum — it has had four since
      `quiet-shell-and-search` made search a destination, and the same change is why iOS's
      `LibraryDestinationTests` asserts **four**, not the three the note quotes. The
      *"Nine servers"* test there reads `.count == 4`. (2) `AppNavigationTest.kt:48-55` no
      longer asserts three entries; it asserts the four, in order. (3) That test's own doc
      comment claimed **"the cases below still hold a nine-server registry to the same
      four"** — and no case below took a registry, because there was nothing to hand one
      to. A comment describing a test that does not exist is worse than a missing test: it
      is what a reader checks *instead of* looking. The comment now says what it used to
      claim and when the claim became true.

## Phase 2 — What the destinations hold

- [ ] **2.1** **[E1/E2] Home**, both platforms: Keep reading, Up next, recently
      added, pinned shelves, finished. Assembled from local history alone.
      Screenshot: all three degradations — carousel, single card, and Home as the
      empty state.

      **Four of the five sections are built on both platforms. Pinned shelves do
      not exist anywhere in the app.** iOS: Keep reading `HomeScreen.swift:58`/`:165`,
      Up next `:60`/`:182`, Recently added `:64`/`:190`, Finished `:68`/`:144`.
      Android: `HomeScreen.kt:57` declares
      `enum class HomeSection { KEEP_READING, UP_NEXT, RECENTLY_ADDED, FINISHED }`
      — four cases, drawn at `:146`, `:148`, `:157` and `:166`.

      **What is missing is pinning itself, not a section that renders it.** No
      `Shelf` type on either platform carries a pin flag; a grep for
      `pinned`/`isPinned` across `StoryArcCore`, `core/model` and `core/persistence`
      returns certificate pinning and prose. The delta scenario is
      `specs/home-screen/spec.md:83-85` and it needs a stored flag, a way to set it,
      and a section ahead of the unpinned ones. iOS has a `shelvesLink` row
      (`HomeScreen.swift:142`, `:207`) which is a navigation entry to `ShelvesView`,
      not a pinned shelf; Android's Home has no shelves entry at all.

      Assembled from local history alone: yes on both. iOS `HomeShelves.swift:5-17`
      are pure functions fed from `progressStore.recent` (`LibraryModel.swift:295-306`);
      Android builds the whole surface in one `remember` from local publications,
      progress and the download record (`HomeDestination.kt:101-108`).
      **One divergence to settle:** iOS scopes Keep reading by the library's current
      query (`LibraryModel.swift:366`) and Android does not, so the iOS hero can
      narrow when the shelf's scope changes. Both are local; only one is scoped.

      The three degradations are captured —
      `after-2026-08-30/ios-home-iphone-hero-light.png` (carousel),
      `ios-home-iphone-hero-solo-light.png` and `android-home-one-card-light.png`
      (single card), `ios-home-iphone-empty-light.png` and
      `android-home-first-run-dark.png` (Home as the empty state).
- [ ] **2.2** Test that Home renders complete and unchanged with every source
      unreachable, and that no shelf appears, reorders or grows when a slow source
      answers. This is the property most likely to regress silently, so it is a
      test rather than an inspection.

      **iOS has the first half. Android has neither half. Neither platform has the
      second.** `Tests/LibraryFeatureTests/HomeOfflineTests.swift` is
      *"Home with nothing reachable"*, 4 tests, and `:79-97`
      (`shelvesDoNotDependOnASource`) builds two models — every source up, and one
      `.unreachable` — and compares all four shelves by id.

      **What is missing, precisely:** an Android `HomeOfflineTest` that does what
      `HomeOfflineTests.swift:79` does. `HomeShelvesTest.kt` has 22 tests and its
      only two reachability cases (`:62`, `:159`) assert the *per-entry* flag, never
      the surface up against the surface down. And **the slow-source clause is
      asserted nowhere on either platform** — no test drives a source that answers
      late and re-checks that no shelf appeared, reordered or grew. The property is
      argued in a KDoc (`HomeShelves.kt:51-53`) and by the construction of the
      `remember`, which is exactly the kind of proof this task exists to replace.
- [x] **2.3** **[I1/I2] The on-device destination**, both platforms. Downloads
      content leaves the settings modal; the queue becomes a pinned section that is
      absent when nothing is in flight; storage limits and network policy stay in
      settings. Screenshot: with a queue in flight, with none, and empty.
      **Done on both platforms, and all three captures exist.** The queue is absent
      rather than empty: `apps/ios/App/DownloadsDestination.swift:81`
      (`if !inFlight.isEmpty`) and `apps/android/…/DownloadsDestination.kt:120`
      (`if (inFlight.isNotEmpty())`) — in both cases the heading lives inside the
      branch, so nothing is left standing over a gap.

      Downloads content did leave the settings modal.
      `SettingsFeature/DownloadsSettings.swift` is 101 lines and holds no per-file
      list and no removal — only the three policy rows and a pointer to the
      destination at `:48`; `feature/settings/…/DownloadsGroup.kt` is 177 lines and
      the same shape, pointing at `:78`. The policy that stayed is the policy the
      task says should: Wi-Fi only (`DownloadsSettings.swift:65`,
      `DownloadsGroup.kt:102`), remove after finishing (`:75`, `:109`) and the
      storage ceiling (`:88-96`, `:127-139`).

      Captures: `after-2026-08-30/{ios,android}-downloads-queue-largest-text.png`
      (in flight), `{ios,android}-downloads-destination-{light,dark}.png` (none in
      flight) and `{ios,android}-downloads-empty.png` (empty).

      One thing seen while reading and left alone, because it is not this task's:
      the space total (`DownloadsDestination.swift:98`, `DownloadsDestination.kt:166`)
      reports the download directory alone, so a reader whose on-device set is
      entirely picked-folder files is told *Zero KB* under a full shelf.
- [x] **2.4** Delete the per-source destinations and the server chip strip above
      the shelf on both platforms, and delete the source line under a cover.
      Screenshot: the library with two sources configured, before and after.
      **Done on both platforms, and the Android capture the previous note called
      outstanding has since landed.** The pair is
      `after-2026-08-31/android-shelf-caption-scale2-light.png`, where the strip is
      still up with *Attic NAS* and *Reading Room* on it, and
      `after-2026-08-31/android-library-no-source-strip-light.png`, where it is
      gone; that directory's README names the second as this task's. iOS's pair is
      `before-2026-08-30/ios-shelf-source-line-{light,dark}.png` →
      `after-2026-08-30/ios-shelf-no-source-line-{light,dark}.png`.

      Verified rather than taken on trust: `CatalogueStrip` and `SourceList` have
      zero hits anywhere in `apps/android`; no per-source destination survives on
      either platform (`LibraryDestination.swift:23-27` and `:45-49`, which takes
      the registry and discards it; `Destinations.kt:31-35`); and no cover on either
      platform carries a source line — `CoverCell.swift:221`, `CoverList.swift:203`,
      `CoverGrid.kt:662-682` and `CoverList.kt:282` each print the format and each
      says in a comment that no third line names a server. `LibraryScreen.kt:72`
      no longer takes `onRemoveSource`; removal lives only on the Settings path.
      `AddSourceMenu` is its own file at
      `feature/library/…/AddSourceMenu.kt`, named as iOS names it.

      The source line under a cover went in an earlier commit on each. This one took
      Android's `CatalogueStrip` — the per-source chips above the shelf — and
      `SourceList`, the browse fallback that stood in for the grid and listed every
      configured library with its connection state. §6.2 of the direction puts
      connections in Settings and nowhere else on the browse path, and Settings
      already has the removal flow. `AddSourceMenu` shared a file with the strip and
      does not share its fate — it is the toolbar's way in to the add-a-source
      sheets. Five strings left with the two screens, in all four locales.

      Two dead composables were reached in the same pass, because the branch the
      strip left behind is where they belong. `LibraryScreen` called an
      `EmptyLibrary(onScan:)` overload that resolved to the superseded one in
      `LibraryEmptyStates.kt`: four transport rows over a folder button, which is
      the shape `sources` forbids. The rewritten `EmptyLibrary` and its
      `AddBooksButton` had been written, translated and called by nobody, and so
      had `LibraryAway`. All three are wired now — `LibraryStates.kt:86` from
      `LibraryScreen.kt:517`, `LibraryStates.kt:150` from `LibraryScreen.kt:532` —
      the superseded overload is deleted, and `LibraryEmptyStates.kt` is down to
      the three states that survive.

## Phase 3 — The availability axis

- [ ] **3.1** The availability projection, both platforms, with the host tests
      from 0.3 extended to the whole library.

      **Android has the library-wide projection as a pure function with a test over
      a list. iOS cannot have one, because its projection is inside a view.**
      Android: `feature/library/…/LibraryAvailability.kt:57` is
      `List<Publication>.narrowedTo(availability, registry)`, and
      `LibraryAvailabilityTest.kt:81` — *"widening restores the whole shelf in the
      order it was in"* — asserts both directions over a list.

      **What is missing on iOS is a seam.** The whole-library narrowing is
      `LibraryContent.swift:22`, a computed `var shown` on a SwiftUI view extension,
      so no host test target can call it; the 11 cases in
      `LibraryAvailabilityTests.swift` are all one publication at a time. Lift the
      body of `shown` into a free function beside `LibraryAvailability` — Android's
      `narrowedTo` is the shape — and assert it over a list. Until then the property
      the delta cares about, that widening restores the library without re-scanning,
      is asserted on one platform only.
- [ ] **3.2** **[G1/G2]** The library's primary scope becomes availability. The
      by-library filter lands in the same commit as the removal of the source
      scope, so no reader loses per-source browse between one build and the next.
      Screenshot: everywhere, on-this-device, and the filter sheet.

      **The axis flipped on both platforms and the source scope is gone from both
      toolbars. One thing is wrong on each side, and the iOS one breaks a scenario
      in the delta.** iOS: `ScopeMenu.swift:16-22` is `everywhere` / `onThisDevice`,
      first in the toolbar's narrowing group (`LibraryToolbar.swift:52-54`), applied
      at `LibraryContent.swift:31-35`. Android: `LibraryControls.kt:98-118` is the
      leading chip, applied at `LibraryScreen.kt:302-305`. Neither toolbar carries a
      source control any more, and no sidebar case is a source
      (`LibrarySidebar.swift:15`).

      **iOS: the by-library narrowing is a scope wearing a filter's name, and
      *Clear filters* does not clear it.** `ScopeMenu.swift:127-144` writes
      `model.query.scope`; `LibraryQuery.swift:126-136` (`activeFilterCount`)
      excludes `scope`, so the badge does not count it, and
      `LibraryQuery.swift:155-166` (`withoutFilters`) leaves it alone, so the
      *Clear filters* at `LibraryFilterMenu.swift:47-52` returns a reader to the
      whole library except for the one narrowing they are actually in.
      `specs/library-browsing/spec.md` *Scoping to one source* asks for the
      opposite in as many words — "clearing filters restores the whole library, so
      there is no state a reader can be left in without noticing". Android has the
      shape the delta wants: `LibraryFilterMenu.kt:46` makes it `FilterSection.LIBRARY`,
      counted at `:149` and cleared at `LibraryScreen.kt:443`.

      **Android: the axis does not survive a cold start.**
      `LibraryScreen.kt:188` and `:198` are `rememberSaveable`, and the KDoc at
      `:183-186` says so itself — the query is what `LibraryPreferences` persists
      and availability is not part of it. iOS persists both with `@AppStorage`
      (`LibraryView.swift:39`, `:48`). *Narrowing to what can be read now* requires
      "the choice persists until changed".

      Captures: `after-2026-08-30/ios-library-on-this-device-dark.png` and
      `android-library-on-device.png` cover on-this-device, and the ordinary shelf
      covers everywhere. **The filter sheet in its by-library form is captured on
      neither platform** — that is the one this task still owes.
- [ ] **3.3** The on-device mark on a cover, and dimming for a publication that is
      neither downloaded nor reachable — with the accessibility label carrying the
      fact, not the opacity. Screenshot: a grid with all four combinations of
      progress and availability.

      **Android is complete on both layouts. iOS is not — and the previous note's
      "iOS shipped earlier" is the claim that has to be withdrawn.** Android's mark
      is `LibraryMarks.kt:70` (`isKeptOnDevice`, a path comparison against the
      download store's own directory) and its dim is `LibraryMarks.kt:107`
      (`isReadableNow`, `AWAY_ALPHA = 0.45f` at `:31`); both reach the grid
      (`CoverGrid.kt:470`, `:547`, `:655`) **and the list** (`CoverList.kt:151`,
      `:217`, `:222`), and both facts are spoken rather than shown —
      `CoverGrid.kt:516-531` and `CoverList.kt:191-198` join the downloaded and
      unavailable words into the `contentDescription`. 15 cases in `LibraryMarksTest`
      (not the 13 the previous note claimed).

      **What is missing on iOS is most of the surface area.** The dim exists at
      exactly one call site, `SectionedShelf.swift:97`, and `SectionedShelf` is
      mounted only when the layout is a grid **and** the shelf is over the
      twelve-item sectioning threshold (`LibraryContent.swift:58-62`, `:101`). So a
      library of twelve or fewer is not dimmed at all, and `CoverList.swift` has
      **neither the dim nor the on-device mark** — the list is the one surface in
      the app where a reader cannot tell a downloaded book from an unreachable one.
      And where iOS does dim, the fact rides `.accessibilityHint`
      (`SectionedShelf.swift:100`), not the label; `CoverCell.swift:254-285` states
      progress, downloaded and pages and never says unavailable. The task asks for
      the label. iOS's mark itself is fine (`CoverCell.swift:160`, rule at
      `LibraryLookups.swift:44`, spoken at `:272-276`), and its 13 test cases are
      split across `OnDeviceMarkTests`, `CoverCellMarksTests` and
      `UnreadableDimmingTests`.

      Two deliberate differences from iOS's rule are in Android's KDoc and stand:
      *Connecting* counts as answering, so the shelf does not flash grey on every
      launch while sources are probed; and a picked folder whose grant the system
      has withdrawn dims its files even though their path is local, which is a case
      iOS does not have.

      **The capture this task names exists on neither platform.**
      `after-2026-08-30/ios-shelf-two-marks-dark.png` shows the mark; a grid with
      all four combinations of progress and availability, on either platform, is not
      in the tree.
- [ ] **3.4** Section headings in a long library, by series where declared and by
      the sort key otherwise. Screenshot: a library of at least 200 publications.

      **The code is done and genuinely mirrored on both platforms. The capture is
      what is left.** `LibrarySections.swift:44` and `LibrarySections.kt:63` both
      set the threshold at twelve; `divide` is `LibrarySections.swift:53` and
      `LibrarySections.kt:81`; the shared-series gate and the demotion of a series
      the sort scatters are `LibrarySections.swift:131`/`:141` and their Kotlin
      counterparts. `LibrarySectionTests.swift` and `LibrarySectionsTest.kt` hold
      19 tests each, one to one.

      The one shape difference is the word for everything the library cannot place:
      iOS reads it out of its own bundle inside the enum, and a Compose module
      cannot resolve a string without a composition, so it arrives as a parameter
      from the screen. Android draws them as full-span sticky items inside the
      existing `LazyVerticalGrid` (`CoverGrid.kt:194`) rather than as a second shelf
      composable: iOS had to split them because its grid lives in its own
      `ScrollView` and Compose does not, so the shelf keeps one scroll position, one
      column rule and one cell.

      **What is owed:** an Android capture of a sectioned shelf — none exists;
      `after-2026-08-30/ios-library-sections-{light,dark}{,-ax5}.png` is iOS only —
      and, on either platform, a capture that is on record as being a library of at
      least 200. Nothing in the tree says how many publications any shelf capture
      holds.
- [x] **3.5** Wire the iOS views that are already written, translated and
      unreachable — recent searches, the cached notice, the scope control in its
      new availability form, and file import from the empty state. No new strings.
      **All four are wired, and each has a live caller.** Recent searches:
      `RecentSearchSuggestions.swift:13` ← `LibraryView.swift:318`
      (`.searchSuggestions`, on the search surface only), with the store behind it
      live too — `LibraryModel.swift:41` remembers, `:58` clears,
      `Persistence/LibraryPreferences.swift:57` persists. The cached notice:
      `CachedNotice.swift:20` ← `LibraryView.swift:278`, the last branch of the
      bottom `safeAreaBar` chain, with `cachedAt` both set (`LibraryModel.swift:237`)
      and cleared (`:264`, `LibrarySourceHealth.swift:216`) so it leaves as well as
      arrives. The scope control: `ScopeMenu.swift:93` ← `LibraryToolbar.swift:53`.
      File import from the empty state: both empty states reach it —
      `LibraryContent.swift:163-169` (`EmptyLibraryView`) and `:176-180`
      (`LibraryAway`) each raise `isImporting`, presented by
      `LibraryView.swift:190` → `LibraryImportAction.swift:31` → `LibraryImports.swift:23`.

      **"No new strings" was not held, and it is recorded here rather than glossed.**
      Five keys were added to `LibraryFeature/Resources/Localizable.xcstrings` for
      this wiring — `library.availability.from`, `library.availability.from.all`,
      `library.availability.onDevice`, `library.availability.widen` and
      `library.cell.unavailable`. All five carry all four locales, so nothing is
      broken and no reader sees an English fallback. The rider was written when the
      task was expected to be pure wiring; giving the availability axis its own
      vocabulary is what overtook it. `publication-detail` task 3.5 was overtaken
      the same way and by a larger margin — see that file.

## Phase 4 — Large screens

- [ ] **4.1** **[K1]** iPad: the sidebar's sections and shelves, with no source
      entry; shelves touching the leading and trailing edges; the settings measure
      capped. Screenshot: iPad Pro portrait and landscape, and in Split View.

      **Three of the four clauses are done. The settings measure is the one that is
      not, and it is a one-line miss.** The sidebar has both sections —
      `LibrarySidebar.swift:113` gives a *Library* `TabSection` (`:115` recently
      added, `:132` series) and a *Shelves* one (`:150` collections, `:165` lists,
      `:182` all shelves), inline shelves capped at eight (`:104`) with *All
      shelves* as the overflow, and the whole thing gated to a regular size class
      at `:107`. No source entry survives: `SidebarEntry` has five cases
      (`:19-29`) and none of them reads the registry. Shelves touch both edges —
      every horizontal row puts its gutter on the scroll *content*
      (`HomeRow.swift:90`, `HomeHero.swift:119`, `DetailSeriesShelf.swift:43`), so
      the scroll view itself is edge to edge.

      **The cap is written and never applied to Settings.**
      `LibrarySidebar.swift:47-49` defines
      `SidebarLayout.maxContentWidth = 720`, and its three call sites are
      `HomeScreen.swift:228`, `PublicationDetailView.swift:70`/`:82` and
      `LibrarySidebar.swift:269`. `SettingsFeature/SettingsView.swift:106-176` is a
      bare `List` with no width constraint, and `StoryArcApp.swift:177` presents it
      as a plain sheet with none either — the only `frame(maxWidth:` in the whole
      of `SettingsFeature` is `.infinity` at `AboutSettings.swift:91`. The direction
      asks for it by name at `ui-revamp-2026-08.md:456`. **To close: apply
      `SidebarLayout.maxContentWidth` to the settings list**, then capture.

      **No capture for this task exists.** iPad Pro portrait, landscape and Split
      View are all owed; the iPad shots that do exist
      (`after-2026-08-30/ios-ipad-sidebar-sections-*.png`) are portrait only and
      were taken for the sidebar rather than for this.
- [ ] **4.2** **[K2]** Android: Material's five breakpoints replacing the
      two-valued window class, the collapsed and expanded rail, and the two-pane
      scaffold. Screenshot: compact, medium and expanded, and a foldable half-open.

      **The code is done, and done well; one capture of the four is missing.**
      `core/designsystem/…/theme/WindowClass.kt:36-54` is the five-case enum —
      `COMPACT(0)`, `MEDIUM(600)`, `EXPANDED(840)`, `LARGE(1200)`,
      `EXTRA_LARGE(1600)` — with the table at `:128-131` and the lookup at
      `:114-115`. It is verified against Material rather than restated:
      `WindowClassTest.kt:54-75` asserts each bound equals the matching
      `WindowSizeClass.WIDTH_DP_*_LOWER_BOUND`. The old two-valued split at 600 dp
      is gone and the rail/pane boundary moved to 840 (`WindowClass.kt:62`).
      The rail is `AdaptiveNavigation.kt:163-185`, collapsed or expanded from
      `:140-147` with secondary entries added only while open (`:176`). The
      two-pane scaffold is Material's own — `navigation/Panes.kt:57`
      (`ListDetailPaneScaffold`), used at `AppPanes.kt:100` — and deliberately not
      `NavigableListDetailPaneScaffold`, for the one-back-rule reason at
      `Panes.kt:25-33`.

      **What is owed is the foldable half-open capture.**
      `after-k2-android-tablet/` has compact (360 × 800), medium (800 × 360) and
      large (1280 × 576) with its own README saying so, and
      `after-2026-08-31/android-tablet-{rail-home,two-panes,empty-pane}-light.png`
      adds the tablet at 1600 × 2560. Nothing in the tree shows a fold at half-open.
      `WindowClassTest.kt:117` argues a fold is an ordinary resize because only the
      width is read, which lowers the risk but is not the capture the task asks for.
- [ ] **4.3** Verify the resize path: a two-pane window narrowed to one pane keeps
      what the reader was looking at, and widening restores the second pane.

      **The property holds by construction on Android and is asserted by no test on
      either platform.** `PaneSplit.of(navigation, windowClass)` (`AppPanes.kt:47-56`)
      is a pure read of the width that never writes to the navigation; the open
      publication lives in `AppNavigation.stacks` (`AppNavigation.kt:27`), hoisted
      above every layout branch in one `rememberSaveable` (`AppShell.kt:69-71`); and
      `AndroidManifest.xml:29` keeps a resize or a fold from recreating the
      activity, so the composition simply reads a new number.

      **What is missing is a test that walks the sequence.** `PaneSplitTest.kt`
      asserts the two ends separately — `:39` that a compact window has no split,
      `:65`/`:75` that expanded and above do — and never narrows and widens the same
      value to check the page came back. **And one thing weakens the construction
      argument and should be in the same test:** `AppNavigation.Saver`
      (`AppNavigation.kt:143-152`) persists only the destination name and discards
      the stack, so the guarantee rests entirely on that manifest line; any config
      change outside its list loses the open page. iOS has no pane, so on iOS this
      task is unmeetable until 4.1 gives it one — see `publication-detail` task 4.3.

## Phase 5 — First run and the empty path

- [ ] **5.1** **[M1/M2]** The first-run empty state on both platforms: one
      sentence, one action that opens a comic with no configuration, one plain
      secondary. The four source types move one level down. Screenshot: first
      launch, both platforms, largest text size.

      **The shape is right on all four surfaces. The last clause is met on the
      library's empty state and deliberately not on Home's, on both platforms.**
      One sentence, one zero-configuration primary, one plain secondary:
      `HomeEmpty.swift:20-53` and `LibraryStates.swift:130-171` on iOS;
      `HomeScreen.kt:387-410` and `LibraryStates.kt:86-129` on Android. The four
      source types are one level down on the library's:
      `AddSourceMenu.swift:24-36` behind the secondary at `LibraryStates.swift:160`,
      and `AddBooksButton` at `LibraryStates.kt:196-231` behind `:121`.

      **On Home, both platforms send the secondary straight to a folder picker** —
      `HomeScreen.swift:78` into a `.fileImporter(allowedContentTypes: [.folder])`,
      `HomeScreen.kt:407` into `onAddFolder` — so the other three types are named
      nowhere on that surface. Android says so at `HomeScreen.kt:380-385`: "The
      secondary is a folder, not a menu of four… The other three are named in the
      library's own empty state, one destination along." The two platforms agree
      with each other, which reads as a decision rather than a miss. **Whoever
      closes this decides which it is** — the task says "the first-run empty state",
      singular, and there are two per platform. Either bring Home's secondary to the
      menu, or write the split into the delta.

      Captures exist and include the largest text size:
      `firstrun-2026-08-30/{ios,android}-home-firstrun-{light,dark}.png` and
      `{ios,android}-library-empty-dark-largest.png`.
- [x] **5.2** Every empty state in the three destinations, checked against the
      delta's rule that an empty section is absent rather than rendered empty.
      **Checked, six destination/platform pairs, and every section tests its own
      content before it draws.** Home: iOS `HomeScreen.swift:138`, `:139`, `:140`,
      `:144`; Android `HomeScreen.kt:196`, `:256`, `:274`, with the first-run branch
      returning early at `:141-144`. Library: iOS `LibraryContent.swift:100-176` is
      one exhaustive chain from a populated shelf down through narrowed-to-nothing,
      scanning, first run and sources-away; Android `LibraryScreen.kt:465-532` is the
      same chain, plus the notice bars at `LibraryView.swift:260-271` and
      `CoverGrid.kt:356-378` which draw nothing when no branch holds. Downloads:
      `DownloadsDestination.swift:81`/`:89`/`:91` and
      `DownloadsDestination.kt:120`/`:137`/`:147`.

      **Three things this pass found and deliberately did not fix**, each outside
      the rule but next to it:

      - **iOS Home's Shelves row is unconditional.** `HomeScreen.swift:142` draws
        `shelvesLink` whatever the reader owns, so a reader with no collections and
        no lists still gets a row into `ShelvesView`. It is a navigation entry
        rather than a heading over a gap, which is why it is not counted as a
        breach; Android's Home has no counterpart at all, which is the same
        divergence task 2.1 records from the other side.
      - **`LibraryContent.swift:132-137` is unreachable.** `LibrarySurface.onDevice`
        is constructed nowhere since `AppShell.swift:89-98` replaced
        `library(.onDevice)` with `DownloadsDestination`, so `OnDeviceEmpty` and the
        `library.downloads.title` case at `LibraryView.swift:287` are dead.
      - **The space total can read *Zero KB* under a full shelf** — see task 2.3.

## Phase 6 — Gates

- [x] **6.1** `corepack pnpm spec:validate`. **Green**, 2026-08-31 at `6c931e61`:
      23 items passed, 0 failed, this change among them.
- [ ] **6.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm build:ios`. No Swift file over 400 lines.
      **The line-count clause holds today and the four commands were not run in
      this documentation pass.** Not one of the 468 Swift files in `apps/ios` is
      *over* 400 lines; the largest is `Sources/Formats/EpubReader.swift` at exactly
      400, then `ComicArchive.swift` at 399 and `PublicationIndexer.swift` at 396.
      Nothing this change owns is close: `LibraryModel.swift` is 384 and
      `LibraryView.swift` is 358.

      Worth knowing before this is ticked: **no script enforces the cap.**
      `package.json:22` (`lint`) runs ten checks and none of them counts a line, and
      neither does `check` at `:30`. The 400 is a convention in
      [AGENTS.md](../../../../AGENTS.md), kept by hand, which is why the margin is
      one line.
- [ ] **6.3** Android: `./gradlew test lint`. No Kotlin file over 800 lines —
      `MainActivity.kt` and `LibraryScreen.kt` both start over it.
      **Both files the task named are fixed, and the previous note's replacement
      list was wrong in two ways.** `MainActivity.kt` is 179 lines and
      `LibraryScreen.kt` is 730 — the note said 697, and it has grown since. The
      note also called `LibraryViewModel.kt` "the largest violation in the
      repository" at 1701 lines. It is 1717, and it is not the largest.

      **The real list, counted at `6c931e61` over 419 Kotlin files, excluding build
      output — five files over the cap:**

      | Lines | File |
      | ---: | --- |
      | 1893 | `feature/reader/…/reader/ReaderScreen.kt` |
      | 1717 | `feature/library/…/library/LibraryViewModel.kt` |
      | 1051 | `feature/epubreader/…/epubreader/EpubReaderActivity.kt` |
      | 911 | `feature/epubreader/…/epubreader/ThemeSheet.kt` |
      | 811 | `feature/reader/…/reader/ReaderViewModel.kt` |

      The next three are under it and worth watching: `CoverGrid.kt` 769,
      `LibraryScreen.kt` 730, `EpubReaderViewModel.kt` 728. As on iOS, no script
      counts lines — `pnpm lint:android` is `gradle lint`, which has no such check —
      which is how five files got here.

      **`LibraryViewModel.kt` is left as a slice of its own, deliberately.** iOS
      solved the same problem by spreading `LibraryModel` over eight files —
      `LibraryScanning`, `LibraryWatching`, `LibraryImports`, `LibraryLookups`,
      `LibraryFacets`, `LibrarySources`, `LibraryRestore` — each an
      `extension LibraryModel` and each under its own 400-line cap. That option does
      not exist here: Kotlin cannot extend a class across files, so the same seams
      have to become real collaborators with real interfaces between them, each
      holding a share of the state the whole class currently reads at will. The
      largest of them, the folder scanner, is roughly 740 lines and touches
      `_publications`, `_registry`, `locations`, `_scanState`, `rebuild()` and
      `cacheLibrary()` — and there is no `LibraryViewModelTest` to catch a mistake,
      so the split would be done with a screenshot as its only proof. That is a
      design job with a test suite in front of it, not a file move.

      **`ReaderScreen.kt` at 1893 is the larger job and belongs to nobody yet.** It
      is not this change's file — the shell, the shelf and the marks never touch it
      — so naming it here is the whole of what this task can honestly do about it.
- [x] **6.4** `corepack pnpm lint`. **Green**, 2026-08-31 at `6c931e61`, exit 0:
      tokens contrast, `spec:validate`, tokens in sync, the fixture corpus, third-party
      notices, the libarchive pin, the iOS lockfile, the corpus self-test, the Kavita
      mock self-test, and `strings:ios` — every key resolving in en, fr, de and es.
- [ ] **6.5** The screenshot set is complete: every task above that changes a
      screen has its light, dark, default-size and largest-size captures beside the
      before set, and the handoff references them.

      **Not complete. Six captures are owed, and this is the list:**

      1. **iPad landscape**, one pass per destination — task 1.2. Every one of the
         sixteen iPad PNGs in `after-2026-08-30/` is 2064 × 2752, portrait.
      2. **A grid with all four combinations of progress and availability**, either
         platform — task 3.3.
      3. **An Android sectioned shelf**, and on either platform a shelf on record as
         holding at least 200 publications — task 3.4.
      4. **The filter sheet in its by-library form**, either platform — task 3.2.
      5. **iPad Pro portrait, landscape and Split View** for the sidebar and the
         capped settings measure — task 4.1.
      6. **An Android foldable at half-open** — task 4.2.

      One thing that would make this task cheaper next time: `after-2026-08-30/`
      has **no README**, unlike `after-2026-08-31/` and `after-k2-android-tablet/`,
      so its 133 captures have to be identified by filename alone. Several of them
      cannot be — `ios-detail-iphone-contrast-*` is read as *increased* contrast by
      convention and nothing in the repository says so.

## Delta merge, 2026-09-04 — not this change's own work

`pnpm delta:drop` gained a check for **two active changes carrying a `## MODIFIED` delta on
one requirement**, and this change was one side of a pair. A MODIFIED requirement replaces the
whole block, so whichever of the two synced second would have deleted the other's scenarios —
silently, after the first change had archived and its delta was gone.

The pair was `library-browsing` → *Presentation*, with
`named-failures-and-quieter-chrome`. That change adds a grouping rule and three scenarios —
*The controls that change the view are grouped*, *A control that stands alone carries a name*,
*An ordering says that it is an ordering* — to a requirement this change rewrites wholesale,
and the two blocks were disjoint in both directions. **This change's block now carries all
three plus the grouping clause**, which makes it a strict superset, and the sync order
(`named-failures` first, this change second) is recorded in `.delta-drops.json`. Do not remove
them to keep this delta about the destinations: that reopens the drop.

Nothing here changes what this change builds or what its tasks say. It is recorded because the
edit lands in this change's delta and `openspec-guard` would otherwise report the plan as
having moved after the task list for no visible reason.
