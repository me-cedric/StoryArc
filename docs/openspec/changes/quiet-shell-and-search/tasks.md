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
- [ ] 1.5 Android: `LibraryDestinationTest` — the same four-entry assertion against
      the Kotlin enum, so the two platforms' sets stay in step.
- [ ] 1.6 Android: add the destination to the enum and to `AdaptiveNavigation.kt`'s
      item list, which builds bar, collapsed rail and expanded rail from one list.
- [x] 1.7 Android: `AdaptiveNavigationTest` — at `ShortNavigationBarMedium`, assert
      `iconPosition = NavigationItemIconPosition.Start` and
      `arrangement = ShortNavigationBarArrangement.Centered`. Material requires
      horizontal items in medium windows and the file composes its own items, so it
      inherits neither.
- [ ] 1.8 Android: pass both. Gates: `pnpm gradle`, `pnpm build:android:tests`.
- [ ] 1.9 Both: `pnpm capture:ios` / `pnpm capture:android home` before and after,
      into `docs/designs/screenshots/`, at default and largest text size. §6 owes a
      control shot for a visible change.

## 2. The search screen

- [ ] 2.1 iOS: `SearchScreenTests` — with an empty query, the screen offers recent
      searches and three suggestion kinds (in progress, never opened, next in
      series), and every suggestion resolves to a publication already in the model.
- [ ] 2.2 iOS: build the at-rest sections in `LibraryView(surface: .search)`. Do not
      use `.searchSuggestions` — it attaches a list to the field and what is wanted
      is a screen with headed sections.
- [ ] 2.3 iOS: `.searchScopes` for the everything/on-device narrowing, persisted.
- [ ] 2.4 iOS: `SearchScreenTests` — nothing to suggest gives one sentence and the
      library's own add-a-source action, not empty headings.
- [ ] 2.5 Android: `LibrarySearchBarTest` — the contained branch uses
      `rememberContainedSearchBarState` and the docked branch
      `rememberSearchBarWithGapState`. Each expanded bar names its required state
      partner in its own KDoc and only those carry the content-fade specs.
- [ ] 2.6 Android: hoist the state per branch; thread
      `SearchBarDefaults.containedColors(state)` through `appBarWithSearchColors`
      into both bar and input field.
- [ ] 2.7 Android: move `AppBarWithSearch` into `Scaffold(topBar =)` and pass
      `SearchBarDefaults.enterAlwaysSearchBarScrollBehavior()`.
- [ ] 2.8 Android: hand-write the leading-icon swap — magnifier collapsed, back
      arrow calling `animateToCollapsed()` expanded. Material requires the back icon
      to release focus and no API supplies it.
- [ ] 2.9 Android: hand-write the clear-the-query trailing icon. `SearchBarDefaults`
      has no clear affordance of any kind.
- [ ] 2.10 Android: narrowing as `FilterChip`s, **not** a segmented control — that
      component is retired in Expressive and its replacement is specified for two to
      five fixed views, which our source set is not.
- [ ] 2.11 Android: result rows as `ListItem(content =, leadingContent =)` with a
      transparent container; group by gap and `SegmentedListItem`, not dividers.
- [ ] 2.12 Both: recent searches persist and clear. Assert the clear empties them and
      that reaching search does not itself record a query.
- [ ] 2.13 Both: a query typed while a source is unreachable shows local results and
      names the source once, in the results. Assert nothing waits on it.

## 3. What's new

- [ ] 3.1 Both: `WhatsNewTests` / `WhatsNewTest` — first launch ever shows nothing
      and records the version as seen; a version change shows the entry once; a
      second launch at the same version shows nothing; a version with no entry shows
      nothing and still records.
- [ ] 3.2 Both: the changelog entries ship with the app as a resource, keyed by
      version, localised in the four shipped languages. Nothing is fetched.
- [ ] 3.3 iOS: present as a `.sheet` with `.presentationDetents([.large])` from
      `AppShell` on first appearance after a version change.
- [ ] 3.4 Android: present as a `ModalBottomSheet`. Not a full-screen dialog:
      Material reserves those for multi-step tasks with unsaved state at compact
      widths only, and this app runs on tablets.
- [ ] 3.5 Both: write the seen flag when the screen is **shown**, not when it is
      dismissed — a reader who swipes it away has still seen it.
- [ ] 3.6 Both: reachable afterwards from About, with earlier versions listed, and
      reaching it that way does not change what is considered seen.
- [ ] 3.7 Both: assert at the largest accessibility text size that every heading and
      sentence is readable in full and the dismissing action stays reachable.
      Android: fixed-dp icon column that does not scale with `fontScale`, content
      scrollable, Continue pinned.

## 4. Docs and close-out

- [ ] 4.1 Update `docs/designs/ui-revamp-2026-08.md` with the search-as-destination
      decision and the reason the earlier `Tab(role: .search)` finding is superseded.
- [ ] 4.2 Update `docs/openspec/STATUS.md`.
- [ ] 4.3 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 4.4 `agent-compass openspec-guard . --strict`.
- [ ] 4.5 `/opsx:verify quiet-shell-and-search`, then `/opsx:sync`.
