# Tasks — one bar, a search page, and a word about what changed

Every task is test-first: the assertion is written and seen to fail before the
behaviour is built. Gates named per task are the smallest set covering the change;
the full gate list is in [`AGENTS.md`](../../../../AGENTS.md) §6.

## 1. Search becomes a destination

- [x] 1.1 iOS: `LibraryDestinationTests` — extend the destination set to four and
      assert the order is home, library, downloads, search, and that `all(for:)`
      still ignores the source registry. Fails before `LibraryDestination` gains
      `.search`.
- [x] 1.2 iOS: add `case search` to `LibraryDestination` with its symbol, and
      delete `AppShell.Selection.search` — the shell addresses it as a destination
      like the other three now.
- [x] 1.3 iOS: `AppShell.swift` — `Tab(value: .destination(.search))` with no
      `role:`. Rewrite the doc comment that defends the role: keep the argument it
      made, say why it no longer holds.
- [x] 1.4 iOS: `ShellWiringTests` (new, source-level, in the manner of
      `CoverRoutingWiringTests`) — assert no `role: .search` remains in
      `AppShell.swift`. Mutation-check: restoring the role fails it.
- [x] 1.5 Android: `LibraryDestinationTest` — the same four-entry assertion against
      the Kotlin enum, so the two platforms' sets stay in step.
- [x] 1.6 Android: add the destination to the enum and to `AdaptiveNavigation.kt`'s
      item list, which builds bar, collapsed rail and expanded rail from one list.
- [x] 1.7 Android: `AdaptiveNavigationTest` — at `ShortNavigationBarMedium`, assert
      `iconPosition = NavigationItemIconPosition.Start` and
      `arrangement = ShortNavigationBarArrangement.Centered`. Material requires
      horizontal items in medium windows and the file composes its own items, so it
      inherits neither.
- [x] 1.8 Android: pass both. Gates: `pnpm gradle`, `pnpm build:android:tests`.
- [x] 1.9 Both: `pnpm capture:ios` / `pnpm capture:android home` before and after,
      into `docs/designs/screenshots/`, at default and largest text size. §6 owes a
      control shot for a visible change.
- [x] 1.10 Android: `pnpm capture:android` gains a `Search` route. The table had none —
      before section 1 there was no destination to walk to — and the previous batch took its
      search shots by hand and said adding one was worth doing.

## 2. The search screen

- [x] 2.1 iOS: `SearchScreenTests` — with an empty query, the screen offers recent
      searches and three suggestion kinds (in progress, never opened, next in
      series), and every suggestion resolves to a publication already in the model.
- [x] 2.2 iOS: build the at-rest sections in `LibraryView(surface: .search)`. Do not
      use `.searchSuggestions` — it attaches a list to the field and what is wanted
      is a screen with headed sections.
- [x] 2.3 iOS: `.searchScopes` for the everything/on-device narrowing, persisted.
- [x] 2.4 iOS: `SearchScreenTests` — nothing to suggest gives one sentence and the
      library's own add-a-source action, not empty headings.
- [x] 2.5 Android: `LibrarySearchBarTest` — the contained branch uses
      `rememberContainedSearchBarState` and the docked branch
      `rememberSearchBarWithGapState`. Each expanded bar names its required state
      partner in its own KDoc and only those carry the content-fade specs.
- [x] 2.6 Android: hoist the state per branch; thread
      `SearchBarDefaults.containedColors(state)` through `appBarWithSearchColors`
      into both bar and input field.
- [x] 2.7 Android: move `AppBarWithSearch` into `Scaffold(topBar =)` and pass
      `SearchBarDefaults.enterAlwaysSearchBarScrollBehavior()`.
- [x] 2.8 Android: hand-write the leading-icon swap — magnifier collapsed, back
      arrow calling `animateToCollapsed()` expanded. Material requires the back icon
      to release focus and no API supplies it.
- [x] 2.9 Android: hand-write the clear-the-query trailing icon. `SearchBarDefaults`
      has no clear affordance of any kind.
