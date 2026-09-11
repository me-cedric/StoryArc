## Context

See proposal.md — Why. The UI decision comes before the code here, because the
owner asked for that in as many words: a spinner on every surface is worse than
a spinner in the one place a reader is looking.

Read against the source on 2026-09-11:

- **iOS `probeNetworkSources`** (`LibrarySourceHealth.swift:27`) walks the
  registry, asks each remote source, and marks the answer. It is reached from
  `resolveSources` (`:310`), from `retryUnreachableSources` (`:76`) and from
  `probe(on:)` (`:101`). It draws nothing and reports nothing.
- **Android `probeAndWait`** (`SourceRetry.kt:115`) is the same function, reached
  from `retryUnreachableSources` (`:53`) and `probe` (`:96`). Same silence.
- **The strip already exists on both.** iOS draws it in `LibraryView.swift`'s
  `safeAreaBar(edge: .bottom)`, ranked: bulk selection, missing folder,
  still-being-read, cached. Android draws `LibraryNotices`
  (`StillBeingRead.kt:84`), ranked: still-being-read, cached.
- **`library.cached %@` already says half of it** — *"Showing what was here %@.
  Checking for changes."* — in four languages on both platforms.
- **`marking(_:as:)` is pure and has no clock.** iOS `SourceRegistry.swift:93`
  maps through `Source.with(_:)` (`:202`), which copies
  `lastSuccessfulSync` forward. Android `SourceRegistry.kt:116` copies only
  `state`. Neither ever writes the timestamp.
- **Both platforms already mark one source `connecting` before a single-source
  refresh.** iOS `LibrarySourceHealth.swift:203`, Android
  `LibraryViewModel.kt:593`, each with the same comment: *"A test whose only
  visible effect arrives a network timeout later is a button a reader presses
  twice."* So the source detail screen's *Status* row already says a
  single-source refresh is running.
- **`connecting` is safe to draw.** `LibraryAvailability.isReadableNow`
  (iOS `:152`) and `LibraryMarks.isAnswering` (Android `:127`) both treat it as
  answering, precisely so a probe does not grey the shelf and un-grey it a second
  later.

Versions: iOS 26.1 floor, `refreshable` and `safeAreaBar` used directly with no
shim (ADR-0003). Android material3 1.5.0-alpha, `PullToRefreshBox` already in
use at `LibraryScreen.kt:494`.

## Goals / Non-Goals

**Goals:**

- Every occasion a refresh can start has a decided answer for *while it runs* and
  for *when it ends*, and the decision is written down rather than implied.
- One refresh is stated once.
- Completion is stated by something that stays true, not by something that
  vanishes.
- The decision of which line the strip draws is a pure value a test can reach on
  both platforms, mirrored name for name (ADR-0001).

**Non-Goals:**

- Scoping the network probe per source. `ShelfRefresh` owns that cost.
- A progress fraction, a count of sources answered, or a notification.
- Any change to what a pull re-fetches. `ShelfRefresh` decides that and is not
  touched.

## Decisions

### Every place a refresh can start, and what the reader sees

| Where it starts | While it runs | When it ends |
| --- | --- | --- |
| **A source is added** | The existing *still being read* line: *"Still reading 1 library"*. It counts a source that is `connecting` and has put nothing on the shelf, which is exactly this case. **Nothing new.** | The line goes and the covers arrive. The arrival is the statement. |
| **Pull to refresh, iOS** | The system `refreshable` spinner. The closure awaits both halves already, so it is already correct. **Nothing new.** | The spinner retracts. |
| **Pull to refresh, Android** | The `PullToRefreshBox` spinner, **now following the network probe as well as the folder walk**. This is the one platform-specific fix. | The spinner retracts. |
| **The library appearing** | The new *refreshing* line, when the shelf is not the cached one. When it is, the cached line already says *"Checking for changes"* and is kept. | The line is replaced by the *checked* line. |
| **The staleness window / retry backoff** | The same new *refreshing* line. | The same. |
| **Connectivity regained, app foregrounded** | The same new *refreshing* line. | The same. |
| **A source's own *Refresh* action** | The source detail screen's *Status* row reads *Connecting…*, which both platforms already do. **Nothing new.** | The *Last sync* row restates the moment — which needs the stamp below to be true. |
| **A source's own *Test connection* action** | The same *Status* row. **Nothing new.** | The same *Last sync* row. |

### Where nothing is drawn, and why

- **The source detail screen gets no spinner.** It has five rows of facts and a
  *Status* row that already reads *Connecting…* for as long as the source is being
  asked. A spinner beside a row that already says *Connecting…* is the same
  sentence twice. iOS additionally disables the action buttons while one runs
  (`SourceDetail.swift:96`), which is the second half of the same statement.
- **The catalogue and server browsers get nothing.** They have their own
  connection step with its own spinner (`CatalogueSheet.swift:33`,
  `KavitaSheet.kt:114`) and they are a different action — browsing a server, not
  refreshing the library.
- **The reader gets nothing, ever.** *Automatic recovery* forbids interrupting
  reading, and a refresh indicator over a page is an interruption. The retry loop
  already skips a reader who is reading.
- **Settings' source list gets nothing new.** Each row draws its source's state
  from `SourcePresentation`, which already renders `connecting`.
- **A pulled refresh draws no strip line.** The gesture's own indicator is at the
  top of the shelf and is unambiguous. A second line at the foot would be the app
  answering a question the finger already answered.

