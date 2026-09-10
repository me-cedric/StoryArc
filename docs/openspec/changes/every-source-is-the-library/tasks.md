**What a tick means.** The code exists and something asserts it — a unit test, a
Robolectric or XCTest suite, or a committed screenshot with a control frame
beside it. A tick does not mean a reader has used the screen.

**One open question rides along.** design.md leaves the size of a source's first
slice unfixed. Task 3.2 carries it as one named constant so the number can be
chosen against a real server without touching anything else.

## 1. Nothing is deleted by an answer that did not arrive

- [ ] 1.1 Write `ContributorCoverageTest` / `ContributorCoverageTests`: a source whose contributor throws mid-round loses no row; one that answers a partial page loses no row; one that answers completely and omits a publication loses that row and keeps its progress. Red before 1.3.
- [ ] 1.2 Write the test that a round covering only source A never touches source B's rows, on both platforms. Red before 1.3.
- [ ] 1.3 Extend the reconciliation in `LibraryViewModel` (`feature/library/LibraryViewModel.kt`, the `partial` set at the scan) and its Swift twin so coverage is per source and explicit, and a partial round deletes nothing. Verify 1.1 and 1.2 pass, and that the existing scan tests are unchanged.

## 2. A source contributes, whatever kind it is

- [ ] 2.1 Write the contributor contract's test first, against a fake: given a source it answers publications and whether that is all of them. Assert the folder scan satisfies it with no behaviour change — the existing scan suite is the control and must pass untouched.
- [ ] 2.2 Introduce the contributor seam and make `LibraryScanner` the first implementation. Verify: `pnpm test:android` and `pnpm test:ios` green with no test edited.
- [ ] 2.3 Write `KavitaContributorTest` / `Tests`: a Kavita source answers publications carrying `serverIdentifier(sourceId, remoteId)`, no `normalizedPath`, the series' own title and cover reference. Red before 2.4.
- [ ] 2.4 Implement the Kavita contributor over `KavitaClient`. Verify 2.3 passes on both.
- [ ] 2.5 The same pair for OPDS, over `OpdsClient`.
- [ ] 2.6 The same pair for SMB, over `:core:smb` — a share's files are files, so this one produces paths as well as a server identifier.
- [ ] 2.7 `SourceKind.isBrowsable` stops meaning "not in the library". Rename it to what it now means, on both platforms, and verify every call site still answers the same question — `SourceReachability.kt:62` names it explicitly and is the one to read first.

## 3. What is read, and what is held back

- [ ] 3.1 Write the test for the partial count: a source that holds more than was read states that it is partial, and the number shown is never presented as the whole. Red before 3.2.
- [ ] 3.2 Read a bounded, recency-ordered first slice per source, behind one named constant. Verify 3.1 passes. **The constant's value is the open question** — pick it against the owner's own server and record the number and the reason beside it.
- [ ] 3.3 Write the test that a publication reachable only through "more from this library" opens the same publication page and is rendered by the same cell, then wire the affordance.
- [ ] 3.4 Assert search still reaches what the index does not hold, on both platforms — `library-browsing`'s *Mixed local and server search* is the existing requirement and the existing tests are the control.

## 4. One row, not two

- [ ] 4.1 Write `RemoteAndDownloadedAreOneRowTest` / `Tests`: a publication a source offers and the same publication downloaded are one row; the row is readable with no network; and its `key` does not change when the path arrives. Red before 4.2.
- [ ] 4.2 Fold a downloaded copy into the remote row using `PublicationIdentity.matches`, keeping the original key. Verify 4.1 passes, and that `PublicationIdentity` itself is unchanged — `git diff core/model/PublicationIdentity.kt` is empty.

## 5. The cache, and what may not be in it

- [ ] 5.1 Write the test that no cached row holds a secret: an OPDS acquisition URL carrying a key in its query, and a Kavita route carrying `apiKey`, are both stored stripped, and the request made from a stored row still carries the secret. Red before 5.2.
- [ ] 5.2 Extend the library cache to hold rows no walk produced, with the address stripped and the secret re-applied from the credential store at request time. Verify 5.1 passes on both platforms.
- [ ] 5.3 Write the eviction test: clearing a source's cache removes its rows rather than leaving rows that open nothing, marks the source as needing to be read again, and leaves downloads and reading progress alone. Then implement it.
- [ ] 5.4 Assert the offline path: with every source unreachable, the cached library still draws, and the indicator says when it was last refreshed. `sources`' 500 ms clause is the bar; measure it rather than asserting it by eye.

## 6. What a reader sees

- [ ] 6.1 Write the test that a row needing its source states so in its accessibility label and not only by dimming, on both platforms. Red before 6.2.
- [ ] 6.2 Draw the unreachable and never-read states in the grid, and the "not read yet" sentence for a source that has never answered. Verify 6.1 passes.
- [ ] 6.3 Screenshot the library on the OnePlus 7T Pro (`f7cee850`) against the owner's Kavita, OPDS and SMB sources together: light and dark, default and largest text. Control: the same library before this change, same device, same appearance — which shows local files only, and is the whole point.
- [ ] 6.4 Screenshot Home with a remote publication in *Recently added* and, if one is part-read, in *Keep reading*. Same controls.
- [ ] 6.5 Screenshot the same two on iOS in the Simulator, with the same controls.
- [ ] 6.6 Write the screenshot README: device, sources, server versions, what each control proves, and anything a frame does not cover.

## 7. The gates

- [ ] 7.1 `pnpm test:android`, `pnpm test:ios`, `./gradlew lint` clean for every module touched.
- [ ] 7.2 `pnpm lint` green, including `strings:drawn` and `strings:ios` for every new string in all four languages.
- [ ] 7.3 `pnpm spec:validate && pnpm spec:guard` green.
- [ ] 7.4 Reconcile with `one-library-three-destinations` before either is archived: both modify *Unified library*, and whichever archives second must carry the other's scenarios. Read both deltas side by side and say in writing which wins where.