- [x] 2.10 Android: narrowing as `FilterChip`s, **not** a segmented control — that
      component is retired in Expressive and its replacement is specified for two to
      five fixed views, which our source set is not.
- [x] 2.11 Android: result rows as `ListItem(content =, leadingContent =)` with a
      transparent container; group by gap and `SegmentedListItem`, not dividers.
- [x] 2.11b Android: `SearchSuggestionsTest` — the three sections over `LibraryIndex` and
      `HomeShelves.upNext`, disjoint, capped, ordered by arrival, and `isEmpty` for the
      screen that says so in one sentence. Its own type over `HomeEntry`, **not** a port of
      iOS's `SearchSuggestions` — that one is a composition over its own home shelves and
      hands the screen bare publications.
- [x] 2.11c Android: `SearchAtRest` draws them — the scope stated before a letter is typed,
      a heading only over a section that has something, and one sentence with the two ways in
      that need only a system picker when there is nothing to suggest. `SearchAtRestTest`
      (Robolectric) asserts which headings exist, which no pure test can. The three network
      transports need one line each in `SearchDestination`; `:app` is another agent's this
      round and they are absent rather than drawn dead.
- [x] 2.11d Android: the scope chips wrap. At `font_scale 2.0` in a 320 dp window a plain
      `Row` drew *On this device* over four lines with a lone "e" on the last —
      photographed, fixed, photographed again.
- [x] 2.11e Android: a suggestion the reader has never opened announces its title alone. Read
      off the device's accessibility tree: every card under *You have never opened these* said
      "…. Part-read", because `homeRemainingText`'s fallback is true of every shelf Home draws
      it for and false of two of the three here. **Home still has it** on Up next, Recently
      added and Finished; that is its own change.
- [x] 2.12 Android: the scope chips reach the fan-out. `SearchScopeTest` — narrowing asks
      nobody, drops what cannot be read with no network, empties no heading over it, and
      leaves `waiting` and `silent` empty; `LibraryPreferencesTest` — the choice is written
      down under its own key, not the shelf's. iOS's half landed with 2.3.
- [x] 2.12b Both: recent searches persist and clear. Assert the clear empties them and
      that reaching search does not itself record a query.
      iOS `RecentSearchMemoryTests`, Android `RecentSearchMemoryTest` — the same four
      assertions in the same order on both platforms. Android's runs under **Robolectric**
      rather than as a source-level tripwire, because `LibraryViewModel` takes an
      `Application` and `LibraryPreferences` wraps `SharedPreferences`; `feature/library`
      already had the dependency wired and `feature/settings` had already set the
      precedent, so this is a real behaviour test on both sides.
      Mutation-checked on both: drop the store write from `clearRecentSearches()` and the
      clear test fails; make the arrival record a term and two tests fail.
- [x] 2.13 Both: a query typed while a source is unreachable shows local results and
      names the source once, in the results. Assert nothing waits on it.
      **Already asserted before this change**, case for case, by
      `SearchListingTests.swift` and `SearchListingTest.kt`: *what the device holds
      is the whole answer until something else replies*, *a library that could not
      answer is named once however often it is asked*, and *a library that fails
      leaves the rows already on screen alone*. Both suites were run; the iOS one
      was mutation-checked by appending the notice unconditionally.

## 3. What's new

- [x] 3.1 Both: `WhatsNewTests` / `WhatsNewTest` — first launch ever shows nothing
      and records the version as seen; a version change shows the entry once; a
      second launch at the same version shows nothing; a version with no entry shows
      nothing and still records.
- [x] 3.2 Both: the changelog entries ship with the app as a resource, keyed by
      version, localised in the four shipped languages. Nothing is fetched.
- [x] 3.3 iOS: present as a `.sheet` with `.presentationDetents([.large])` from
      `AppShell` on first appearance after a version change.
- [x] 3.4 Android: present as a `ModalBottomSheet`. Not a full-screen dialog:
      Material reserves those for multi-step tasks with unsaved state at compact
      widths only, and this app runs on tablets.
- [x] 3.5 Both: write the seen flag when the screen is **shown**, not when it is
      dismissed — a reader who swipes it away has still seen it.