### Completion is a timestamp, not a transient message

Three shapes were available. The reasons for picking the second:

1. **A transient message** needs a timer, and a timer is a promise the app cannot
   keep — a reader who looks away for four seconds sees nothing at all, which is
   the state this change exists to fix. It also needs a surface: Android would use
   a snackbar, iOS has no equivalent, and inventing one on iOS is what ADR-0001
   forbids.
2. **A timestamp that updates.** Chosen. It is already what the requirement asks
   for — *"when it was last refreshed"* — and it answers the reader's question at
   any moment, not only in the seconds after. It costs no timer and no new
   surface.
3. **The indicator merely stopping.** Kept for the two pulled cases, where the
   reader is holding the gesture and watching it, and rejected everywhere else: a
   line that disappears is unobservable by anyone who was not already looking at
   it.

So completion is stamped once and read in two places:

- `marking(_:as:)` records the moment when the new state is `connected`. This is
  the whole of the fix for part 2 of the gap, and it makes the source detail
  screen's *Last sync* row live for the first time on either platform.
- The strip's quietest line states it: *"Libraries checked %@"*, ranked below the
  cached line, below the still-being-read line, and below the refreshing line. It
  is the only thing the strip has to say on an ordinary, current, online shelf,
  which is a bar that is otherwise empty.

The timestamp is read from the registry — the newest `lastSuccessfulSync` across
the sources — so the completion state needs no model field of its own and cannot
disagree with the source detail screen.

### One pure decision for the whole strip

`SourceRefresh.swift` and `SourceRefresh.kt` are new files in each platform's
library feature, beside `ShelfRefresh` and for the same reason: a decision
written inside a view modifier is a decision nothing can assert.

```
SourceRefreshOrigin { pulled, automatic }      // who started it

LibraryNotice {
    stillBeingRead(Int), cached(Date), refreshing, checked(Date), none
}

LibraryNotice.of(refreshing:, waiting:, cachedAt:, checkedAt:)
```

Flat rather than nested inside a namespace type: `SourceRefresh` would hold
nothing of its own, and an empty wrapper is a name to learn for no behaviour.

Five branches, in that order:

1. `waiting > 0` → `stillBeingRead`. The shelf is incomplete, which outranks
   everything else the strip can say.
2. `cachedAt != nil` → `cached`. The shelf is last session's, and that line
   already carries *"Checking for changes"*.
3. `refreshing == .automatic` → `refreshing`. Not `.pulled`: see above.
4. `checkedAt != nil` → `checked`.
5. otherwise → `none`.

iOS keeps `refreshing` on `LibraryModel`, set and cleared around
`probeNetworkSources`, whose new `origin:` parameter defaults to `.automatic`;
only `LibraryView`'s `refreshable` closure passes `.pulled`. Android keeps it as a
`StateFlow` on `LibraryViewModel`, set and cleared in a `try/finally` around
`probeAndWait`; `retryUnreachableSources` passes the origin to its **first** probe
only, because every later one in that loop is the backoff and not the finger.
Android's `onProbeSources` lambda becomes `(SourceRefreshOrigin) -> Unit`, which
is the signal `ShelfRefresh.kt:34` said was missing.

The pull indicator itself is a second, smaller decision, `isRefreshingShelf(scan:
refreshing:)`, and it is **Android-only**. SwiftUI awaits its `refreshable`
closure, so iOS has no boolean to decide; ADR-0001 asks for the same shape where
the platforms have the same problem, and here they do not.

The bulk-selection bar and the missing-folder notice stay above all four notices
and are not about sources. They moved with the rest of the strip into
`LibraryBottomBar.swift`, an extension on `LibraryView` — a fourth branch took
that file past its 400-line cap, and this is the seam `LibraryPanes.swift` and
`LibraryContent.swift` were already split along. `BulkSelectionChromeTests` reads
the branch's source text and now reads it from its new home.

### Risks

- **`marking` stamping on every probe means the timestamp moves every time the
  library appears.** That is what *last successful sync* means, and it is
  persisted by `SourceStore` on both platforms, so it survives a launch. A source
  that fails keeps its old value, which is the *A refresh that failed* scenario.
- **A local folder is stamped too**, because `markLocal` marks it `connected`.
  Correct: the folder answered. `markLocal` early-returns when the state has not
  changed, so a connected folder is not re-stamped on every appearance — which
  means a folder's *Last sync* is the moment it last changed state, not the moment
  it was last looked at. Recorded rather than fixed: the field is on the source
  detail screen, and a folder that has been readable for a week is honestly
  described by the moment it became readable.
- **Three files are within six lines of their cap**: `LibraryView.swift` (397 of
  400), `LibraryModel.swift` (394 of 400) and `LibraryScreen.kt` (799 of 800).
  The first is split, as above. The second takes two lines and lands at 400. The
  third lands at exactly 800, which is why its pull indicator is a named function
  rather than an expression: the condition needed a test anyway, and putting it
  in `SourceRefresh.kt` is what keeps the screen inside its budget.
- **`ShelfRefreshTest.kt` reads `LibraryScreen.kt`'s own source text** and asserts
  the literal `onProbeSources()` appears after `onRefresh = {`. Changing that
  lambda's signature breaks the test, which is the test working. It is updated in
  the same task.

## Migration

None. `lastSuccessfulSync` is already persisted and already nullable on both
platforms, and a registry written before this change loads with whatever it held.
