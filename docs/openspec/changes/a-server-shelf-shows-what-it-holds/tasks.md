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
- [x] 5.2 **Four frames, and the server they needed was built rather than borrowed.**
  `ios-shelves-light.png`, `ios-shelves-dark.png`, `ios-shelves-ax5-light.png` and
  `ios-shelves-ax5-dark.png`, in the same directory as the Android six.

  No simulator has a Kavita server and the owner's key is not on one, which is why this task
  sat open. `scripts/kavita-server.mjs` is the mock this repository already carries for
  exactly this -- "so the walkthrough, enter a key, list libraries, open a series, read a
  chapter, can be watched" -- and it prints its own test key. Run against the same
  140-publication corpus on port 5001, it serves 2 libraries and 49 series.

  The frames show a server's own shelves beside a local one: *Staff picks*, captioned
  `ada · 127.0.0.1`, and *Long reads* with the four-quadrant composite cover task 5.3
  describes, next to the local *Lantern Run*. So the composite is now proved on both
  platforms rather than on Android alone.

  The address and the key are typed through the real form by `AddMockKavitaTests`, because
  the key lives in the Keychain under `CredentialStore.reference(for:)` and nothing outside
  the app can put it there.

- [x] 5.5 **A finding from taking those frames: the Kavita sheet's two fields carried no
  accessibility label.** A dump on 2026-09-11 reported `textFields: [""]` and
  `secureTextFields: [""]`. The words *Address* and *API key* are adjacent `Text`, and
  `.labelsHidden()` took the label off the field itself, so a screen reader announced "text
  field" and no hint of what to type -- on the one form in the app where a reader must enter a
  secret correctly.

  **Fixed on 2026-09-12, and the sibling sheets with it.** Each field states its own name
  through `.accessibilityLabel`, from the same key its visible headline draws, so the spoken
  name and the drawn name cannot drift. Six fields: the Kavita address and key, the catalogue
  address, and the catalogue token, user and password. Where a field has a hint footnote under
  it, the hint is now the field's own `.accessibilityHint` and the footnote is hidden from the
  reader, because both would otherwise say the same sentence twice.

  `AddMockKavita.swift` addresses the two fields by name now rather than by index, so the
  capture test would fail if the labels went away again. `SpokenFieldLabelsTests` holds the
  rule: every field names a key, the key is the one the headline draws, and every key carries
  all four languages. Checked by removing one label and re-running -- two of its four tests
  fail.

  **One control the same sweep found and deliberately did not touch**: the segmented and
  inline `Picker`s -- the search scope, the PDF tab strip, the language list, the EPUB
  alignment axis. A segmented picker vends each segment as its own element, so a label on the
  container may do nothing or may rename the segments, and which of the two happens cannot be
  settled without listening to VoiceOver. `reader-theming-and-page-transitions` task 7.6 is
  where that listening is tracked. The EPUB text-size stepper *was* fixed, because it is one
  combined element and a combined element takes the name it is given.
- [x] 5.3 Android only, and **without a locked-cover tile**: every shelf on this server is unlocked, so `android-collections-dark-*` and `android-lists-dark-*` prove the composite (four quadrants, and one cover where there are fewer than four members) against the blank frames that preceded them. The `coverImageLocked` branch is drawn by no frame here.
- [x] 5.4 `README.md` beside them: device, API level, server version, which build each frame came from, what each pair proves, the two gaps above, and the `adb` recipe that repeats it.

## 5b. What the archive verification found, 2026-09-12

All 24 boxes above were ticked, so the guard called this change ready. Three agents then read
every scenario of the delta against the code on both platforms, and a fourth asked what they
had missed. **Five findings, and two of them are the change's own scenarios failing.** This
section is why the change is not archived yet.

- [x] 5b.1 **A shelf with no artwork was drawn as an empty frame, which its own delta
  forbids.** The scenario says a collection whose members' covers cannot be fetched "shows the
  same placeholder a publication with no cover shows", and that it is "never drawn as an empty
  frame". `ShelfComposite` drew a filled rectangle instead.

  Found twice the same day and by two routes: by an agent reading `ShelfCover.kt` against the
  delta, and by a device pass that photographed Home listing a collection of one coverless book
  as a white tile. Before and after are
  `docs/designs/screenshots/shelves-and-marks-2026-09-12/android-home-shelves-blank-before.png`
  and `-named-after.png`.

  **Android is fixed.** The composite draws `CoverlessWell` when none of its members' covers
  arrived, and every caller now passes the shelf's name for it to carry — `ShelfCover`,
  `ServerShelfCover`, the cover chooser and Home. 761 tests pass in the module.
- [ ] 5b.2 **The same fix on iOS, which needs an API decision first.**
  `CoverlessWell` there takes a `PublicationFormat` and draws a glyph for it
  (`DesignSystem/CoverlessWell.swift:66-70`); a shelf has no format to give it. Two ways out,
  and the choice belongs to whoever knows the design intent: a formatless initialiser that
  draws the generic glyph, or the first member's format, which reads well for a collection of
  comics and oddly for a mixed one. Android sidesteps it because its own well takes a nullable
  format. `ShelfCover.swift:88` is the site.
- [ ] 5b.3 **A server-defined collection cannot show the cover a reader locked on the
  server.** The delta extends "unless the user sets a specific one" to a collection a server
  defines, and the model drops the field for exactly that kind: `KavitaShelves.kt:13-17` has no
  `coverImageLocked`, and `KavitaShelves.swift:8-22` decodes only id, title and summary. Only
  the reading list sets `chosenCover` — `ShelvesScreen.kt:139` and `KavitaShelfViews.swift:69`.
  So the branch is not merely untested for collections, as task 4.3 says; it is unreachable.
- [x] 5b.4 **Two tests could not fail, and both assert now.**
  - `ServerShelfCoverTests.swift` built a local tuple array and re-implemented `sorted`,
    `prefix` and `map` inside the test body, so the only production symbol it touched was
    `CompositeCover.tileCount`. The rule moved out of the view into `ServerShelfTiles`, where
    a test can reach it, and the five cases call it. Checked by deleting the sort from the
    production rule: two of the five fail. A fifth case was added for the half nothing
    covered — a collection keeps the server's own order, where a reading list keeps the
    reader's.
  - `ServerShelfCoverTest.kt`'s "artwork that never arrives leaves the frame rather than the
    app" held one `compose.waitForIdle()` and no expectation. It now asserts what it is for:
    a shelf whose every fetch threw is still drawn, and drawn as the placeholder rather than
    as an empty frame.
- [ ] 5b.5 **Nothing exercises the server shelf card on either platform.** Neither test tree
  mentions `ServerShelfCard` or `ServerShelfCardView`, so the collection branch is unasserted:
  which members are read (`ShelvesScreen.kt:506` against `:502`), and which artwork route is
  taken (`:529` against `:527`), with the same pair at `ServerShelfCardView.swift:61` and `:49`.

## 6. The gates

- [x] 6.1 `pnpm test:android` and `pnpm test:ios` green, and `./gradlew lint` clean for `:feature:library` — `warningsAsErrors` is on for `:app` and the module inherits the config.
- [x] 6.2 `pnpm lint` green, including `strings:drawn` and `strings:ios` for any new string, in all four languages.
- [x] 6.3 `pnpm spec:validate && pnpm spec:guard` green for this change.