- [x] 3.6 Both: reachable afterwards from About, with earlier versions listed, and
      reaching it that way does not change what is considered seen.
- [x] 3.7 Both: assert at the largest accessibility text size that every heading and
      sentence is readable in full and the dismissing action stays reachable.
      Android: fixed-dp icon column that does not scale with `fontScale`, content
      scrollable, Continue pinned.

## 4b. Why this change could not be archived, and what unblocked it

**Archiving it would have lost a requirement.** Its `navigation-shell` delta modified
*Reaching search*, and `navigation-shell` **has no main spec**: it is a new capability
`one-library-three-destinations` introduces and has not synced. So the sync merged the
other two deltas and skipped this one, and an archive — which moves the change directory
away — would have carried that requirement off, never having reached the contract.

`--skip-specs` does not help: it is the flag that says the specs are already updated, and
for that one delta they were not.

**The wait was resolved by reconciling rather than by waiting, on 2026-09-01.** The plan of
record was for this change to sit until `one-library-three-destinations` synced. Re-reading
the two deltas showed that was not merely slow but wrong. This change's own proposal set the
condition:

> This one adds a destination and removes a role; it touches no requirement that change
> wrote. If that stops being true, the two must be reconciled before either syncs, not after.

**It was never true.** `one-library-three-destinations`'s ADDED block contains
`### Requirement: Reaching search`, and this change's MODIFIED delta named exactly that
requirement. The trigger was met the day the delta was written, and nobody noticed because
`openspec validate` passes a MODIFIED delta whose target does not exist in any main spec —
the same validator gap `brand-identity-and-app-icons` records at the foot of its own task
list. Only `archive` would have caught it, at the point where the delta could no longer be
applied.

**So the rewritten requirement moved to the change that creates the capability.** It now
lives in
[`one-library-three-destinations`](../one-library-three-destinations/specs/navigation-shell/spec.md)
as the ADDED *Reaching search*, replacing that change's superseded first draft, and carrying
a note recording where it came from, what the old text said, and why the app disproved it.
This change no longer carries a `navigation-shell` delta.

**Nothing about the shipped behaviour changed, and no task here changed.** The work is in
this change — sections 1 and 2 built it and their captures are on record — and the
requirement is stated by the change that owns creating the capability. Which change *builds*
a behaviour and which change *creates the capability's spec* are allowed to differ; a
requirement with nowhere to merge into is not.

With that delta gone, this change's two remaining deltas are both synced, and it is ready to
verify and archive.

## 4. Docs and close-out

- [x] 4.1 Update `docs/designs/ui-revamp-2026-08.md` with the search-as-destination
      decision and the reason the earlier `Tab(role: .search)` finding is superseded.
- [x] 4.1b Rewrite divergence register row 1, which still described both platforms as they
      were before section 1, and add rows 14–16: the bar's container, the narrowing control,
      and where recent searches sit.
- [x] 4.2 Update `docs/openspec/STATUS.md`.
- [x] 4.3 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [x] 4.4 `pnpm spec:guard:strict` — 0 errors, 1 warning, and that warning is the
      pre-existing orphan list.
- [x] 4.5 Verified and synced on 2026-08-31. Main specs updated; the change stays
      open, per the lifecycle.
      **`navigation-shell` was not synced, and on 2026-09-01 stopped needing to be.** It has
      no main spec: it is a new capability `one-library-three-destinations` introduces and
      has not synced, so there was nothing to merge into, and creating one from this
      change's single requirement would have published a fraction of the capability as if it
      were the whole contract. The delta has since been reconciled into that change — the
      two named the same requirement, which the proposal said must trigger a
      reconciliation — and §4b records what moved and why.
      **The sync surfaced a coordination problem worth recording.** Two other open
      changes carried MODIFIED deltas on requirements this one changed, and a
      MODIFIED requirement replaces the whole block — so archiving either of them
      later would have silently dropped the scenarios added here.
      `openspec validate --all` caught it; the missing scenarios are carried into
      `one-library-three-destinations` and `reader-theming-and-page-transitions`
      with a note saying where they came from.
