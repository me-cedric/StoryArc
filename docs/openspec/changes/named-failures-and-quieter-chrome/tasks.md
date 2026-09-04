# Tasks — named failures and quieter chrome

Test-first. §6 applies to all three visible changes; `design.md` records which claim in the
review was verified, which was undercounted, and which was stale.

**Two of the review's items are not in this list**, because the capabilities they touch are
owned by changes that are still open — see design.md's routing table. The hero is four new
scenarios in `one-library-three-destinations`; the player's artwork is one in
`audiobooks-and-playback`. Their tasks live there.

**What a tick in §1 means**: the code exists on both platforms, something automated asserts
it, and that assertion was run. Where a picture is the only possible proof it was taken and
filed — `docs/designs/screenshots/named-failures-2026-09-01/`. A tick does **not** mean the
whole change is verified; §4.4 owns that.

**Three things this section's own text got wrong**, corrected in place below rather than
worked around silently:

- `rar4-solid.cbr` is not a file that reaches a skip. A solid RAR4 is *found* and marked
  unopenable on purpose, so the second differently-failing fixture is
  `password-protected.cbz`. `LibraryScannerTests` has always asserted the found behaviour.
- The refusal sentences are **worded** by `publication-formats` and are **not translated**:
  they are English literals in each platform's format layer. Nothing here invents a second
  wording — that is what §1.2 forbids — so the notice now shows English reason text in a
  four-language app. Named as a gap, not fixed here.
- Android's count was never on a timer. `design.md` says both platforms had a six-second
  `dwell`; only iOS did. The Android half of §1.4 is a placement change, not a timer removal.

## 1. A failure names its publication

- [x] 1.1 Both: the indexer's reasons are **kept**, not counted. `PublicationIndexer` already
      produces `IndexError.unsupported(format:)`, `.unreadable(reason:)` and
      `.contentProtected`, each worded — **and not translated**: they are English literals in
      both scanners, and the `Formats` module carries no string catalogue at all. The notice's
      own strings are localised in four languages; the reasons inside it are not. Confirmed by
      a verification pass on 2026-09-04 against this change's own `ios-skipped-list.png`, which
      shows two English rows inside a translated frame. The debt is written up in `design.md`
      and belongs to `publication-formats` + `localization`, not here. The scan keeps only the
      tally. Carry
      the pairs through. Test first, with `refused.cb7` and `rar4-solid.cbr` from the corpus —
      two files that fail *differently*, which is the case a merged reason would hide.
      **Done.** `SkippedPublications` on both platforms; `LibraryScanning.swift` and
      `LibraryViewModel.rescan` carry the pairs where they used to `break` and `-> Unit`.
      Android's parallel `var skipped = 0` is gone: one `Skipped` event is one skipped file,
      so the count `Finished` carries is `refusals.size`. Asserted against a real scan of two
      corpus files in `SkippedScanTests` (iOS, 6 tests) and `SkippedScanTest` (Android, 3) —
      with `password-protected.cbz` rather than `rar4-solid.cbr`, which is *found*.
- [x] 1.2 Both: one failure names its publication and its reason. Assert the reason is the
      one `publication-formats` gives, not a new sentence.
      **Done.** `Notice.one(name:reason:)` carries the scanner's own string verbatim;
      `SkippedPublicationsTests` / `SkippedPublicationsTest` assert the exact sentence, and
      the corpus tests assert the CB7's reason names the container. No new wording was added
      — see the gap noted above about those sentences not being translated.
- [x] 1.3 Both: several state the count and lead to a list, each row with its own reason.
      Assert two differently-failing files produce two different reasons.
      **Done.** `Notice.several(count:)` plus a sheet (iOS) and a `ModalBottomSheet`
      (Android). Asserted pure, asserted against the real scanner, and photographed:
      `ios-skipped-list.png` and `android-skipped-list.png` show *the archive is password
      protected* beside *CB7 is not a format StoryArc reads*.
- [x] 1.4 Both: the notice is **not on a timer**. Delete the `dwell` and the `isShowing`
      countdown in `LibraryStates.swift`; the same in `LibraryScreen.kt`. Assert it survives
      longer than the old six seconds — a test that only checks it appears would pass against
      the toast.
      **Done on iOS, and there was nothing to delete on Android.** `ScanSummary` is gone,
      `dwell` and `isShowing` with it; `SkippedNoticeTimerTests` asserts the file holds no
      sleep, no duration and no visibility state, and `UITests/SkippedNoticeTests` waits nine
      real seconds on a booted simulator and looks again (passed, 19.0 s). Android's count had
      no timer — `design.md` is wrong about that — so `SkippedNoticeTest` still advances
      Compose's clock past seven seconds, which is the assertion iOS cannot make off-device.
