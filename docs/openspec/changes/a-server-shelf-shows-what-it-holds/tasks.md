**What a tick means.** The code exists and something asserts it — a unit test, a
Robolectric or XCTest suite, or a committed screenshot with the control frame
beside it. A tick does not mean a reader has used the screen; a screenshot task
says which device and which appearance it was taken on.

## 1. The wire carries what the screens need

- [x] 1.1 Write `KavitaReadingListDecodingTest` (Kotlin, `core/kavita`) and its Swift twin, decoding a captured `ReadingList/items` payload, and assert `pagesRead` and `pagesTotal` survive on every entry. Red before 1.2.
- [x] 1.2 Add `pagesRead` and `pagesTotal` to `KavitaReadingListItem` (`apps/android/core/kavita/.../KavitaShelves.kt:29`) and to the Swift model in `Sources/Kavita/KavitaShelves.swift`. Verify 1.1 passes on both.
- [x] 1.3 Write the decoding assertion for `coverImage`, `coverImageLocked` and `itemCount` on `KavitaReadingList`, then add the three fields. Verify: the new assertions pass and no existing `core/kavita` test changes.
- [x] 1.4 Payloads captured from a live server and carried as inline JSON in both test files, with the server version in the header. **Placed differently from the plan:** `packages/test-fixtures` generates comic, ebook and audiobook *binaries* through `scripts/generate.py` and holds no API payloads, and every Kavita test in both trees already inlines its JSON beside the stub. The repository is public, so the names and ids are invented while every field name, type and null is the shape Kavita 0.9.1.4 returned.

## 2. An entry states its read state

- [x] 2.1 `ServerListProgressTest` (9 cases) and `ServerListProgressTests` (9 cases) hold the rule; `ServerListRowTest` (6 Robolectric cases) holds what is drawn. **Unread draws no badge** — the library draws none for an unread publication either — so it is asserted on the accessibility label rather than on a drawn string, which is what "in the same terms the library uses" means here. The rule and its test landed together rather than red-first; a mutation of the `pagesTotal <= 0` branch fails 5 assertions, which is the proof the ordering was meant to give.
- [x] 2.2 Draw the three states in `EntryRow` (`apps/android/feature/library/.../KavitaShelfScreens.kt:243`) and in the row of `KavitaShelfViews.swift:257`, reusing `KavitaChapter.isFinished`'s rule and `KavitaExchange.position`. Verify 2.1 passes on both.
- [x] 2.3 Write the assertion for the list's own summary — "14 of 18 finished", excluding entries with no read state from both numbers — then draw it above the rows. Verify: the new test passes and states the excluded case.
- [x] 2.4 Android: `ServerListRowTest` asserts the merged node reads "1. Issue #43 Lantern Green Finished", and that an unread row says *Unread* where it draws nothing. iOS: the same label is built by `said(index:row:)` and the row is `.accessibilityElement(children: .ignore)`, but **no iOS test asserts the label** — this half is code without an assertion, and the tick covers Android only. No progress is conveyed by colour alone on either platform: every state is a word.

## 3. An entry carries its cover

- [x] 3.1 Write the test for a row whose cover has not arrived and one whose fetch failed: both keep number, title and series, and the frame keeps the library's 2:3 aspect. Red before 3.2.
- [x] 3.2 Draw the chapter cover at the row's leading edge through `KavitaClient`'s existing `Image/chapter-cover` route, keyed by `chapterId`, decoded at the displayed size. Verify 3.1 passes, and that no image-loading dependency was added — `git diff gradle/libs.versions.toml Package.swift` is empty.
- [x] 3.3 `ServerListCoverFetchTest`: 77 rows of 56 dp in a 200 dp window, and the loader is asked for fewer than 20 of them — row 1 yes, row 77 never — plus one chapter asked for exactly once however often its row recomposes. Android only; iOS relies on SwiftUI's own lazy `List`, which no test here asserts.

## 4. A server shelf is drawn from what it holds

- [x] 4.1 Assert the local shelves are unchanged first: run `ShelfCoverTest` and `ShelfCoverChoiceTest` (and iOS's counterparts) and record that they pass before anything moves. They are the control for the extraction.
- [x] 4.2 Extract the quadrant layout out of `ShelfCover` (`feature/library/ShelfCover.kt:66`) into a private composable that takes the resolved artwork, leaving `ShelfCover(tiles:viewModel:)`'s signature and every local call site untouched. Mirror in `ShelfCover.swift:19`. Verify: 4.1's tests still pass, and `git diff` touches no file that calls `ShelfCover`.
- [x] 4.3 `ServerShelfCoverTest` (4 Robolectric cases) asserts which artwork the composite asks for, in what order, and that a failed fetch leaves the frame rather than the app. `ServerShelfCoverTests` (3 cases) asserts the tile-selection rule only: **iOS has no drawing assertion here** — building a `KavitaPage` needs a `Source` and a `CredentialStore`, and the composite itself is `ShelfComposite`'s, which the local shelf tests already cover. The `coverImageLocked` branch is code on both platforms and is asserted by neither; it is one `if` over a field the decoding tests do prove arrives.
- [x] 4.4 Add `ServerShelfCover(tiles:load:)` over the extracted layout, fetching through `Image/chapter-cover` as the entry poster does, and call it from `ServerShelfCard` (`ShelvesScreen.kt:473`) and `ShelvesView.swift:328` in place of `tiles = emptyList()`. Verify 4.3 passes on both platforms.
- [x] 4.5 Verify `CompositeCover` itself is unchanged — `git diff core/model/CompositeCover.kt` is empty — and that a server collection composites from its series covers as a reading list does from its chapters'.

## 5. Seen on a device

- [x] 5.1 Six frames at `docs/designs/screenshots/server-shelves-2026-09-10/`: the list in dark and light, before and after, plus the 77-entry list at `font_scale 2.0` in both appearances. **The two largest-text frames have no control** — changing the scale recreates the activity and pops back to Library, so the two captures taken that way showed the wrong screen and were discarded rather than presented as controls. The README says so.
- [ ] 5.2 Screenshot the same list in the iOS Simulator, same four frames, same control.
- [x] 5.3 Android only, and **without a locked-cover tile**: every shelf on this server is unlocked, so `android-collections-dark-*` and `android-lists-dark-*` prove the composite (four quadrants, and one cover where there are fewer than four members) against the blank frames that preceded them. The `coverImageLocked` branch is drawn by no frame here.
- [x] 5.4 `README.md` beside them: device, API level, server version, which build each frame came from, what each pair proves, the two gaps above, and the `adb` recipe that repeats it.

## 6. The gates

- [x] 6.1 `pnpm test:android` and `pnpm test:ios` green, and `./gradlew lint` clean for `:feature:library` — `warningsAsErrors` is on for `:app` and the module inherits the config.
- [x] 6.2 `pnpm lint` green, including `strings:drawn` and `strings:ios` for any new string, in all four languages.
- [x] 6.3 `pnpm spec:validate && pnpm spec:guard` green for this change.
