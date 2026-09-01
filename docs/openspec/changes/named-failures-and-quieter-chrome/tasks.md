# Tasks — named failures and quieter chrome

Test-first. §6 applies to all three visible changes; `design.md` records which claim in the
review was verified, which was undercounted, and which was stale.

**Two of the review's items are not in this list**, because the capabilities they touch are
owned by changes that are still open — see design.md's routing table. The hero is four new
scenarios in `one-library-three-destinations`; the player's artwork is one in
`audiobooks-and-playback`. Their tasks live there.

## 1. A failure names its publication

- [ ] 1.1 Both: the indexer's reasons are **kept**, not counted. `PublicationIndexer` already
      produces `IndexError.unsupported(format:)`, `.unreadable(reason:)` and
      `.contentProtected`, each worded and translated; the scan keeps only the tally. Carry
      the pairs through. Test first, with `refused.cb7` and `rar4-solid.cbr` from the corpus —
      two files that fail *differently*, which is the case a merged reason would hide.
- [ ] 1.2 Both: one failure names its publication and its reason. Assert the reason is the
      one `publication-formats` gives, not a new sentence.
- [ ] 1.3 Both: several state the count and lead to a list, each row with its own reason.
      Assert two differently-failing files produce two different reasons.
- [ ] 1.4 Both: the notice is **not on a timer**. Delete the `dwell` and the `isShowing`
      countdown in `LibraryStates.swift`; the same in `LibraryScreen.kt`. Assert it survives
      longer than the old six seconds — a test that only checks it appears would pass against
      the toast.
- [ ] 1.5 Both: it does not obscure a cover. It is not a floating overlay any more.
- [ ] 1.6 Both: dismissal is the reader's, and the list stays reachable from the library
      afterwards. That makes it **state rather than an event**, so the library's model owns it
      beside the scan results it already holds.
- [ ] 1.7 Both: the same set does not re-announce itself. Assert a second scan finding the
      same failures does not bring the notice back.
- [ ] 1.8 Both: a publication that later opens leaves the list without being dismissed, and
      the notice goes when the list empties. **This is the one that keeps the feature honest** —
      without it the list becomes a graveyard and a reader learns to ignore it, which is the
      toast's failure arrived at slowly.
- [ ] 1.9 Both: announced once, naming the publication or the count, and it does not steal
      focus from the shelf. The way to the list is a named control, not the whole notice.
- [ ] 1.10 Both: captures. The "before" must be taken **within six seconds of a failing scan**,
      because that is how long the toast lives.

## 2. The toolbar keeps two controls and a menu

- [ ] 2.1 iOS: `LibraryToolbarTests` — count the `ToolbarItem`s in `.primaryAction`. There are
      **six** today (the review said five). Assert the count after, and mutation-check by
      re-adding one.
- [ ] 2.2 iOS: fold the show and scope controls into the menus already there. `SortMenu` and
      `FilterMenu` stay; `AddSourceMenu` stays, being a different kind of act.
- [ ] 2.3 iOS: **select stays on its own**, and the test says why: it changes the surface's
      *mode* where the rest present a choice and leave. A mode switch inside a menu of choices
      is how a reader lands in selection without asking.
- [ ] 2.4 Both: every standalone control names itself to assistive technology whatever it
      draws. Assert it for each.
- [ ] 2.5 Android: no change to the library's own controls — it already uses menus for these
      choices. Confirm that by reading it, and say so in the tick rather than silently
      skipping the platform.
- [ ] 2.6 iOS: captures before and after, at default and largest text size.

## 3. Two smaller ones

- [ ] 3.1 Android: the sort chip says it is an ordering. `library_sort_title` is "Title" and
      the chip shows it alone, which beside a "Filter" chip reads as a filter value. Same for
      grouping, which is neither a sort nor a filter. Four languages.
- [ ] 3.2 iOS: the player's `Close` button gives way to the sheet's grabber —
      `FullPlayerView.swift:61`. A sheet already has two ways out and the button sits where the
      grabber wants to be.
- [ ] 3.3 Android: **no equivalent change to the player.** Its player is a destination rather
      than a sheet, so it needs its back affordance and has no grabber to defer to. A
      divergence from the platforms, not from taste — record it, do not "fix" it.

## 4. Close-out

- [ ] 4.1 `docs/openspec/STATUS.md`, and `docs/designs/ui-revamp-2026-08.md` if it describes
      the toolbar or the notice.
- [ ] 4.2 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 4.3 `pnpm spec:guard:strict`.
- [ ] 4.4 `/opsx:verify named-failures-and-quieter-chrome`, then `/opsx:sync`.