- [x] 1.5 Both: it does not obscure a cover. It is not a floating overlay any more.
      **Done.** Inline above the shelf on both platforms, on an opaque surface, taking its own
      space: out of iOS's `safeAreaBar` and out of Android's `bottomBar`. The before/after
      pair is the proof — `ios-skipped-toast-before-ax5.png` has the capsule sitting on a
      cover with the artwork showing through it.
- [x] 1.6 Both: dismissal is the reader's, and the list stays reachable from the library
      afterwards. That makes it **state rather than an event**, so the library's model owns it
      beside the scan results it already holds.
      **Done.** `LibraryModel.skipped` and `LibraryViewModel.skipped`, beside `scanState`.
      Dismissal collapses the notice to a named control rather than to nothing —
      `Notice.reachable`, which is a fourth case precisely because `nothing` and *dismissed*
      are different. Asserted on both platforms; the Android dismissal is driven through the
      control's own semantics action in `SkippedNoticeTest`.
- [x] 1.7 Both: the same set does not re-announce itself. Assert a second scan finding the
      same failures does not bring the notice back.
      **Done.** Acknowledgement is by name, not by a flag, so a set that *grows* still has
      something to say. Asserted pure on both platforms and against two real consecutive
      scans of the same folder in `SkippedScanTests.secondScanIsQuiet`.
- [x] 1.8 Both: a publication that later opens leaves the list without being dismissed, and
      the notice goes when the list empties. **This is the one that keeps the feature honest** —
      without it the list becomes a graveyard and a reader learns to ignore it, which is the
      toast's failure arrived at slowly.
      **Done, and it falls out of one decision**: settling *replaces* the list at the end of a
      whole scan rather than accumulating, so a walk that opened a publication does not report
      it and a file the reader **deleted** leaves the same way. Acknowledgements are pruned
      with their entries, so a file fixed and then broken again is news a second time.
      `SkippedScanTests.fixedPublicationLeavesTheList` swaps the protected archive for one
      that opens, rescans, and watches the row go; `emptyListEndsTheNotice` deletes the last
      one and watches the notice go.
- [x] 1.9 Both: announced once, naming the publication or the count, and it does not steal
      focus from the shelf. The way to the list is a named control, not the whole notice.
      **Done.** The sentence and its reason are one accessibility element — `.combine` on iOS,
      `semantics(mergeDescendants = true)` on Android — so a screen reader stops once and
      hears the whole fact. Nothing manipulates focus and nothing carries a tap gesture: the
      way to the list is a labelled button. `SkippedNoticeTest` asserts one node carrying both
      halves, exactly one of them, and the control's own name beside it.
- [x] 1.10 Both: captures. The "before" must be taken **within six seconds of a failing scan**,
      because that is how long the toast lives.
      **Done.** Ten pictures in `docs/designs/screenshots/named-failures-2026-09-01/`, both
      platforms, before and after, default and largest text size, with a README saying how to
      retake them. The iOS before was caught by waiting for the strip itself rather than for
      the shelf, on the pre-change sources restored over the tree and then put back.
      `scripts/corpus.mjs` gained `Locked Vault.cbz` so a device can show **two** refusals
      that differ; with one, the two-reasons claim could not be photographed at all.
      Two defects were found by these captures and fixed before they were filed — see the
      README.

## 2. The toolbar keeps two controls and a menu

- [x] 2.1 iOS: `LibraryToolbarTests` — count the `ToolbarItem`s in `.primaryAction`. There are
      **six** today (the review said five). Assert the count after, and mutation-check by
      re-adding one.
      **Done, and the six is now a measurement rather than a second opinion.** The suite was
      written first with the assertion set to `6` against the unchanged sources and run: it
      passed, which is what turns "the review undercounted" into a fact. Flipped to `4` it
      failed, the fold made it pass, and the mutation — one more `ToolbarItem` holding a layout
      button, in the file, compiled — put it at `found → 5` and named the count in the failure
      message. Six tests, all passing: the count, the two folded controls being gone, the three
      folded *choices* still being decided, select standing alone, and each of the four items
      naming itself in words and in four languages.
