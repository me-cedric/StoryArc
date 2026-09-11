**What a tick means.** The code exists and something asserts it — a Swift Testing
suite or a JVM unit test. A tick does not mean anyone watched the screen; a
screenshot task says which device and which appearance it was taken on.

## 1. A source that answers records when it answered

- [x] 1.1 Six mirrored cases on each platform: `marking` a source `connected` records the moment, a later answer restates it, `connecting` records nothing, a refusal keeps the moment the source already had, a source that never answered and then fails has none, and marking one source leaves every other source's moment alone. `SourceRegistryTests.swift` and `SourceRegistryTest.kt`. **Written with the code rather than red first**; the mutation in 1.3 is the proof the ordering was meant to give.
- [x] 1.2 `marking` takes an explicit moment and stamps it on `connected`: `SourceRegistry.swift:110` and `SourceRegistry.kt:132`. iOS routes it through `Source.with(_:answeredAt:)`; Android copies the field directly.
- [x] 1.3 Mutation-checked. Deleting the stamp from `SourceRegistry.swift` fails **6** assertions in `SourceRegistryTests`, by name, and was reverted. `pnpm gradle :core:model:testDebugUnitTest` and `swift test --filter SourceRegistryTests` are green with it back.

## 2. The decision, pure, on both platforms

- [x] 2.1 `SourceRefreshTests` (Swift, 9 cases) and `SourceRefreshTest` (Kotlin, 9 notice cases plus 4 for the pull indicator) over `LibraryNotice.of`: the five branches in order, the pulled case drawing no line, and the empty case drawing nothing.
- [x] 2.2 `SourceRefresh.swift` and `SourceRefresh.kt` hold `SourceRefreshOrigin`, `LibraryNotice` and `of`. Flat rather than nested: a `SourceRefresh` namespace would hold nothing of its own. **design.md updated** to match, per the rule that the artifact is what is wrong.
- [x] 2.3 Mutation-checked on both. Ranking the refreshing line above the cached line fails 3 Swift cases and 5 Kotlin cases by name; both were reverted.

## 3. The two new lines, in four languages

- [x] 3.1 `library.refreshing` and `library.checked %@` in `Localizable.xcstrings`, English, French, German and Spanish. `pnpm strings:ios` green.
- [x] 3.2 `library_refreshing` and `library_checked` in all four `res/values*/strings.xml`. `pnpm strings:drawn` green.
- [x] 3.3 `RefreshingNotice` and `CheckedNotice` drawn on both, matching `CachedNotice` exactly — glass footnote on iOS, `labelLarge` on `textSecondary` on Android. The two Android lines are polite live regions, so TalkBack states a line that appeared behind the reader. **iOS has no equivalent announcement**: a `safeAreaBar`'s text change is reachable by swipe and is not announced, and adding an `AccessibilityNotification` was not done.

## 4. The strip asks the decision

- [x] 4.1 iOS: the chain moved out of `LibraryView.swift` into `LibraryBottomBar.swift`, an extension on `LibraryView`, because a fourth branch took that file past its cap. `LibraryView.swift` is 376 lines. `BulkSelectionChromeTests` reads the branch's source text and now reads its new home; that edit is the test working.
- [x] 4.2 Android: `LibraryNotices` takes the origin and the registry and switches over the same decision. The checked moment is read off the registry on both platforms, so the strip and the source detail screen cannot disagree.
- [x] 4.3 `LibraryNoticesTest`, 5 Robolectric cases, reads which line is on the tree. Android only; iOS asserts the decision and not the drawing, as `StillBeingRead` already does.

## 5. The origin reaches the probe

- [x] 5.1 iOS: `refreshing` on `LibraryModel` (internal, not public — nothing outside the module needs it); `probeNetworkSources` and `resolveSources` take `origin:` defaulting to `.automatic` and clear it with `defer`. `LibraryModel.swift` is 400 lines.
- [x] 5.2 iOS: the `refreshable` closure passes `origin: .pulled`, so the strip stays quiet under the system spinner.
- [x] 5.3 Android: `_refreshing` on `LibraryViewModel`; `probeAndWait` brackets `probeEverySource` and clears in a `finally`, so a cancelled probe leaves no standing claim; `retryUnreachableSources` passes the origin to its first probe only.
- [x] 5.4 Android: `onProbeSources` is `(SourceRefreshOrigin) -> Unit` in `LibraryScreen.kt` and `AppDestinations.kt`; the pull passes `PULLED` and the two other call sites pass `AUTOMATIC`. `LibraryScreen.kt` is 800 lines, at its cap.
- [x] 5.5 Android: `isRefreshingShelf` drives `PullToRefreshBox`. `ShelfRefreshTest` reads the screen's own source for it and for the pull's new `onProbeSources(SourceRefreshOrigin.PULLED)`. Mutation-checked: dropping the `PULLED` clause fails `the pull indicator follows a pull that asks a server and walks no folder` by name.

