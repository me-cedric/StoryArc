**What a tick means.** The code exists and something asserts it — a JVM unit
test, a host Swift test, or a committed screenshot. A tick does not mean a
reader has used the screen.

**Where the order was not test-first, it says so.** The pure types and their
tests landed together rather than red-then-green. What the tests are worth is
recorded per task instead of implied by an order nobody can check afterwards.

## 1. A server's shelf can be written down

- [x] 1.1 `RememberedShelf` in `core/model/RememberedShelf.kt` and `StoryArcCore/RememberedShelf.swift`, modelled on `ShelfPin` token for token. Both kinds, the source, the server's own id and the title, in one string.
- [x] 1.2 `RememberedShelfTest` (9 cases) and `RememberedShelfTests` (9 cases), case for case: both kinds round-trip, a title holding a colon survives, a title holding spaces survives the stored scalar, an unreadable token is dropped rather than guessed, and what is written down is sorted. **Written beside the type, not before it.** The parse is a `split` with a limit, and the colon case is the one that would fail if that limit moved.
- [x] 1.3 One key in `LibraryPreferences` (`rememberedShelves()` / `saveRememberedShelves()`), beside `pinnedShelves`, and `RememberedShelf.storageKey` on iOS. Verified by `:core:persistence:testDebugUnitTest` and `swift test`, neither of which changed.

## 2. The shelves screen remembers what a server answered

- [x] 2.1 Android: the fetch in `ShelvesScreen.kt` writes the record, replacing it wholesale, and skips the write when no server answered.
- [x] 2.2 iOS: `ServerShelves.record` is that same rule as one property, and `ShelvesView`'s `.task` assigns it. One line there, because that file is six lines under its 400-line cap.
- [x] 2.3 `HomeShelfIndex.remembering` is the pure mapping, asserted on both platforms: a fetch of two collections and one list becomes three records carrying both kinds, and a later fetch that finds one shelf writes one. **The skip-when-nothing-answered branch is code on both platforms and is asserted by neither** — it reads view state inside a `LaunchedEffect` and a `.task`, which no host suite reaches.

## 3. The listing is assembled, purely

- [x] 3.1 `HomeShelfListing.kt` and `HomeShelfListing.swift`: `HomeShelfSummary`, `HomeShelfDestination`, `HomeShelfListing` and one `assemble`. No Compose, no SwiftUI, no view model.
- [x] 3.2 `HomeShelfListingTest` (13 cases) and `HomeShelfListingTests` (13 cases), case for case: the two halves; an empty listing; one kind only; a list has a position and a collection has none; four tiles; an empty shelf still appears; a remembered shelf is listed, labelled and states no count; a remembered shelf whose source has gone is left out; pinned shelves lead; keys are unique.
- [x] 3.3 `ShelfComposite` in Android's `ShelfCover.kt` is `internal`, matching iOS. `ShelfProgressRail` was extracted from `ShelfCard` in the same file so the home surface and the shelves screen draw one rail. `ShelfCoverTest` and `ServerShelfCoverTest` pass unchanged.

## 4. The home surface draws it

- [x] 4.1 `HomeShelvesRow.kt` and `HomeShelvesRow.swift`: a heading that leads to the shelves screen, and a row of cards. iOS reuses `ShelfCard`; Android composes `ShelfComposite` and `ShelfProgressRail` itself, because `ShelfCard` resolves its own artwork through a view model and the home surface deliberately holds none.
- [x] 4.2 Both wired into `HomeScreen`, between Recently added and the pinned shelves. Each shelf returns early when its half is empty. **Asserted by no screen test on either platform** — what is asserted is the assembly that decides whether a half is empty.
- [x] 4.3 Android: `HomeDestination.kt` assembles the listing, filters to the sources `KavitaPage.of` can build, and routes a card to `Screen.Collection`, `Screen.ReadingList` or `Screen.ServerShelfPage`.
- [x] 4.4 iOS: `HomeScreen.swift` assembles the same listing from `model.shelves`, `model.registry`, the secure store and `rememberedShelves`, and routes to `CollectionDetail`, `ReadingListDetail`, `KavitaCollectionView` or `KavitaListView`. The `shelvesLink` row it used to carry is now drawn only when there is nothing to list, because with shelves drawn two headings already lead there.
- [x] 4.5 No new user-facing string. The headings are `shelves_collections` / `shelves_lists` and `shelves.collections` / `shelves.lists`; the caption is `shelves_count` / `shelves.count`. `git status` names no `strings.xml` and no `.xcstrings`.
- [x] 4.6 `shelfSubtitle(count:sourceName:)` extracted on iOS so the home card and `ShelvesView`'s own subtitle are one sentence. **Android still has two**, `homeShelfCaption` and `ShelvesScreen`'s `caption`, because the second takes a `ShelfOrigin` and a source list rather than a resolved name.

## 5. Gates

- [x] 5.1 `pnpm lint` — exit 0, twenty checks.
- [x] 5.2 `pnpm spec:guard` — passed with 7 warnings, none of them this change.
- [x] 5.3 `pnpm gradle :core:model:testDebugUnitTest :core:persistence:testDebugUnitTest :feature:library:testDebugUnitTest :app:compileDebugKotlin` and `:lint` on all four — all passed.
- [x] 5.4 `swift test` in `apps/ios/Packages/StoryArcKit` — 2456 tests in 323 suites passed. `swiftlint lint --strict` reports 0 violations in 800 files.

## 6. Not done

- [ ] 6.1 Screenshots from a booted emulator and simulator, light and dark, at default and largest text size. Nothing in this change has been photographed.
- [ ] 6.2 A remembered shelf's artwork. Its members are chapters on a server, so its card is a cover-shaped blank until something caches server artwork on the device. Named in `design.md` under Risks.
- [ ] 6.3 OPDS contributes nothing. `opds-catalog` models no collection and no reading list, so there is nothing to list. Named in the proposal's Non-Goals.
- [ ] 6.4 A server's shelf renamed or deleted between two visits to the shelves screen keeps its old name on the home surface until the next visit. Named in `design.md` under Risks, and asserted by nothing.