- [x] 2.2 iOS: fold the show and scope controls into the menus already there. `SortMenu` and
      `FilterMenu` stay; `AddSourceMenu` stays, being a different kind of act.
      **Done — six items to four: `[Select] · [View · Filter] · [Add books]`.** `ScopeMenu` and
      `LayoutToggle` are gone as toolbar items and both of their choices are named pickers
      inside one menu. `FilterMenu` is untouched.
      **`SortMenu` became `ViewMenu`, which goes one step past this task's letter.** The task
      says the sort menu "stays", and the sort choices do — field and direction, their own
      pickers, unchanged. What could not stay is the *name*: a type and a toolbar label reading
      *Sort* that also decide availability and layout is exactly the drift this repository keeps
      paying for, and `library-browsing` asks the menus to be *named* for what they hold. So the
      menu is `library.view` — "View", the word Apple's own file browser uses for the menu that
      holds layout and ordering together — and the layout picker inside it is `library.layout`,
      "Show as", because the options are Grid and List and that is the sentence a reader
      completes. Both keys are in all four languages and `pnpm strings:ios` passes.
      **Availability went into the *view* menu, not the filter menu, and that is a decision.**
      Putting it in `FilterMenu` was the obvious fold — that menu already holds the binding, to
      reset it with *Clear filters* — and it would have made the axis a filter by placement
      while every other line in this module calls it the library's primary axis and deliberately
      keeps it out of the filter badge. Two things follow: `LibraryNarrowing.activeCount` is
      untouched, so iOS and Android still report the same number; and the requirement that the
      choice be "visible while it is active" needed a new home, because `ScopeMenu`'s own glyph
      was holding it. `ViewMenu`'s icon holds it now, plus the `accessibilityValue` the old
      control carried.
      **This said `ellipsis.circle` while the shelf shows everything, the availability symbol
      while it does not — and later work reversed it on 2026-09-04.**
      `LibraryBrowsingControls.swift` now draws the availability symbol *unconditionally*, and
      its own comment argues against the two-state version by name. The requirement is better
      served: "visible while it is active" now holds in **both** states rather than one.
      The proof moved with it — `quieter-toolbar-2026-09-02/ios-toolbar-after-light.png` shows
      a `•••`-in-circle and is a picture of the superseded shape, while
      `stated-axes-2026-09-04/` photographs what shipped.
      **The layout toggle became a picker rather than moving as a button.** It drew the layout it
      would switch *to*, which is unreadable inside a list of choices: a row saying "List" beside
      a shelf drawn as a grid states neither where the reader is nor where they would go.
      **`ScopeMenu.swift` is `LibraryAvailability.swift`.** The file is named for the enum the
      whole module reads; only the control ever lived beside it. The argument for why the axis is
      not a filter is kept there, at the place a future fold would look first.
- [x] 2.3 iOS: **select stays on its own**, and the test says why: it changes the surface's
      *mode* where the rest present a choice and leave. A mode switch inside a menu of choices
      is how a reader lands in selection without asking.
      **Done.** `selectStandsAlone` asserts three things and its doc comment carries the reason
      in the spec's own terms: the toolbar contains no `Menu {` of its own — so there is nowhere
      in this file for `selection.begin()` to have been folded into — the way in is still here,
      and it is `.disabled(selection.isActive)` rather than absent, so the control does not move
      while the reader is using it. The "why" is the load-bearing half: a reader who went looking
      for a sort and came back holding a checklist did not ask for selection, which is why
      `library-browsing` words the allowance as *changes mode* rather than *is important*.
