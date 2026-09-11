# Tasks

This change amends one specification requirement. It writes no application code,
so no task here owes a screenshot from a simulator or an emulator.

A task is ticked when the file it names holds what the task describes.

## 1. Establish the cost from the code

- [x] 1.1 Read what a cover tap does on iOS. `CoverCell.swift:68` and
  `CoverList.swift:118` both push a `PublicationRoute`, which is the publication's
  page. Neither opens a reader.
- [x] 1.2 Read what a cover tap does on Android. `CoverGrid.kt:432` and
  `CoverList.kt:199` call `onOpen`; `AppDestinations.kt:99` binds that parameter to
  `AppHost.openPage`, which pushes `Screen.PublicationPage`.
- [x] 1.3 Read what the page's primary action does. It is one button. On iOS
  `DetailActions.swift:94` draws it and `DetailActions.swift:120` labels it from
  `PrimaryAction`; on Android `primaryActionOf` at `DetailActions.kt:58` returns
  `CONTINUE` for an on-device publication with progress. Both open the book at the
  stored position.
- [x] 1.4 Read the resume affordance on both. `HomeScreen.swift:178` hands the
  Keep reading hero `open`; `HomeDestination.kt:166` hands it `resume`, which calls
  `host.open` with the recorded location. One action each.
- [x] 1.5 Record the two numbers: two actions by cover, one by a resume
  affordance, on both platforms.

## 2. Find out whether the amendment already exists

- [x] 2.1 Read `docs/openspec/STATUS.md` for the `reading-progress` and
  `publication-detail` rows before claiming anything is missing.
- [x] 2.2 Search the live changes for a `## MODIFIED` block on `reading-progress`.
  `changes/publication-detail/specs/reading-progress/spec.md` holds one, added by
  commit `3ba316c1` on 2026-08-31.
- [x] 2.3 Decide what is left to add. The two verbs are already split and the dead
  reason clause is already replaced. The action count is not stated anywhere.

## 3. Write the amendment

- [x] 3.1 Carry `publication-detail`'s whole *Resuming* block into this change's
  delta, word for word, so the two blocks are nested and not disjoint.
- [x] 3.2 Add the SHALL sentence that requires the cost of each verb to be stated.
- [x] 3.3 Add the action count to *Continue from a resume affordance* and to
  *Continue from the library*.
- [x] 3.4 Bound the two counts in the delta itself. A publication that draws no
  continue action has no path back into the book, so no count applies to it. The
  bound is stated in the requirement prose because only `specs/**` reaches the main
  spec on sync; a bound left in `design.md` is archived and lost.
- [x] 3.5 Leave *Restart deliberately* exactly as `publication-detail` wrote it.
  Its reason clause is already correct and amending a correct clause is a defect.

## 4. Keep the two deltas from deleting each other

- [x] 4.1 Record the sync order in `.delta-drops.json` under `collisions`, as
  `["publication-detail", "two-taps-back-to-the-book"]`, with the reason.
- [x] 4.2 Run `pnpm delta:drop` and read what it says about the pair.
- [x] 4.3 **Then take the order away, because an order relies on someone
  honouring it.** `every-source-is-the-library` already met this and chose the
  safer fix: write the union into both files so the sync order cannot matter. This
  block is the union, so it is now `publication-detail`'s block as well, word for
  word. The `collisions` entry is removed and `pnpm delta:drop` reports no pair at
  all rather than a pair with a recorded order.
- [x] 4.4 The counts belong in `publication-detail`'s delta on their own merit.
  That change is the one that made a cover cost two actions, so a delta of its own
  that did not say so was the less honest of the two.

## 5. Hand the decision to the owner

- [x] 5.1 State in the proposal that the library path costs one action more than
  the requirement promised, and that this is worse for a reader who only wants to
  carry on.
- [x] 5.2 State the three facts that bound the cost, and make a recommendation
  rather than a silent blessing.
- [x] 5.3 **Decided by the owner on 2026-09-11: accept two actions.** The
  publication page earns the action it costs, and the one-action route stays where
  it is -- Keep reading, the hero on Home on both platforms. So the delta states
  the two counts and blesses neither path as the only one. Nothing moves to
  `publication-detail`, because two is not too many.

## 6. Left for whoever owns the file

- [x] 6.1 **Corrected, though it is not this change's file.** `STATUS.md`'s
  `reading-progress` row said `publication-detail`'s delta "does not list
  `reading-progress` as MODIFIED". Commit `3ba316c1` made that false on 2026-08-31.
  A stale sentence in the file agents read first is worse than a tidy scope, so the
  one sentence is fixed here and named in the commit.
