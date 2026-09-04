# Tasks

Most of this change is already built — see [`design.md`](design.md) *Context*.
Groups 1 and 2 are ticked against code that exists, with the file that proves each
one, so this list records the position honestly instead of restating the capability
as though none of it had happened. Groups 3 to 6 are the remainder.

A ticked box here means **the code exists and a unit test asserts it**. It does not
mean anyone has watched it work; that is group 4, and it is the reason this change
is not archivable yet.

## 1. Registry, credentials and removal — built

- [x] 1.1 `SourceRegistry` as an immutable value with `adding`, `renaming`, `moving`, `replacing`, `removing`, `dropping`, mirrored on both platforms — verified by `SourceRegistryTest.kt` and `IdentityAndSourceTests.swift`
- [x] 1.2 The registry persisted as one JSON document, order surviving a launch — verified by the iOS source-store round-trip test (**Android has none; task 6.1**)
- [x] 1.3 Secrets in the platform secure store: `SecItem` on iOS, an Android Keystore AES-256-GCM key on Android, one entry per source, the registry holding only an opaque reference — verified by the credential-store tests on each platform
- [x] 1.4 Removal deletes the stored secret first and unconditionally, by the reference the registry holds, then the downloads — verified by `SourceRemoval` tests on both platforms
- [x] 1.5 Removal states how many titles it removes and that reading positions are kept for 30 days, before asking — verified by the confirmation strings in both `Localizable.xcstrings` and the Android string resources
- [x] 1.6 30-day retention as a tombstone plus `collectingExpiredTombstones(as:retention:)`, the moment passed in so a test advances a clock rather than waiting — verified by the clock-advancing cases in `SourceRegistryTest.kt` and its iOS mirror

## 2. Connection state, diagnosis and cache — built

- [x] 2.1 `SourceProbe.delay(afterFailures:)` doubling from 5s and capping at 300s, and the HTTP-response-to-state mapping, asserted against the same table on both platforms — verified by `SourceProbeTest.kt` and `SourceDiagnosisTests.swift`
- [x] 2.2 Connection state never persisted; every source loads as *connecting* — verified by the `SourceStore` round-trip test asserting the state is not read back
- [x] 2.3 `SourceDiagnosis` producing the five fields and deciding which of the five actions a given source is offered, with no pixels in it — verified by eleven mirrored cases per platform
- [x] 2.4 The per-source health screen reached by tapping a source in Settings — `SourceDetail.swift` / its Android mirror (**not driven; task 4.1**)
- [x] 2.5 `Credentials rejected` re-opens the add sheet with the address filled and the secret blank, and what comes back keeps the same identifier so `SourceRegistry.replacing` preserves position, downloads and the reader's name — verified by the `replacing` tests
- [x] 2.6 `SourcePrecedence` ranking by registry position, an unattributed find and a removed source tying for last, and the row opening the copy it names — verified by the precedence tests on both platforms
- [x] 2.7 The folder walk cached: catalogue written on completion and restored before the next walk, covers keyed by publication and pixel size, both in the caches directory; incremental refresh; a publication a walk no longer finds removed while its progress stays; neither write nor removal firing on a walk that saw nothing — verified by the library-cache tests
- [x] 2.8 The dead iOS reconnect loop wired, running from the same `task` as the first probe and *after* it, and Android asking once before it starts scheduling — `LibraryView.swift:286`

## 3. Reachability — the one behaviour still missing