- [x] 2.4 Both: every standalone control names itself to assistive technology whatever it
      draws. Assert it for each.
      **Done on iOS by assertion, confirmed on Android by reading — no Kotlin changed.**
      iOS: `eachItemIsNamed` and `eachNameIsTranslated` run over a table of all four items —
      `library.select`, `library.view`, `library.filter`, `library.addSource` — and check each is
      looked up as a `Label { Text }` in the file that declares it *and* is translated into en,
      fr, de, es. The second half matters more than it looks: a `LocalizedStringKey` that matches
      nothing is not an error on this platform, it renders the key, so a control can be "named"
      and still announce `library.view` to a screen reader.
      Android's two standalone controls in the library's top bar are `AddSourceMenu`'s
      `IconButton` (`R.string.library_add_source`) and `LibraryOverflowMenu`'s (`R.string.
      library_more`), both carrying a `contentDescription` from a string resource; the rows inside
      each menu are `DropdownMenuItem`s with visible text, and their leading icons are correctly
      `contentDescription = null`. This tick covers the top bar only — the chip row under it is
      §3.1's and another pass's.
- [x] 2.5 Android: no change to the library's own controls — it already uses menus for these
      choices. Confirm that by reading it, and say so in the tick rather than silently
      skipping the platform.
      **Confirmed by reading. No Android control changed.** iOS's six `.primaryAction` items,
      each matched to what Android already does:
      1. **sort** — `LibraryControls.kt:92` → `:144` `SortChip`: a chip carrying the current
         ordering, opening a `DropdownMenu` at `:161` with a radio per field and the two
         directions under a divider. A named menu.
      2. **filter** — `LibraryControls.kt:93` → `LibraryFilterMenu.kt:73`, whose chip at `:91`
         reads *Filter* at rest and the active count as a plural once one is set, opening a
         menu that shows one group at a time. A named menu.
      3. **add** — `LibraryTopBar.kt:83` → `AddSourceMenu.kt:45`: one `+`, five kinds of source
         behind it. A named menu.
      4. **scope** — `LibraryControls.kt:91` → `:118` `AvailabilityChip`. **Not a menu, and
         deliberately not one**: the axis has two values of which the wide one is the library's
         normal state, so it is a single chip reading *On this device* that is selected or not.
         The reasoning is recorded at `:106–116`, and `library-browsing` asks for this axis
         "reachable without opening the filter sheet" and "visible while it is active" — a
         chip is both, where a menu would satisfy neither.
      5. **show** — `LibraryControls.kt:102` → `:193` `LayoutToggle`. Also not a menu: one
         `IconButton` drawing the layout it would switch *to*, with a `contentDescription` at
         `:201` naming that layout. A binary with no third value has nothing for a menu to
         present.
      6. **select** — `LibraryTopBar.kt:126`, an item **inside** the overflow menu, and this is
         where Android diverges from §2.3. On iOS select stays out of the menus because a mode
         switch among sort and filter choices is how a reader lands in selection without asking.
         Android's `⋮` is not that menu: it holds *Select*, *Collections* and *Settings* — three
         occasional acts, none of which is a choice about how the shelf is drawn — so the
         confusion §2.3 prevents cannot arise from it. The requirement permits either ("**may**
         stand on its own"), so this is a divergence within the spec rather than against it.
      **And Android already made this correction, earlier and for a measured reason.**
      `LibraryTopBar.kt:30–41` records what it replaced: a bar with **eight** action icons, in
      which "Library" was squeezed into a column one letter wide at 411 dp and vanished at
      320 dp with the last control pushed off the screen. So this is not a platform that
      happened to use menus; it is a platform that hit the same defect two icons worse than
      iOS's six and answered it with a flexible bar plus one overflow, moving the four
      frequently-touched controls out under the bar into `LibraryControls`.
      **§2.4's assertive-technology clause holds on the Android side already.** Three
      standalone controls remain and every one names itself: `AddSourceMenu.kt:51`
      (`library_add_source`), `LibraryTopBar.kt:120` (`library_more`), and
      `LibraryControls.kt:201` (`library_layout_grid` / `library_layout_list`, whichever it
      would switch to).
      **Where the reading corrects the task's own framing**: "it already uses menus for these
      choices" is true of three of the six, not all six. Two of the remaining three are
      *deliberately* not menus and say why in the source, and the sixth sits in a menu that iOS
      keeps its equivalent out of. Recorded rather than smoothed over, because "Android already
      does this" is the kind of sentence that later reads as "so nobody needs to look".
- [x] 2.6 iOS: captures before and after, at default and largest text size.
      **Done, and in both appearances rather than one** —
      `docs/designs/screenshots/quieter-toolbar-2026-09-02/`, eight pictures with a README.
      Dark as well as light because this toolbar sits on Liquid Glass, and a capsule
      photographed only on paper says nothing about what it does over a dark canvas. The dark
      pair is also what `--appearance` made possible: it landed today, and neither
      `testCaptureLibrary` nor `testCaptureLibraryAtLargestText` had ever had a dark twin —
      `docs/designs/ui-revamp-2026-08.md` §7.5 states the requirement as "light and dark, at
      default and largest text size", and for this screen only half of it had been met. Both
      halves are taken now.
      **§7.5 also counted the toolbar independently, and got six.** Its 2026-08-30 slice-zero
      capture reports "six unlabelled icon buttons … in a floating pill at the top of the
      phone, and seven on the iPad", which is the same number `LibraryToolbarTests` measured
      and a second reason the review's five was an undercount. That document's own bullet is
      now stale and belongs to §4.1.
      The *before* was photographed on the pre-change sources restored over the tree with
      `git checkout f30478bf -- Sources/LibraryFeature/`, then put back — the same route
      §1.10 used.
      **The largest-text pair answers a question rather than ticking a box.** Android's chip
      row overflowed at `font_scale 2.0`; iOS draws these as toolbar icons and an icon does not
      grow with the reader's text, so each row is the same width at both sizes and neither the
      six-glyph row nor the four-item one overflows. The improvement at the largest size is the
      same as at the default — two fewer glyphs to tell apart — and there was never an overflow
      to fix. Said plainly rather than left implied by four files.
      **Every run's case count was checked.** Each of the eight was a single
      `-only-testing:ScreenshotTests/<test>` run that reported one screenshot attached;
      `xcodebuild` exits 0 on a filter matching nothing, and the capture script's "attached
      nothing" line is the only tell.

## 3. Two smaller ones

- [x] 3.1 Android: the sort chip says it is an ordering. `library_sort_title` is "Title" and
      the chip shows it alone, which beside a "Filter" chip reads as a filter value. Same for
      grouping, which is neither a sort nor a filter. Four languages.
      **Done, and photographed.** The chip reads `Sort: Title`. One new format string —
      `library_sort_chip` — in all four `values*` directories: `Sort: %1$s`,
      `Sortierung: %1$s`, `Tri : %1$s`, `Orden: %1$s`. French takes the space before the colon
      that the rest of that file already uses (`kavita_status`). German, French and Spanish
      take the **noun**, not the imperative `library_sort` sitting above them — the chip names
      an ordering already in force rather than asking for one, so *Sortieren* would have been
      the wrong word in the right place.
      **A frame around the existing names, not seven new sentences.** `sortChipLabel` in
      `LibraryControls.kt` composes the frame with `LibrarySort.labelRes`, so the seven field
      names stay the words the menu uses. Respelling them as *Sorted by size on this device*
      would have put a second wording of one fact in a four-language app — the drift
      `searchScopeLabel` exists to avoid — and would have broken German and Spanish
      capitalisation, where those names are nouns that keep their capital. A colon takes a
      capital in its stride in all four.
      **Both rows that show a sort, not just the one the review photographed.** The shelf's
      `SortChip` and `ShelfDetailScreen`'s `ListOrderChips` draw the same seven names, and the
      requirement says "the current sort **on a control**" rather than naming a screen. The
      curated order is deliberately left bare: *The list's order* already reads as an ordering,
      and `Sort: The list's order` would assert a sort over the one list whose defining
      property is that nothing sorted it. `ListOrder.chipLabel` holds that asymmetry and
      `SortChipNamesAnOrderingTest` pins it.
      **Grouping has no Android control to rename, and that is a finding rather than a skip.**
      The requirement's second clause — "the same holds for grouping, which is neither" —
      assumes a grouping control. Android has none: `LibraryScreen.kt:673` calls
      `LibrarySections.divide(publications, query.sort, other)`, so the shelf's headings are
      **derived from the sort** and are contiguous runs of the arranged list, never a
      regrouping of it (`LibrarySections.kt`, which says so at length and gives the reason — a
      grouping that gathered every "A" out of a shelf sorted by last-read would silently undo
      the sort). So on Android the clause is satisfied by the sort chip it follows from, and
      inventing a grouping control to have something to label would be building an unspecified
      behaviour.
      **iOS's half, answered 2026-09-04 rather than left open**: iOS shows no current-sort
      value on any control, so the scenario's `WHEN` never fires there. `ViewMenu`'s toolbar
      label is `library.view` ("View") with the availability glyph; the sort lives *inside* the
      menu as a `Picker` labelled `library.sort`, with direction as a picker of its own. There
      is no iOS grouping control either, exactly as on Android, where the headings are derived
      from the sort. Vacuously compliant, which is worth writing down: an archived record that
      leaves this as an open question reads as unfinished work rather than as a platform that
      never draws the value.
      **Asserted, and the assertion was made to fail twice.** `SortChipNamesAnOrderingTest`
      checks two properties over all seven fields in all four locales — the label is not the
      bare field name, and the field name is still inside it. Neither alone is enough: the
      first passes for a label of pure decoration, the second for the bare name this replaced.
      Mutating `library_sort_chip` to `%1$s` fails the first; mutating it to `Sort` fails the
      second. A fifth test holds the curated order bare.
      **The row still wraps at the largest text size**, which is the half of this that could
      have gone wrong — this row scrolled sideways once and put *Filter* half out of the
      window. `ListOrderChipsWrapTest` measures the composed label now rather than the bare
      one, in all four locales at 320 dp and `font_scale 2.0`; measuring the bare name would
      have reported a width no reader ever sees. On the emulator at `font_scale 2.0` the row
      takes two lines with nothing clipped.
      **Photographed** before and after, light and dark, default and largest —
      `docs/designs/screenshots/sort-chip-2026-09-01/`, eight files with the conditions in
      their names. Its README records how the build in them was verified, because this
      emulator is shared and an install on it can report `Success` and then be discarded.
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

