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
- [x] 3.2 iOS: the player's `Close` button gives way to the sheet's grabber —
      `FullPlayerView.swift:61`. A sheet already has two ways out and the button sits where the
      grabber wants to be.
      **Done.** The `ToolbarItem(placement: .confirmationAction)` is gone, and with it the whole
      `.toolbar` — it held nothing else — so the artwork starts where the pill used to sit.
      **The grabber is now drawn rather than merely available.** `.presentationDragIndicator(.visible)`
      is the other half of the task and it is not cosmetic: the drag always worked and was
      unadvertised, so removing the button without drawing the grabber would have left a sheet
      with no *visible* way out at all. This is a full-height sheet, so there is no scrim to tap.
      **The assistive-technology route is kept and made explicit.** VoiceOver dismisses a
      presented sheet with the escape gesture rather than by finding a button, and
      `.accessibilityAction(.escape)` states that on the view so the surface does not depend on
      the platform continuing to provide it by default. It is stated rather than assumed because
      nothing in the build would notice if it stopped being true.
      **`PlayerAuditTests` asserted the button, and now asserts its absence.** Its walk waited on
      `app.buttons["Close"]` to know the player had appeared; the landmark is `Chapters` now — a
      control `audio-playback` *requires* the player to offer, so unlike Close it cannot be
      removed without the spec changing, which is exactly what happened to the old one.
      `testASheetIsStillDismissibleWithoutACloseButton` is new: it fails first if a Close button
      is on the player at all, then drags the sheet away and asserts the listener is back on the
      shelf with the compact bar. The XCUITest API has no escape gesture, so that route is
      covered by the explicit action above and by the audit rather than by a walk — said here
      rather than left as a silent gap.
      `ReadAloudPlayerTests` also matches `app.buttons["Close"]`; that is the **reader's**
      `reader.close`, not the player's, and is untouched. The `player.close` string stays in use
      by `ChapterListView`, which keeps its own explicit Close.
      **Photographed** at the default and largest text sizes —
      `docs/designs/screenshots/after-2026-09-01-ios-player-artwork/`, against
      `after-2026-09-01-ios-player/` as the before, which shows the pill and no grabber.
      §2.6 still owes the library toolbar's own pair; this covers the player only.
- [x] 3.3 Android: **no equivalent change to the player.** Its player is a destination rather
      than a sheet, so it needs its back affordance and has no grabber to defer to. A
      divergence from the platforms, not from taste — record it, do not "fix" it.
      **Confirmed by reading, and no Android UI changed.** Four things in the source say it, and
      the last two say it more strongly than the task assumed:
      1. `navigation/Destinations.kt:192` — `data object Player : Screen`. It is a member of the
         `Screen` sealed interface, which *is* the navigation stack's element type.
      2. `AppNavigation.kt:69` / `:103` — it arrives by `push(Screen.Player)` from
         `AppShell.kt:179` and `:323`, and leaves by the one `back` rule that pops the stack.
      3. **A sheet is a different type on this platform, and the type's own comment says why.**
         `AppSheet` is documented as "not part of `AppNavigation`: a bottom sheet is not a place,
         it dismisses itself, and it brings its own back handling". The player is not one.
      4. `Screen.Player.hidesNavigation` is `false`, with the reason recorded beside it: "the
         player is somewhere a listener goes *to* while the book plays, and taking the
         destinations away would strand them there". So it is not even a full-window screen —
         the navigation bar stays under it. `AppShell.kt:302` hides the *compact bar* while the
         player is current, which is a destination's business and something a sheet over the
         shelf would never need to do.
      Its back affordance is `PlayerScreen.kt:98` — a `TopAppBar` `navigationIcon` holding
      `Icons.AutoMirrored.Filled.ArrowBack` with `R.string.player_back` as its
      `contentDescription`, auto-mirrored for right-to-left. Removing it would leave a pushed
      destination reachable only by the system back gesture, which is the opposite of what §3.2
      does on iOS: there the platform supplies a dismissal the app was duplicating, and here the
      app supplies the only one there is.
      `Destinations.kt:185` also records that Android's drag-to-expand sheet "is deferred to its
      own change and this is a screen until then" — so **if** that sheet ever lands, §3.2's
      question arrives on Android with it. It has not, and this tick is not a decision about it.

## 4. Close-out

- [ ] 4.1 `docs/openspec/STATUS.md`, and `docs/designs/ui-revamp-2026-08.md` if it describes
      the toolbar or the notice.
- [ ] 4.2 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 4.3 `pnpm spec:guard:strict`.
- [ ] 4.4 `/opsx:verify named-failures-and-quieter-chrome`, then `/opsx:sync`.