- [x] 3.1 Wire a reachability observer to the probe on iOS so an unreachable source is retried when connectivity returns and when the app returns to the foreground, and verify with a unit test that drives the observer's callback rather than a real network. Decide the observer's placement — library model or beside the probe — in this task's review; `NWPathMonitor` is `Assumed` and unused in this repository so far
      **Placement decided: beside the probe.** `StoryArcCore/SourceReachability.swift` holds
      `RetryTrigger` (the two occasions `sources` names) and the three functions that decide
      what to do with one — `shouldProbe(on:sources:isReading:)`, the edge detector
      `trigger(hasNetwork:previously:)`, and `triggers(from:)` over an injected
      `AsyncStream<Bool>`. The same reason `SourceProbe` is there: a decision a test can
      reach without a network. Sixteen cases in `SourceReachabilityTests`, none of which
      touches a monitor.
      **What is not done is the wiring, and it is in `LibraryFeature`.** Two edits, named in
      full in the handoff: an `NWPathMonitor` → `AsyncStream<Bool>` adapter beside
      `NetworkCost.swift`, which already holds one monitor for the same framework, and a
      `.task` in `LibraryView` that consumes the triggers and calls
      `probeNetworkSources(credentials:pins:)`. The foreground half needs the same loop and a
      `scenePhase` observation: `.task` is **not** re-run when the app returns to the
      foreground — it fires on appear, and backgrounding does not disappear the view — so the
      claim in `retryUnreachableSources`' own doc comment that "returning is what starts it
      again" holds only when the library actually went away.
      **Wired on 2026-09-03, and the wiring found the requirement's other half was never met.**
      `NetworkPaths.satisfied()` is the adapter, beside `NetworkCost.swift` for the reason given
      — and deliberately a *second* monitor rather than a shared one, because the two questions
      have different lifetimes: the cost is asked synchronously whenever a download is weighed,
      this is consumed by a `.task` that ends with the view, and one object answering both is how
      one of them reads a stale path.
      **The foreground occasion is `scenePhase`, not the `.task` restarting.** Both this task's
      own note and `retryUnreachableSources`' doc comment said returning to the foreground was
      free because "returning is what starts it again". It is not: a `.task` fires on *appear*,
      and backgrounding does not disappear a view — `LibraryView`'s own header says so a hundred
      lines above where it started the loop. So **neither platform retried on returning to the
      foreground**, for as long as both comments claimed it did. `.onChange(of: scenePhase)` is
      the trigger now.
      **And the backoff loop ran straight through a chapter.** §3.3 asked me to *confirm* nothing
      reconnects mid-read; the answer was that iOS's loop is never cancelled when a reader opens,
      so it probed every configured server every 5 s, then 10, up to every 5 minutes, for as long
      as anything was away. `isReading` now travels from `StoryArcApp.reading` through the shell
      to the view — a closure, not a value, because a reader opens a publication *while* the loop
      is waiting — and it is checked **after** each wait rather than once at the top.
      `LibraryView.swift` crossed SwiftLint's 400-line cap, so the two triggers are a
      `SourceRetryTriggers` modifier in its own file. **Its first version built its own
      `CertificatePins` and that was a defect**: the view loads the reader's pinned certificates
      into `@State`, so a fresh pair would have trusted nothing they pinned and failed against
      exactly the servers pinning exists for. It takes the view's own now.
