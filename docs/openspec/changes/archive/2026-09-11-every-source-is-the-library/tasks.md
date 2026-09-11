**What a tick means.** The code exists and something asserts it — a unit test, a
Robolectric or XCTest suite, or a committed screenshot with a control frame
beside it. A tick does not mean a reader has used the screen.

**One open question rides along.** design.md leaves the size of a source's first
slice unfixed. Task 3.2 carries it as one named constant so the number can be
chosen against a real server without touching anything else.

## 1. Nothing is deleted by an answer that did not arrive

- [x] 1.1 Android only, as `ServerRowsSurviveAScanTest`. It holds **by construction, not by a branch**: `ScanReconciliation.vanished` only considers a source that appears in `seenBySource`, and a server appears in no walk — so a contributor that throws, or answers nothing, costs no row. Pinned because the next person to touch that one line will not know a server's rows depend on it. The third case (a complete answer that omits a publication) is not yet reachable: nothing tells the reconciler a server answered completely, and it will not be until a contributor can say so.
- [x] 1.2 Android only: a walk over one folder leaves a server's rows alone, and still removes what its own folder no longer holds. **iOS has no equivalent yet** because iOS has no contributor yet.
- [x] 1.3 **No code was needed.** Coverage is already per source and already explicit — `seenBySource` plus `partial` — and a source no round covered is already untouched. The task assumed a change the code had already made; 1.1 pins it instead.

## 2. A source contributes, whatever kind it is

- [x] 2.1 **The second contributor arrived inside this change, and it answered the question. The seam is still not extracted, and now for a measured reason rather than a guessed one.**

  This task deferred the interface until there was a second implementation to observe, and named the open question: is the contract `(source) -> publications`, or something that also reports coverage and paging? There are now three implementations -- `KavitaContributor`, `OpdsContributor` and `SmbContributor`, on both platforms -- so the question can be read off the code instead of guessed.

  **The output is agreed and it is the second answer.** All three return `SourceSlice`, which carries the publications *and* whether the source held more back. That is exactly "something that also reports coverage", so the simpler contract this task offered as the alternative is ruled out by observation.

  **The input is not agreed, and cannot be.** Each takes a different second argument: `KavitaContributor` a `KavitaClient`, `SmbContributor` an `SmbClient` and a root, `OpdsContributor` a `CataloguePage`. A single `(source) -> SourceSlice` would need the client bound before the call, so the interface would be a closure built at each call site -- which is what each call site already writes. Extracting it would move no decision and add a type.

  So the seam stays out, and 2.1 is discharged: it asked for an observation and there is one. The next contributor that needs a *fourth* client shape does not change this answer; a contributor that could be driven from the source alone would.
- [x] 2.2 Discharged with 2.1. The scan is untouched and every existing scan test passes unedited, which is the property this task existed to protect. Nothing in the three contributors reaches it.
- [x] 2.3 Both platforms. `KavitaContributorTest` (Android, 8 cases) and `KavitaContributorTests` (iOS, 6): the server identity and the absent path, what a row is drawn from, a numbered issue with no title, `AUTHORITATIVE` origin, each Kavita format, the archive guess pinned as a guess, and two reads of one chapter matching as one row.
- [x] 2.4 Android: `KavitaContributor` over `KavitaClient.recentSeries` and `volumes`, wired at `LibraryViewModel.readServers`, with `remoteCover` resolving a row that has no file. Seen on the phone: the grid holds the server's issues and Home's *Recently added* leads with one. **iOS not done.**
- [x] 2.5 `OpdsContributor` and `OpdsContributorTest`, 7 cases. **One feed, not a crawl** — the root the reader saved; what is deeper stays in the browser and in search, because a catalogue may be a thousand pages deep. A navigation entry is not a publication and is dropped. **No acquisition address survives into a row**, asserted directly: an OPDS link can carry a key in its query and `sources` forbids a cached catalogue holding one. The test caught a real bug — `application/epub+zip` contains "zip", so every book on every catalogue was filing as a comic.
- [x] 2.6 `SmbContributor` on both platforms, with six tests apiece. **A bounded walk, breadth-first**: the root, then the folders it found, level by level, stopping at 200 publications or 40 listings. Breadth-first on purpose — shares put their folders at the root, so a depth-first walk spends the whole budget inside the first one. The row is identified by its **path**, as a scanned file is, so a share's copy and a downloaded copy fold together with no server identifier; and its metadata is the filename's and says so, because reading the file's own means fetching the archive. Not exercised against a live share.
- [x] 2.7 `hasItsOwnBrowser` on both platforms, with the reason on the property: a folder is walked and the other three are browsed through a screen that knows their catalogue's shape. No call site changed its answer — the only code that reads it is iOS's search, and `SourceReachability` referred to it only in a comment.

## 3. What is read, and what is held back

