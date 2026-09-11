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

- [ ] 7.1 Screenshot the refreshing line and the checked line on a booted iOS Simulator, light and dark, with the library beside them as the control. **Not done.**
- [ ] 7.2 The same two lines on an Android emulator, light and dark, at `font_scale 2.0`. **Not done.**
- [ ] 7.3 A `README.md` beside the frames naming the device, the appearance and what each pair proves. **Not done.**

## 8. What is not asserted, and is code either way

- [~] 8.1 **The source detail screen's own refresh is asserted by nothing, on either platform, and was not before this change either.** Both `LibraryModel.test(_:)` (`LibrarySourceHealth.swift:203`) and `LibraryViewModel.testSource` (`LibraryViewModel.kt:593`) mark the source `Connecting` before they ask, and the screen's *Status* row reads it — which is what satisfies *A refresh of one source from its own screen*. No test on either platform calls either function: both need a network. The stamp that makes the *Last sync* row live **is** asserted, in task 1.
- [~] 8.2 **Two overlapping probes clear the flag once.** `probe(on:)` launches beside `retryUnreachableSources` rather than inside it, so whichever finishes first clears `refreshing`. The worst case is the line leaving a second early. Recorded rather than fixed: serialising the two is a change to the retry loop, not to this indicator.