- [x] 3.2 The same on Android with `ConnectivityManager.NetworkCallback`, asserted by the same mirrored test cases, and verify `pnpm gradle :core:model:testDebugUnitTest` passes
      `core/model/SourceReachability.kt` mirrors the iOS file function for function, and
      `SourceReachabilityTest` mirrors its sixteen cases name for name — including the
      eight-report flapping signal, which is the same list of booleans on both platforms.
      `:core:model:testDebugUnitTest` passes: 16 tests, 0 failures.
      **Wired on 2026-09-05.** `NetworkPaths.satisfied(context)` is the observing half, a
      `callbackFlow` around `ConnectivityManager.NetworkCallback`, beside `NetworkCost.kt` for
      the reason iOS puts its own beside `NetworkCost.swift` — and deliberately a second
      observer rather than a shared one, because the two questions have different lifetimes.
      **It sends the current state before registering, and that is not tidiness.**
      `registerDefaultNetworkCallback` is silent when there is *no* default network: it only
      ever calls `onAvailable`. A collector that started offline would therefore keep
      `triggers`' assumed `true`, read the regain as no change, and never fire the one trigger
      the requirement is about. iOS gets that opening report free — `NWPathMonitor` reports an
      unsatisfied path as readily as a satisfied one — so the divergence is in the platform,
      not in the mirror.
      **The foreground half is not the one-line addition this task expected.** It sits with
      the connectivity half in `SourceRetryTriggers.kt`, one composable holding both, because
      `SourceReachability`'s own note gives the reason: two call sites is how one of them ends
      up without the reading guard. Both report to `LibraryViewModel.probe`, which is the only
      caller of `shouldProbe`.
      **And the collection is scoped to `repeatOnLifecycle(STARTED)`, which is the reading
      guard's other half.** The EPUB reader is an activity of its own, so while a reader is in
      a chapter of one the navigation state `isReading` asks holds a library, not a book — it
      answers false and cannot answer otherwise. Suspending the collection is what stops a
      dropped Wi-Fi mid-chapter probing every server behind the page. The backoff loop is
      *not* covered by that and still runs through an EPUB chapter; 3.3 already records it,
      and it now takes `isReading` and is correct for the comic reader.
      **The loop's guard was the other half of 3.3 and is done here.** `retryUnreachableSources`
      takes `isReading` and asks it after each wait rather than once at the top, because a
      reader opens a publication *while* the loop is waiting. `AppHost.isReading` is the one
      value that can see both a reader and a library.
      **Six mutation-checked wiring cases** in `SourceRetryWiringTest`, which reads the two
      source files for `SmbTransferWiringTest`'s reason: a `NetworkCallback` needs a device,
      and `SourceReachabilityTest`'s sixteen cases all passed for as long as nothing called
      any of them. Deleting the loop's guard fails exactly *the backoff loop asks whether a
      reader is reading*; unwrapping `repeatOnLifecycle` fails exactly *the connectivity
      signal is collected only while the activity is started*. Both restored byte for byte.
      **`LibraryViewModel.kt` was at the length `scripts/line-cap.mjs` records for it**, so the
      source-health block moved to `SourceRetry.kt` — the same split iOS made into
      `LibrarySourceHealth.swift`, for the same reason and with the same consequence: three
      backing flows are `internal` rather than `private`, because `private` is file-scoped in
      Kotlin as in Swift.
- [x] 3.3 Confirm neither platform reconnects while the reader is reading — the scenario's "does not interrupt reading" clause — and verify by a test that asserts no probe is scheduled while a reader session is open
      **The guard exists and is asserted; it is not yet consulted, and today both platforms
      do reconnect mid-read.** `shouldProbe` refuses on `isReading` before it looks at
      anything else, and three cases assert the absence — *no probe is scheduled while a
      reader is open*, *the reader outranks every other reason to probe*, and the both-occasions
      case, on each platform. Mutation-checked in both directions: deleting the one guard line
      fails exactly those three tests on iOS (6 issues) and exactly those three on Android,
      each failure naming `isReading = true` against a scheduled probe. Both files were
      restored byte for byte.
      **What is left is that nothing calls it yet, and the existing backoff loop needs it
      too.** iOS's loop runs from `LibraryView`'s `.task`, which is not cancelled when the
      reader opens — the file says so itself at `LibraryView.swift:94` — so it probes every
      5 s to 300 s through a chapter. Android's is stopped by `onDispose`, which the comic
      reader triggers and the EPUB reader, being an activity of its own, does not. Both fixes
      are one condition in a file this task could not edit.

## 4. Visual proof — what blocks archiving

Every item here owes a screenshot from a booted simulator or emulator, light and
dark, at default and largest text size. A `#Preview` and a `@Preview` do not count.
`pnpm capture:android --list` names the routes; `pnpm capture:ios` is the iOS side.

- [ ] 4.1 The source detail screen, both platforms, showing all five fields and the five actions — verify by attaching the screenshots to the change
- [ ] 4.2 The reconnect sheet reached from a rejected credential, address filled and secret blank
- [ ] 4.3 The "cannot be reached" notice for an unreachable server, with the "downloads stay readable" line and the try-again action. **Capture a control beside it** — a reachable source at the same moment — so the picture proves the state and not merely that the screen exists
- [ ] 4.4 Pull-to-refresh on iOS, mid-gesture and after completion
- [ ] 4.5 The precedence rule with two sources holding one title: the row, and the copy it opens
- [ ] 4.6 The removal confirmation showing the title count and the 30-day sentence

## 5. The honest limit in the cached indicator

