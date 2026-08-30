# Tasks

Slices **F1** and **F2** of
[`docs/designs/ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md) §7.1,
plus the colour wiring neither of them names as work because it looks like it is
already done.

**Every task that changes a screen owes a screenshot from a booted simulator or
emulator** — light and dark, default and largest text size — per
[AGENTS.md §6](../../../../AGENTS.md). Previews are not proof.

**Ordering:** on Android, Phase 2 onwards depends on the navigation graph from
`one-library-three-destinations`. On iOS there is no such dependency; the screen
can be pushed onto the existing stack.

## Phase 0 — Answer before building

- [ ] **0.1** Confirm a cover thumbnail is available to sample at the moment the
      page is composed, on both platforms, for each of the four source types.
      Deliverable: the answer, and if it is "not always", the placeholder-then-adopt
      behaviour the delta requires, with no visible flash.
- [ ] **0.2** Decide where the Android accent slot lives — a composition local
      beside the palette, matching the shape of the iOS environment modifier — and
      confirm it composes with the dynamic-colour scheme without tinting chrome.
      Deliverable: the slot, with a test that chrome colour is unchanged when an
      accent is set.

## Phase 1 — The colour reaches the library half of the app

- [ ] **1.1** iOS: call `CoverAccent` from the library half and put the result in
      `Theme.coverAccent`, which has had a slot and no caller since it was written.
- [ ] **1.2** Android: the slot from 0.2, plus the caller.
- [ ] **1.3** Host tests, mirrored case for case per the project's rule for
      mirrored code: a colour that clears the floor, one that must be adjusted to
      clear it, a monochrome cover that yields nothing, and an undecodable cover.
      Both platforms assert the same answers.
- [ ] **1.4** Screenshot the wash under increased contrast and reduced
      transparency, where the delta requires a plain surface rather than a softened
      one.

## Phase 2 — The screen

- [ ] **2.1** **[F1]** iOS: the page — cover over the wash, title block, one
      primary action, secondary actions in a menu, description, series shelf,
      provenance line. Screenshot: a downloaded local publication, a cached remote
      one, and one whose source is unreachable.
- [ ] **2.2** **[F2]** Android: the same content model with Material
      composition. Same three screenshots.
- [ ] **2.3** Every cover on every surface leads here; every resume affordance
      still opens the book directly. Screenshot the two paths from the home
      surface.
- [ ] **2.4** The page for a publication with no series, no year, no description
      and no cover — the composition has to hold up with a title and a placeholder.
      Screenshot both platforms.

## Phase 3 — Provenance and the seam

- [ ] **3.1** The provenance projection: the source's user-given name plus the
      availability answer, computed with no network call.
- [ ] **3.2** The same-publication-in-two-places case: the line names the copy
      this page will open and says another exists. Test with one publication
      present locally and on a server.
- [ ] **3.3** The removed-source case: the download survives, the line says "on
      this device", and no removed library is named. Test, not inspection — this
      is the case that will silently render a stale name.
- [ ] **3.4** Confirm by inspection of the browse path that origin appears
      nowhere else: home, library, on-device destination, search, shelves. This is
      the seam's only test and it is a `grep` plus four screenshots.
- [ ] **3.5** No new user-facing string ships from this change. If the provenance
      line needs one, hand it to the vocabulary slice rather than adding it here.

## Phase 4 — Large screens

- [ ] **4.1** iPad: the page as the split's detail column, with the hero art
      carrying under the floating sidebar. Screenshot portrait, landscape and Split
      View.
- [ ] **4.2** Android: the detail pane, with predictive back animated by the
      scaffold. Screenshot expanded width, and the narrow-then-widen path.
- [ ] **4.3** The empty second pane before a publication is chosen — one
      sentence, not an arbitrary publication. Screenshot both platforms.

## Phase 5 — Gates

- [ ] **5.1** `corepack pnpm spec:validate`.
- [ ] **5.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm build:ios`. The new screen must not put any Swift file over 400 lines —
      compose it from several.
- [ ] **5.3** Android: `./gradlew test lint`, 800-line cap.
- [ ] **5.4** `corepack pnpm lint`, which includes `tokens:check` — the derived
      colour has to clear the same contrast gate the palette does.
- [ ] **5.5** The screenshot set is complete and referenced in the handoff.
