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

- [ ] 3.1 Wire a reachability observer to the probe on iOS so an unreachable source is retried when connectivity returns and when the app returns to the foreground, and verify with a unit test that drives the observer's callback rather than a real network. Decide the observer's placement — library model or beside the probe — in this task's review; `NWPathMonitor` is `Assumed` and unused in this repository so far
- [ ] 3.2 The same on Android with `ConnectivityManager.NetworkCallback`, asserted by the same mirrored test cases, and verify `pnpm gradle :core:model:testDebugUnitTest` passes
- [ ] 3.3 Confirm neither platform reconnects while the reader is reading — the scenario's "does not interrupt reading" clause — and verify by a test that asserts no probe is scheduled while a reader session is open

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

- [ ] 5.1 Make the scanner report whether it could read the folder, so the cached notice stays when a walk saw nothing because the folder was unreadable and leaves only when a walk genuinely found an empty folder. Write the failing test first — a walk over an unreadable folder keeps the notice — then change the scanner on both platforms

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
- [ ] 6.2 Assert the library-feature behaviours nothing currently covers on either platform: the empty state, the cached notice, the incremental refresh, and the disappearance removal. Four cases per platform, mirrored case for case
- [ ] 6.3 Assert that the diagnostic export's source section is a count and never a list, on both platforms — the one regression that would leak a hostname or a token

## 7. Close the change

- [ ] 7.1 Run `/opsx:verify source-lifecycle` and resolve or record every CRITICAL it reports
- [ ] 7.2 Update the `sources` row in [`STATUS.md`](../../STATUS.md) from the verify report — scenario counts, what was driven and on what, and what remains
- [ ] 7.3 Confirm `agent-compass openspec-guard . --strict` reports no error for this change, then archive it with `/opsx:archive`