- [x] 3.1 `SourceSliceTest` / `SourceSliceTests`, and the implementation the test needed: `SourceSlice` carries `holdsMore`, each contributor answers it its own way — a full page from Kavita, a `next` link from a catalogue, any of three budgets running out on a share — and `SourceDiagnosis.isPartial` makes the source screen say *at least %d titles* rather than a bare number, in four languages on both platforms.
- [x] 3.2 `KavitaContributor.FIRST_SLICE = 60`, read through `Series/recently-added-v2`, newest first. The number is provisional and its header says so: one request for the page plus one per series, so 60 is roughly the request count. **The unit was the bigger question and design.md did not ask it**: a chapter is the publication, not a series, because a library row must open a book and because chapter ids are what progress, downloads and `serverIdentifier` already key on.
- [x] 3.3 **The affordance, one clause it does not meet, and one it did not meet until a verification pass found it.** `MoreFromTheLibrary` draws a way in at the foot of the shelf for each source that held something back, on both platforms, in four languages; `sourcesWithMore` decides which — a source with a browser of its own that gave less than it has — and five cases per platform assert it, including the one that draws nothing, because an affordance that is always there says nothing. It leads to the source's own browser, which draws the catalogue's cells rather than the library grid's: the *same cells* clause is met for search and not yet here, and that is a screen to rebuild rather than a line to add. **iOS drew it in one branch of three** — a library long enough to divide into sections, which is what a partial server library looks like, showed no way to the rest of it at all. Hoisted out of the branch, and the list layout has it now too, on both platforms.
- [x] 3.4 One case per platform, beside the merge cases that are the control: a row a source answers with, that nothing on the shelf matched, reaches the screen. That is what makes a bounded read honest — the slice is a head start and not a ceiling.

## 3b. A series is the row

- [x] 3b.1 `LibraryRows` and `LibraryRowsTest`, 7 cases: a series is one row however many issues it holds, a publication with no series is its own row, a series of one is not a list to open, a series takes the place its first member had, a scattered series is still one row and keeps every member, a blank series name is no series, and an empty library has no rows. Pure and off the composition, as `LibrarySections` is.
- [x] 3b.2 Android: `rememberShelfRows` collapses the arranged list, `CoverGrid` draws a series cell named for the series and captioned with `shelves_count` — a plural that already existed in all four languages — and `LibrarySections` now divides rows. Seen on the phone.
- [x] 3b.3 `SeriesShelfScreen`, drawing the same `CoverGrid` over one series' members, reached by `Screen.SeriesShelf`. **No test asserts the screen** — it reads the view model's flow and composing it needs one; the frame is the evidence for now.
- [x] 3b.4 `SeriesReturnsToTheLibraryTest`, on the navigation value rather than a device. "At the place the reader left it" is decidable there: `AppPanes` hands `AppNavigation.stateKey` to a `SaveableStateHolder`, so every scroll offset is remembered against that key — the test asserts the key differs while the series is open and is the same again after, which is what makes it a return rather than a reset. **Android only**; iOS's stack is SwiftUI's own and nothing here pins it.
- [x] 3b.5 **Deferred, and this is the record of it rather than an open task.** A row exists today only where a publication does, so a series the app knows of but has fetched no issues for has nothing to draw. Making it lazy needs a row that can exist without members — a real model addition, not a smaller fetch. The cost it would save is bounded and measured: one page plus one call per series in the slice, sixty of them, seconds on the owner's server.

  Left as a recorded deferral rather than an open box: the decision is made, the cost is
  measured, and what it waits on is a model addition that belongs to whichever change
  needs a row without members. An open box here only stops this change from archiving.
- [x] 3b.6 iOS now has all of it: the rule, both contributors, `ServerLibrary`, `LibraryMerge`, a series cell in `CoverGrid`, and `SeriesShelfView` reached by `SeriesRoute` — registered beside the publication page, so a stack that has one has both. **Seen on a simulator**, with four local comics rather than a server — the rule does not care where a publication came from. The library lists the series as one cell with its count, and opening it lists its issues. The simulator caught a bug every unit test passed: a series cell inside the Library split opened the issue leading the series, because the split hands cells a closure instead of a value link and the series branch was only on the link path.

## 4. One row, not two

- [x] 4.1 `DownloadFoldTest` / `DownloadFoldTests`, seven cases each rather than the three asked for — the control (the two identities share nothing, which is the defect), the spelling the card and the contributor have to agree on, and a card from another app. Named for the seam rather than the claim: a publication a source offers and the same publication downloaded are one row; the row is readable with no network; and its `key` does not change when the path arrives. Red before 4.2.
- [x] 4.2 `KavitaCard.remoteIdentity` is the bridge — the card is written when the chapter is kept and holds the source and the chapter, which is the pair the contributor builds an identifier from. `DownloadFold.described` records it on the file's identity and `adopt` records the path against the row already on the shelf. `PublicationIdentity` is unchanged. Verify 4.1 passes, and that `PublicationIdentity` itself is unchanged — `git diff core/model/PublicationIdentity.kt` is empty.

## 5. The cache, and what may not be in it