- [x] 5.1 Make the scanner report whether it could read the folder, so the cached notice stays when a walk saw nothing because the folder was unreadable and leaves only when a walk genuinely found an empty folder. Write the failing test first — a walk over an unreadable folder keeps the notice — then change the scanner on both platforms
      **The scanner now reports it, on both platforms.** `scan` takes an
      `onUnreadableFolder` reporter, called with the path of every directory the walk could
      not list. A lambda rather than a fourth `ScanEvent`: the terminal event is matched
      exhaustively in `LibraryFeature` and `feature/library`, which this change does not own,
      and the answer has to outlive the stream because the decision is made at `finished`.
      Reported per directory, because a subdirectory that cannot be listed makes the walk
      partial in the same way — what it did not see is unaccounted for rather than gone.
      **Android needed it in two places, and the second is the one that matters.** A picked
      folder arrives as a tree `Uri`, and `SafTree.children` turned a refused query into an
      empty folder — its own doc comment said so: "a folder whose permission was revoked reads
      as empty rather than throwing". `SafTree.childrenOrNull` keeps the distinction and
      `children` delegates to it, so the callers that only want rows are unchanged.
      **Six mirrored cases per platform**, including the defect stated as an assertion — *the
      finished event alone cannot tell the two apart* — and a genuinely mode-0 directory, which
      both suites make and both actually ran (0 skipped). Mutation-checked on Android:
      restoring the swallowed listing failure fails four of the six; restored byte for byte.
      **The consumers are changed now, on 2026-09-05, and the notice stays.** `LibraryScanning`
      and `LibraryViewModel` pass a reporter per walked scope; `cacheLibrary` takes the answer
      and neither clears the indicator nor stamps `now` into the snapshot, and
      `ScanReconciliation.vanished` takes the partial scopes and removes nothing from one.
      **The reconcile's half is the one the emptiness rule could never have covered.** "A walk
      that found nothing removes nothing" was an inference, and it only ever caught the folder
      that became unreadable *whole*. A folder that loses one subdirectory still returns rows,
      so the walk looked complete and every book under the branch it could not list was
      removed as though the reader had deleted it. That is the case both new suites drive.
      **And on iOS nothing had ever called `cacheLibrary` after a walk at all.** Its only
      caller was the per-source *clear cache* action, so no snapshot was ever written, none was
      restored, `cachedAt` was never set — and `CachedNotice`, a drawn view with its own
      string, could not appear. The honest limit 5.1 set out to close was therefore not the
      only thing wrong with the notice on that platform; the scan writes a snapshot now, at the
      end of every place it walked, where Android has always written one. `LibraryModel.swift`
      was one line under SwiftLint's file length, so the pair moved to `LibraryCaching.swift`.
      **Asserted by the four readability cases in 6.2's suites**, mutation-checked on both
      platforms: dropping the reconcile's guard fails exactly *a walk that lost one subfolder
      still holds the books that were under it*; dropping the snapshot's fails exactly *a walk
      that could not read the folder keeps the cached notice*; removing the snapshot write
      fails four iOS cases. Every file restored byte for byte.
      `entries(in:)` still swallows the same failure, deliberately and with a note: nothing
      compares a snapshot without having just walked the same folder.

## 6. Test gaps the audit named

- [x] 6.1 Add `SourceStoreTest` on Android — the registry round trip is asserted on iOS and by nothing on Android — and verify `pnpm gradle :core:persistence:testDebugUnitTest` passes
      **Nine cases; `:core:persistence:testDebugUnitTest` passes.** The first seven mirror iOS's
      `SourceStoreTests` in its order, so the two platforms' stores are held to one written
      contract rather than to two lists that drift.
      **Two have no iOS counterpart, because the code they cover has none.** Android's
      `StoredRegistry.toDomain` drops a `SourceKind` this build cannot parse rather than guessing
      at it — its own comment says a source written by a newer version has a type this one cannot
      fetch from, and drawing it as a folder would be worse than not drawing it — and `registry()`
      wraps its decode in `runCatching`, so truncated preferences give a reader an empty library
      they can add to instead of an exception on the launch path. Neither was asserted anywhere.
      The unknown-kind case is written as raw JSON because **no enum case can produce it**: only a
      future build can, which is exactly why nothing had covered it.
      **Mutation-checked, both directions.** Defaulting an unparseable kind to `LOCAL_FOLDER`
      fails the drop case and nothing else; carrying `Connected` through `toDomain` fails the
      state case and nothing else. Each mutation was reverted and the store restored byte for
      byte.