## 3b. The selection chrome, which had no requirement at all

Added on 2026-09-02, after the owner reported it twice. **This section exists because the
behaviour shipped before anything specified it** — `collections-and-reading-lists` says a reader
may select in bulk and `native-experience` asks for the platform's conventions in general terms,
and neither reaches the *shape*. A `native-experience` delta now states it; see
`specs/native-experience/spec.md`.

- [x] 3b.1 iOS: the selection's actions **replace** the tab bar rather than stacking above it.
      `LibraryView` hides the tab bar for the mode's duration, and the actions are a
      `Capsule()` on glass inset by the gutter, inside a `GlassEffectContainer` with the undo
      capsule so their edges morph. `.controlSize(.large)`, the scale floating chrome uses here.
      **This is the line that fixes "two bars"**, and it is mutation-checked: commenting it out
      fails `BulkSelectionChromeTests` by name.
      The guard's first version was too loose and the agent caught it — a 160-character lookback
      reached the `navigationBarTitleDisplayMode` line above and would have lent the test the
      word it was searching for. Scoped to the enclosing `.toolbar(` statement instead.
- [x] 3b.2 iOS: the count moves to the navigation title and *Select* is **replaced** by *Done*
      in the trailing toolbar slot. The three view choices stand down for the mode, so changing
      what the shelf shows cannot carry picks off screen.