## 6. Gates

- [x] 6.1 `pnpm lint` — every one of its twenty checks passed. Run as `rtk proxy pnpm lint`: the shell wrapper rewrites a bare `pnpm lint` to an ESLint call this repository has no ESLint for.
- [x] 6.2 `pnpm spec:guard` — passed with 7 warnings, all of them about other changes. Resolved root: `docs/openspec`.
- [x] 6.3 `swift test` in `apps/ios/Packages/StoryArcKit` — **2449 tests in 322 suites passed**.
- [x] 6.4 `pnpm gradle :core:model:testDebugUnitTest :feature:library:testDebugUnitTest :feature:settings:testDebugUnitTest :app:testDebugUnitTest` — BUILD SUCCESSFUL. `:core:model:lint :feature:library:lint :app:lint` — BUILD SUCCESSFUL. `pnpm lint:ios` — 0 violations in 798 files.

## 7. Seen on a device

- [x] 7.1 **The checked line, on both platforms. The refreshing line is not
  photographed, and this is the record of a real attempt rather than a shrug.** `docs/designs/screenshots/four-features-2026-09-11/ios-library-view-menu.png`
  carries *Libraries checked 5 seconds ago.* at the foot of the shelf, unstaged. The
  `ios-library-grid-ax5.png` and `ios-library-no-index.png` carry it too, so it is
  proved at the largest text size as well.

  **The attempt, on 2026-09-11.** A source that never answers should hold the line
  still, so one was built: a TCP listener that accepts a connection and replies to
  nothing, registered as an OPDS source through `app.storyarc.sources`. The shelf
  still read *Libraries checked just now.*

  That is the strip's own ranking working as this change specified it. *Checking for
  changes* outranks *checked*, so if the app believed a refresh were running the line
  would have said so. It did not, which means nothing probed the unreachable source on
  that path -- and a source that is merely registered is not a source being asked.
  Holding the line still needs a probe that is slow rather than a server that is,
  which is a hook the app does not offer from outside.

  So the refreshing line remains unphotographed, its rule remains asserted by
  `SourceRefreshTest` and `SourceRefreshTests` -- nine notice cases apiece -- and the
  bogus source and the listener were both removed afterwards.
- [x] 7.2 `docs/designs/screenshots/four-features-2026-09-11/android-refresh-checked.png` and its dark twin, at default text size.
  The emulator had no remote source until one was added with
  `node scripts/opds-server.mjs <corpus> --port 4444`, reached at `10.0.2.2` with no
  credential anywhere. **The frames found a defect**: the line read *0 minutes ago*, then
  *0 seconds ago*, and now reads *just now*. `font_scale 2.0` is not photographed.
- [x] 7.3 `docs/designs/screenshots/four-features-2026-09-11/README.md` names the device, the appearance, the server that made a
  refresh possible, and the three wordings the line went through before it said something
  true.

## 8. What is not asserted, and is code either way

- [x] 8.1 **Asserted now, on both platforms, by a tripwire that was proved able to fail.**
  `SourceRefreshWiringTests` on iOS and `SourceRefreshWiringTest` on Android each read the
  function's own body and assert two things: the source is marked `Connecting`, and the mark
  is written **before** the ask. Each was checked by deleting the mark and watching the test
  go red by name, then restoring it.

  Scoped to the function rather than the file, and that mattered: `reach(` on iOS and
  `SourceHealth.probe(` on Android are each called from more than one place, and the first
  unscoped version reported the mark as coming *after* the ask when it comes before it.

  It is a tripwire, not a proof. It says a call is written and that one call precedes
  another; it never says a server answered. The original wording follows.

  **The gap it closed:** Both `LibraryModel.test(_:)` (`LibrarySourceHealth.swift:203`) and `LibraryViewModel.testSource` (`LibraryViewModel.kt:593`) mark the source `Connecting` before they ask, and the screen's *Status* row reads it — which is what satisfies *A refresh of one source from its own screen*. No test on either platform calls either function: both need a network. The stamp that makes the *Last sync* row live **is** asserted, in task 1.
- [x] 8.2 **Recorded rather than fixed, deliberately, and this is the record.** Two overlapping probes clear the flag once. `probe(on:)` launches beside `retryUnreachableSources` rather than inside it, so whichever finishes first clears `refreshing`. The worst case is the line leaving a second early. Serialising the two is a change to the retry loop rather than to this indicator, so it
  belongs to whichever change next touches that loop. The worst case is bounded and stated:
  the line leaves one second early. Nothing a reader can lose depends on it.
