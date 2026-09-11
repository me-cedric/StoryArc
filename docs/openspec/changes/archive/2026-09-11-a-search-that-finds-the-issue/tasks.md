# Tasks

A tick means the file the task names holds what the task describes, and that a
test asserts it. A tick does not mean anybody watched it work on a device.

## 1. The join, tested first

- [x] 1.1 Write `KavitaIssuesTests.swift` in
  `apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/`. Assert the issues of
  a matched series, the dedupe against the server's own chapter hit, a
  publication of another series, and a publication with no chapter id.
- [x] 1.2 Write the twin `KavitaIssuesTest.kt` in
  `apps/android/core/model/src/test/kotlin/app/storyarc/core/model/`, with the
  same cases in the same order.
- [x] 1.3 Write `KavitaIssues.swift` in
  `apps/ios/Packages/StoryArcKit/Sources/StoryArcCore/`.
- [x] 1.4 Write `KavitaIssues.kt` in
  `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/`.
- [x] 1.5 Run `cd apps/ios/Packages/StoryArcKit && swift test` and
  `pnpm gradle :core:model:testDebugUnitTest`.

## 2. The finders use it

- [x] 2.1 Add `publications` to `KavitaFinder` in
  `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/KavitaSearch.swift`, and
  pass the server's hits through `KavitaIssues.joined`.
- [x] 2.2 Do the same in
  `apps/android/feature/library/src/main/kotlin/app/storyarc/feature/library/KavitaSearch.kt`.

## 3. The library supplies the publications

- [x] 3.1 `KavitaBrowserView` takes the source's publications and sets them on
  the finder it owns, in
  `apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/KavitaBrowser.swift`.
- [x] 3.2 `SourceBrowser` and `LibraryPanes` carry them down, filtered on
  `sourceID`.
- [x] 3.3 `KavitaBrowserScreen` takes the same list and sets it on its finder, in
  `apps/android/feature/library/src/main/kotlin/app/storyarc/feature/library/KavitaBrowserScreen.kt`.
- [x] 3.4 `AppScreens` fills it from the library's publications, filtered on the
  source id.

## 4. Gates

- [x] 4.1 `pnpm lint`.
- [x] 4.2 `pnpm spec:guard`.
- [x] 4.3 `pnpm gradle :core:model:testDebugUnitTest :feature:library:testDebugUnitTest`.
- [x] 4.4 `cd apps/ios/Packages/StoryArcKit && swift test`.

## The frame this change cannot take

- [x] **No frame proves this on a device, and the reason is the device rather than
  the change.** `AGENTS.md` section 6 owes a picture of every behaviour a reader can
  see. This one needs a Kavita source with an API key, and then a library walk so the
  contributor fills the index the join reads. The emulator has no server and the
  owner's key is not on it; their own phone, which has both, was handed to another
  session. The absence is recorded in
  `docs/designs/screenshots/four-features-2026-09-11/README.md` under *Not shown*,
  beside the frames the same day did take. `KavitaIssuesTest` and `KavitaIssuesTests`
  assert the join on both platforms, eight cases each, and they are what stands in
  for the picture.