- [x] 3b.3 Android: a contextual `TopAppBar` — close at the start, the plural count as title,
      download and mark-as-read as actions, *Add to…* named in words in the overflow.
      `BulkActionBar.kt` is deleted and the screen's `bottomBar` no longer has a selection
      branch. **Android never puts selection chrome at the bottom**: that is the navigation
      bar's territory, and `native-experience` asks for the platform's own convention. An
      ADR-0001 divergence by design, recorded in both platforms' doc comments.
- [x] 3b.4 Both: the actions are inert at nought picked and **shown rather than hidden**.
      Chrome that arrives on the first pick appears under a thumb mid-tap and changes the
      shelf's bottom inset mid-scroll; shown-and-inert says what the mode is for. The way out is
      never in the disabled group.
- [x] 3b.5 Both: every action names itself to assistive technology. Glyph-only survives for
      **two of the mode's actions**, both on Android's top bar where an action slot holds no
      word at any width, and both glyphs the platform already establishes. (This said "exactly
      two places", which undercounts the bar itself: `LibrarySelectionTopBar` draws four
      glyph-only controls once the exit and the overflow are counted. All four carry a
      `contentDescription` from a string resource and all four are platform-established
      symbols, so the requirement holds — it is the count that was loose.) *Add to…* is named in words,
      because `PlaylistAdd` is the ambiguous glyph the review objected to.
- [x] 3b.6 **A second instance of the same slab, which the brief did not name.**
      `ShelfBulkActions` drew the identical full-bleed `BulkUndoBar` one screen over. Floated as
      an inset capsule in the same pass. The complaint had two homes and only one was reported.