- [x] 5.1 `CachedServerRowsTest`'s last case, and it is a tripwire rather than a fix: neither contributor puts an address in a row at all — a row is identifiers, and the address and its key live in the source registry and the credential store, so the request is built from those at the moment it is made. The test reads the written snapshot and refuses five spellings of a secret in it.
- [x] 5.2 The cache already held whatever was on the shelf; what it never held was a server's rows, because the snapshot was written when a *folder* walk finished. A reader whose library is one server and no folders had nothing cached and opened the app offline to an empty shelf. `readServers` now writes it, on both platforms.
- [x] 5.3 `CachedServerRowsTest`: clearing one source's cache takes its rows out of the shelf and out of the snapshot, leaves another source's alone, and a source with nothing cached is a no-op. The implementation was already there; nothing asserted it.
- [x] 5.4 Asserted, not measured. `CachedServerRowsTest` restores a snapshot with no source reachable and reads the rows and the refresh time back. The 500 ms clause is not asserted: a Robolectric restore is not a device's cold start, and a number taken here would describe this laptop — the same reason `measure-turn.mjs` exists for the frame budget.

## 6. What a reader sees

- [x] 6.1 `SpokenCellLabelTest` on Android, five cases; iOS's `LibraryMarksTests` already had eight. Both cells were already saying it — the grid's and the list's copies of the same list are now one `spokenCellLabel`, which is what the test asserts.
- [x] 6.2 The unreachable state was already drawn and spoken. The *never read* one was not: a source that has never answered contributes no rows, so a reader who added a server and opened the library saw nothing new and was told nothing, for the twenty seconds the client waits. `StillBeingReadNotice` says it on both platforms, in four languages, above the shelf rather than over it. Three cases deliberately say nothing — a connected server that holds nothing, an unreachable one, and a local folder — because a notice that is usually wrong is one a reader learns to ignore. No frame yet: 6.3 is where that is owed.
- [x] 6.3 Four frames of the grid against the owner's Kavita server and two local comics, plus the foot of the shelf and both screens that state the count. The control is `servers-in-the-library-2026-09-10/android-library-before.png` rather than a new frame — the same phone, before, with local files only. Only Kavita was configured on the device: OPDS and SMB are asserted and not photographed, which the README says.
- [x] 6.4 Four frames plus one scrolled: `Green Lantern Corps Quarterly` is in *Recently added*, on the server and not on the phone, beside two comics that are. Not in *Keep reading* — no server publication has been read on this device, which is the honest reason rather than a fault.
- [x] 6.5 **The negative, and it is the useful half.** The simulator has local fixtures and no server — the owner's key is not on it — so its library shows the same grid, the same series cell, and *no* affordance at the foot, which is what the rule says for a library holding everything its sources gave. A remote row, the partial count and the affordance are asserted on that platform and photographed on neither; the README records it.
- [x] 6.6 `docs/designs/screenshots/every-source-2026-09-10/README.md`, including two things no frame covers: the still-being-read line, which leaves before a screenshot lands, and the iOS gaps above.

## 7. The gates

- [x] 7.1 All three green, `./gradlew lint` over every module rather than the ones touched. It caught two: a plural whose `one` form carried no number, which is an error in French because `one` matches zero there, and a `StateFlow.value` read inside a composition, which would not have recomposed.
- [x] 7.2 Green. Three new strings this round — the still-being-read line, *at least %d titles*, and *more from %s* — each in four languages on both platforms.
- [x] 7.3 Green.
- [x] 7.4 Reconciled before any code was written, because `pnpm delta:drop` fails the build on it rather than waiting for archive. Both changes now carry one identical *Unified library* block — the union of one-library's origin-invisible clause and availability axis with this change's five additions — so the order they sync in no longer matters. The three bullets the union deliberately drops are recorded in `.delta-drops.json` under this change as well as under one-library's.

## Carried from a sibling, and not this change's behaviour

- [x] **A sibling extended this change's `library-browsing` delta, word for word.**
  `a-shelf-of-issues-and-a-rail-to-scan-it` added a series-or-issues choice and an
  alphabetical index to the *Presentation* requirement. A MODIFIED requirement replaces
  the whole block on archive, so whichever of these changes synced second would have
  deleted the other's scenarios. Rather than record a sync order that relies on somebody
  honouring it, the union is written into every sibling delta that holds the requirement
  -- the same safer fix `every-source-is-the-library` chose once before, and the reason
  `pnpm delta:drop` now reports no pair at all.

  **None of that behaviour belongs to this change.** The grouping choice, the index and
  their scenarios are owned, built, tested and photographed by
  `a-shelf-of-issues-and-a-rail-to-scan-it`. This delta carries them so that archiving in
  any order leaves the main spec whole.

  Recorded here because the edit made this change's `specs/` newer than its `tasks.md`,
  which is what `openspec-guard` reads as `[stale]`. The task list was not describing an
  older plan; it had not been told about a sibling's edit. It has now.