- [x] 6.2 Assert the library-feature behaviours nothing currently covers on either platform: the empty state, the cached notice, the incremental refresh, and the disappearance removal. Four cases per platform, mirrored case for case
      **Eight per platform, not four**, in `LibraryShelfLifecycleTests.swift` and
      `ShelfLifecycleTest.kt`, mirrored name for name: the four this task names plus the four
      5.1 owes — the notice leaving on a good walk, the notice staying on an unreadable one,
      the wholly unreadable folder that removes nothing, and the partial walk that keeps what
      was under the branch it could not list.
      **Two of the four were broken, and neither broke a test.** The cached notice could not
      appear on iOS at all (5.1's note has the reason), and the reconcile removed books under
      an unlistable subdirectory on both.
      **Real folders and the real corpus**, driving the actual model rather than a fake walk.
      Android runs under Robolectric over the app's *managed* folder, which is what makes it
      possible at all: with no picked folder there is no document tree, so `rescan` takes the
      `File` overload a JVM can reach. `SkippedScanTest`'s note — that Android's view model
      cannot be driven from a unit test — held only for the tree overload.
      **The incremental refresh is asserted at the moment it could go wrong**: the instant the
      second walk is started, before anything has been found again. Asserting the end state
      would pass against a model that emptied the shelf and refilled it, which is the thing
      `sources` forbids.
      **The unreadable directories are genuinely mode 0**, and both suites report 0 skipped, so
      neither `assumeTrue` fired and neither process was running as root.
      **A consequence worth recording:** the iOS suites that scan now take their own
      `LibraryCache`. From this change on a walk writes a snapshot, the default location is the
      machine's caches directory, and `LibraryRestoreTests` was putting another test's shelf up
      before its own walk began — two of its cases failed on the first run after the write was
      wired, which is the shared-cache defect finding itself.
- [x] 6.3 Assert that the diagnostic export's source section is a count and never a list, on both platforms — the one regression that would leak a hostname or a token
      **Seven cases per platform, and the section is now a real count.** It was the literal
      `configured = 0` on both — a count in shape and a falsehood in fact, so a reader with
      four servers filed a report saying they had none. `Diagnostic.sourceLines` takes the
      registry, and `Diagnostic.text` takes it through from `PrivacySettings` and
      `PrivacyGroup`.
      **The registry rather than an `Int`, deliberately.** An `Int` makes a leak
      unexpressible, which sounds stronger and is worse to depend on: it moves the guarantee
      out of the export and into whichever caller counts, where nothing asserts it. Passing
      the registry keeps the boundary in the file, two lines wide, with a test pointed at it.
      **Three refusals, asserted on the section and again on the whole report:** no display
      name (a reader names a server after the machine, so it *is* the hostname), no locator
      (a URL is where an embedded credential survives — the fixture's carries `s3cr3t`), no
      credential reference (a handle into the secure store). Plus the two that stop the
      section satisfying them by disappearing: it still says `[Sources]` and still says how
      many.
      **Mutation-checked, exactly as asked.** Appending `name = <displayName>` to the section
      fails five of the seven on each platform, and *no source value reaches the report at
      all* names the hostname in its failure. Both files restored byte for byte.
      Android's suite is Robolectric, so it is still a host test —
      `:feature:settings:testDebugUnitTest`, 7 tests, 0 skipped, no device.

## 7. Close the change

- [ ] 7.1 Run `/opsx:verify source-lifecycle` and resolve or record every CRITICAL it reports
- [ ] 7.2 Update the `sources` row in [`STATUS.md`](../../STATUS.md) from the verify report — scenario counts, what was driven and on what, and what remains
- [ ] 7.3 Confirm `agent-compass openspec-guard . --strict` reports no error for this change, then archive it with `/opsx:archive`