- [~] 3b.7 Captures. **The iOS half is taken; the Android half is not.**
      iOS, done: ten frames in `docs/designs/screenshots/ios-selection-chrome-2026-09-04/`,
      on `StoryArc-iPhone17Pro` — the shelf selecting at **0** and at **2** picked, at the
      default text size and at `UICTContentSizeCategoryAccessibilityXXXL`, **light and dark**,
      plus the end-of-scroll pair. Five walks, each run reporting `1 passed, 0 skipped`.
      Two walks are new (`…SelectingEmpty`, `…SelectingEmptyAtLargestText`) and the three
      that existed were hardened, because **none of them could say it had photographed the
      right screen**: they launched with `launch()`, which pins no appearance — so the app's
      stored `oledDark` could outrank `--appearance light`, the failure
      `SweepLibraryTests.testCaptureCoverGrid` already records — they picked `shelf.buttons`
      by index, which is what `realCovers(in:)` exists to replace, and nothing read the count
      back, so a walk that picked nothing still passed. All five now use `sweepLaunch` and
      assert `N selected`, *Done* and all three action names before the shutter.
      They stay in a sibling extension on `ScreenshotTests`: that file sits at SwiftLint's
      400-line file warning (396 after this) and the sweep README invokes the walks by the
      class-qualified name.
      **The question is settled, and the ancestor wins.** The capsule's glyphs measure
      `#000000` on light and `#f4f4f4` on dark, saturation **0.000** in both; *Done*, in the
      same navigation bar at the same moment, is `#8a4df0` at saturation **0.679**. So
      `.storyArcGlassText(.primary)` beats the button style's tint, and it reads correctly —
      the accent is left marking only what is picked and the way out, which would have been
      flattened by three violet glyphs beside a violet *Done*.
      **Two things the pictures settled that nobody asked, neither fixed here** — this was a
      capture job, and each is a behaviour change wanting its own task:
      (a) the `ViewThatFits` fallback is **already taken at the default text size** on a
      402 pt iPhone, so the named row is never drawn on this phone and the surface shows
      three bare glyphs — which §3b.5 and `BulkActionBar`'s own doc comment both say happens
      only at the accessibility sizes. `BulkSelectionChromeTests` greps the source for
      `.titleAndIcon` and so proves the fallback is *declared*, not which branch is taken;
      (b) the inert capsule is **pixel-identical** to the live one — 0 of 27 900 pixels
      differ, against 45 % over a cover's tick in the same pair — so §3b.4's inertness is
      invisible. Likely the explicit `foregroundStyle` defeating the disabled dimming; stated
      as an inference, not a measurement.
      Android, still owed: the contextual bar at 0 and at many, light and dark, default and
      largest text — no walk exists yet. **This section stays `[~]` until it does.**
      Also named and not reached, with reasons, in that folder's README: the undo capsule and
      §3b.6's `ShelfBulkActions` (both need a persisted write or a collection the corpus does
      not build), the *Add to…* menu open, Reduce Transparency and Increased Contrast (the
      other branch of `GlassText`, with no launch-argument lever), and iPad.

## 4. Close-out

- [x] 4.1 `docs/openspec/STATUS.md`, and `docs/designs/ui-revamp-2026-08.md` if it describes
      the toolbar or the notice.
      **Three downstream artifacts were stale, and a verification pass named each.**

      - **`STATUS.md` had a heading for this change and no section.** It now has one: §1's
        state-not-event decision and the four scenarios that fall out of it, §2's six-to-four
        toolbar, §3's sort chip, and §3b's two deliberately divergent selection chromes. Its
        "last updated" moved from 2026-09-01 to 2026-09-04.
      - **`ui-revamp-2026-08.md` still stated the six unlabelled toolbar buttons as a live
        defect**, three days after §2 folded them into two controls and two named menus. Marked
        *Settled*, following the convention its neighbour established. That bullet is also one
        of the two independent places the **six** was counted — the review of the same screen
        said five, which was an undercount — so it is worth keeping rather than deleting.
      - **`android-sweep-2026-09-02/README.md` labelled its seven selection frames
        "Current"** while photographing the full-bleed bottom slab §3b deleted. They are the
        *before* now, and they say so.

      One more, not owed by this task and taken while the file was open:
      `quieter-toolbar-2026-09-02/README.md` now records that its "after" frames show the View
      menu's superseded two-state glyph, and points at the folder that photographs what
      shipped.
- [ ] 4.2 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 4.3 `pnpm spec:guard:strict`.
- [ ] 4.4 `/opsx:verify named-failures-and-quieter-chrome`, then `/opsx:sync`.
