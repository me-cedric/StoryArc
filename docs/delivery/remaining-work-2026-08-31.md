# What is left, and what a device or a server would settle

**Date:** 2026-08-31. **Method:** three independent audits read the whole of
[`STATUS.md`](../openspec/STATUS.md) and every open task in `docs/openspec/changes/`
against the app source on both platforms, with `path:line` evidence. Written because the
change task lists had drifted so far from the code that they were misleading in both
directions — work marked open that had shipped, and whole screens marked shipped that no
reader could reach.

This document is the work list. It is not a plan for one session; it is what is honestly
outstanding, ordered so that whoever picks it up next starts with the item that matters
most rather than the item that is easiest to find.

---

## 0. First, the two things that had gone wrong with the documents themselves

**The task lists lied by omission.** `one-library-three-destinations` showed 1 of 25 tasks
done and `publication-detail` showed 0 of 23, while the three-destination shell, Home, the
Downloads destination, the availability axis, the empty states and the entire publication
page were all built. A reader of those files would have concluded the revamp had barely
started. The lists are being corrected as each slice lands; the correction is part of the
slice, not a tidy-up afterwards.

**`STATUS.md`'s own arithmetic does not reconcile.** Its header table claims 21
`one platform only` and says "every one of them is named in its own row above". Summing the
per-capability rows gives 17. The rows also sum to 142 `built and tested` against a header
of 137, and 90 `built, asserted by nothing` against 89 — 271 verdicts against a stated 269.
Only `missing` reconciles exactly, at 21. Six scenarios carrying a verdict are never bound
to a scenario title at all: `ebook-reader`'s two `missing`, `reading-progress`'s one
`one-platform`, `native-experience`'s two, and `sources`' two.

Four of the twenty-one `one platform only` slots are also not gaps: the
`local-library` spec splits *Adding a folder* and *Remembering an opened file* per platform
by construction, so each consumes a slot while being complete on both sides.

The document warns on its own second page that "a status document that lags is worse than
none, because it is believed". That applies to its totals too. **Recount it, name the six
unnamed scenarios, and separate the four by-construction splits from the real gaps** — this
is a small job and it is the one that makes every other number in this document trustworthy.

---

## 0b. What has closed since this was written, the same day

Kept as an addendum rather than by editing the sections below, so the audit still reads as
what was found rather than as what survived.

| Closed | Where it was |
| --- | --- |
| **The publication page is reachable** on both platforms. Every cover leads to it; every resume affordance still opens the book. Three browse screens deliberately keep opening the reader, and the reason is recorded in the change's task 2.3. | §1 |
| **Android's shelf caught up with iOS's** — the on-device mark, dimming for what cannot be read now, and section headings by series. The per-source chip strip and the superseded empty state are gone. | §2 |
| **The interface language reaches the EPUB reader.** Both of the app's two activities now use one mechanism. | §3.2 |
| **Material You can be turned off**, with the switch disabled and explained under OLED Dark, where true black already wins over the wallpaper. | §3.3 |
| **The iOS accessibility audit runs at all.** Its target had never built — no `Info.plist`, no generation flag — so `xcodebuild test` failed before a single test started. It reported nineteen issues on first run; Downloads is down from seven to one, and the nine contrast findings are each judged in the test's own expectations. | §5 |
| **The device tooling finds its own tools.** `scripts/adb.mjs` resolves `adb`; `scripts/gradle.mjs` resolves JDK 21, the SDK, and writes the `local.properties` a fresh worktree lacks. Before this, two of the three device scripts could not run on this machine at all and Gradle could not start in a worktree. | §5 |
| **`pnpm smoke:android` walks 16 of 16 routes**, up from 1 of 13, with no crashes. It had been describing the pre-revamp shell, and reading uiautomator's null dumps as "element absent". | §5 |

### A second round, later the same day

| Closed | Where it was |
| --- | --- |
| **Renaming or moving a file no longer loses the reader's place** — `contentDigest` existed on both platforms and nothing called it. It also found that Android's instrumented `ProgressStoreTest` had not compiled since a commit months back: nineteen positional call sites binding the wrong parameter, so nothing it appears to cover had run. | §3.1 |
| **A device that is ahead now tells the server.** `ProgressPull.toPush` was computed and discarded. Proven against the in-repo Kavita mock, which gained a 13-check self-test wired into `pnpm lint`. The same slice closed a **secret leak**: `KavitaAddress` printed the reader's API key in its default description on both platforms. | §3.6 |
| **Local and server search results are one ranked list, each row saying where it came from.** Four cross-platform sort divergences were found by measuring and pinned by mirrored tests — scalar against UTF-16 ordering, two different ideas of whitespace, and a case fold Kotlin cannot perform. | §3.12 |
| **The "Downloaded" filter**, and a reading list that can be sorted and returned to its curated order. | §3.4, §3.11 |
| **Natural** as a theme and a live preview in the theme sheet — **two** of the four items blocking that change's `/opsx:sync`, not three. Three *tasks* landed; 5.2 and 5.4 are one blocker between them, and a fourth item (a double-page spread curling as one surface) has no task number at all, which is why it keeps vanishing from the count. **The grain does not draw** — see the correction in `after-2026-08-31/README.md`. | reader-theming remainder |
| **The 800-line cap is counted.** Nothing had ever measured it, which is how five Kotlin files got past it. A ratchet: each is recorded at its length, may shrink, may not grow. | §3, last row |
| **iOS walks thirteen routes** — three destinations, the publication page, the reader, Settings and its seven groups — against Android's sixteen. That asymmetry is named in STATUS and said to be not deliberate. | §5 |
| **A test that proves a publication comes back where it was left**, across a real terminate and relaunch. `reading-progress` scores nine of seventeen scenarios as built and asserted by nothing. | §5 |
| **A fixed-layout EPUB that could never be opened.** The routing was right and the fixture was wrong, so that path had never been exercised against anything it could draw. | not previously recorded |

**And two questions answered by a device rather than by reading**, both now recorded in
[`ui-revamp-2026-08.md`](../designs/ui-revamp-2026-08.md): `Tab(role: .search)` morphs into
a field in place, so the documented fallback should not be built; and the OPDS stack works
end to end against `pnpm opds` — the app connects, names the catalogue, and issues
`GET /opds/all?q=…`. What is *not* wired is the merge, which is exactly what §3.12 says.

---

## 0c. Thirteen defects a task-list reconciliation found on the way past

Found while re-deciding all 48 tasks of `one-library-three-destinations` and
`publication-detail` against the source. None was in that agent's remit to fix; all are
recorded with evidence so nobody has to find them twice. Roughly in order of what a reader
would notice.

| # | Defect | Where |
| --- | --- | --- |
| 1 | **iOS: *Clear filters* cannot clear the by-library narrowing.** `ScopeMenu` writes `query.scope`; `activeFilterCount` excludes it and `withoutFilters()` leaves it — so a reader can be left looking at one source's shelf with nothing offering to undo it. `library-browsing` forbids that in as many words: "there is no state a reader can be left in without noticing". Android has the right shape. | `ScopeMenu.swift:127-144`, `LibraryQuery.swift:126-136,155-166` |
| 2 | **iOS: dimming reaches only the sectioned shelf.** Its sole call site is gated on a grid of more than twelve items, so a short library shows unreachable publications undimmed, and `CoverList` has neither the dim nor the on-device mark. The fact also rides an `accessibilityHint` rather than the label. Android is complete on both layouts. | `SectionedShelf.swift:97`, `CoverList.swift` |
| 3 | **Android: a remote publication that is not downloaded can never have a cover**, so its page is permanently washless — both cover pipelines bottom out on a location written only when bytes are on the device. | both platforms' cover pipelines |
| 4 | **Android: `detail_action_refused` is unreachable.** It is produced only inside `if (press != null)`, and `press` is null exactly when the action is `REFUSED`. Four locales carry a string nothing can render. | `PublicationDetailScreen.kt` |
| 5 | **Android: a `NEEDS_DOWNLOAD` publication shows two controls for one action** — the primary and an overflow item. iOS forbids it by construction. | `PublicationDetailScreen.kt:339,408-416` |
| 6 | **Android: the detail pane draws an unconditional back arrow** with the list permanently beside it. Material's own `ListDetailPaneScaffold` hides it when both panes are visible; this pane is hand-composed. | `PublicationDetailScreen.kt:153-159` |
| 7 | **`PredictiveBackHost` has zero call sites.** Nothing in the app animates a predictive back, which is why `publication-detail` task 4.2 cannot close. | `PredictiveBack.kt:105` |
| 8 | **iOS's cover wash arrives as a hard cut** — no animation anywhere in the `Detail*.swift` files, where Android crossfades. That is the visible flash task 0.1 forbids. | `Detail*.swift` |
| 9 | **Provenance diverges on the same file.** A comic in a picked folder reads *"On this device"* on Android and *"From ‹folder›"* on iOS. Same reader, same file, two sentences. | both platforms' provenance |
| 10 | **Android: neither the availability scope nor the download facet survives a cold start**, where iOS persists both. Closing it needs `core/persistence`. | `LibraryScreen.kt:188,198` |
| 11 | **Experimental Material 3 opt-ins have spread to four modules** while the file that centralises them still claims to be "the one place". An alpha bump is now a four-module fix. | `Panes.kt:17` |
| 12 | **iOS: `OnDeviceEmpty` is unreachable** since the Downloads destination replaced the on-device library surface, and the space total can read "Zero KB" under a full shelf. | `LibraryContent.swift:132-137` |
| 13 | **Nothing counts a line.** `pnpm lint` runs ten checks and none is a line-count gate, which is how five Kotlin files got over the 800-line cap without anyone noticing. The largest is **`ReaderScreen.kt` at 1893**, not `LibraryViewModel.kt` as earlier notes claimed. Swift is clean by exactly one line: its largest file is 400. | `package.json` |

**~~A spec amendment is owed before `/opsx:sync`.~~ Written.** The `reading-progress` delta
now exists in `publication-detail/specs/`, and the change declares it. Two further clauses
in the `one-library-three-destinations` delta — that no result is labelled with its source,
and that arrivals never displace — were **withdrawn**, with the reasoning recorded in that
change's own `design.md` rather than in a commit message, because `/opsx:sync` erases the
delta and would take the reasoning with it. A fourth contradiction turned up while doing it:
`publication-detail`'s own delta listed search among the surfaces that state origin, so two
unarchived deltas were about to sync into a contradiction with each other.

---

## 1. The single largest gap: a whole screen nobody can reach

The publication page — hero, cover-derived wash, title block, primary action, overflow,
description, series shelf, provenance line — is **built, translated and screenshotted on
both platforms, and reachable from no cover on either.**

- **iOS: the page is dead code.** `publicationDetail(model:onOpen:onGone:)` at
  `PublicationRoute.swift:51` is the only registration of
  `navigationDestination(for: PublicationRoute.self)` and it has zero call sites. The only
  push of a `PublicationRoute` anywhere is `DetailSeriesShelf.swift:100` — inside the page
  itself. `PublicationDetailPlaceholder` and `goneSentence` are dead beside it.
- **Android: reachable only from itself.** `Screen.PublicationPage` is pushed only at
  `AppScreens.kt:227`, again the page's own series shelf.

Every browse surface on both platforms goes straight to the reader. This was deliberate
once — commit `82ad1d92` reads *"Reverts the wiring that made a cover open the page… The
destination modifier is ready and one line attaches it"* — reverted to avoid a same-wave
file conflict, and never re-attached.

The rule has two halves and both matter: a **cover** leads to the page; a **resume
affordance** still opens the reader, because a reader who tapped Continue has already
chosen.

---

## 2. Android's shelf is behind iOS's

`CoverGrid.kt:474` says so in its own comment. Three features shipped on iOS and exist on
Android only on Home, not on the library shelf:

| Missing on the Android shelf | On iOS at |
| --- | --- |
| The on-device mark, capped at two marks per cover with the pick mark substituting rather than joining | `CoverCell.swift` `OnDeviceMark` / `showsOnDeviceMark` |
| Dimming a publication that cannot be read now, with the fact in the accessibility label | `SectionedShelf.swift:99`, hint at `:102` |
| Section headings by series where declared and by sort key otherwise | `LibrarySections.swift`, 18 tests in `LibrarySectionTests.swift` |

iOS's dimming has an honest limit of its own: it reaches only `SectionedShelf`, so the
plain grid, the list layout and search results show unreachable items undimmed.

---

## 3. Ranked by what a reader would notice

Everything here is buildable today. Nothing in it waits on hardware.

| # | Gap | Why it ranks here |
| --- | --- | --- |
| 1 | **Content identity** — iOS `PublicationIndexer.contentDigest` is dead code; Android digests only a file opened from outside the app | Renaming or moving a file silently loses the reader's place. Data loss the reader cannot see coming. |
| 2 | **The interface language never reaches `EpubReaderActivity`** — no `attachBaseContext`, so 109 keys across 94 call sites stay in the system language | A reader who picks French gets an English reader. The STATUS row spells the fix: three lines, plus moving `speaking()` and `chosenLanguage()` into `:core:persistence`. |
| 3 | **Material You cannot be turned off on Android** — `useDynamicColor = true` is hardcoded at `MainActivity.kt:139` and `EpubReaderActivity.kt:305`; no setting, no `AppSettings` field | The spec has an opt-out clause. Today the only way back to the brand palette is to choose OLED Dark. |
| 4 | **The "Downloaded" filter** is absent from `LibraryFilterMenu` on both platforms | The one filter that matters on a plane or underground. Its stated blocker is gone: `DownloadStore` already knows which downloads finished. |
| 5 | **The same publication from two sources never merges** — `PublicationIdentity.ServerIdentifier` is never constructed in production on either platform | A folder copy and a Kavita copy of one book are two records. Read twice, counted twice. |
| 6 | **A device that is ahead never tells the server** — `ProgressPull.toPush` is computed and discarded (`KavitaSync.swift:65-66` and its Kotlin mirror) | The other device silently rereads. `pnpm kavita` can prove the fix. |
| 7 | **Nothing pauses the queue when the disk fills** — `Download.Pause.outOfSpace` and its string exist and are unreachable; nothing asks the device for free space | The queue will fill the disk. |
| 8 | **No metered-connection override** — `enqueue` queues unconditionally, with no per-item override, no confirmation and no size stated | Silent cellular spend on a 400 MB comic. |
| 9 | **Reading has to wait for the whole download** — `fetch` blocks on a continuation until the file lands, with no stream-to-local-copy hand-over | Today you wait for the last byte before the first page. |
| 10 | **"This source cannot store progress" is never said** | One string. Prevents a reader assuming a folder source syncs. |
| 11 | **A reading list cannot be sorted, or restored to its curated order**, and the curated order is unlabelled | |
| 12 | **Local and server search results are never merged** into one ranked list | Two places to look for one book. |
| 13 | **A Kavita reading list opens read-only** — no reorder, online or off | `scripts/kavita-server.mjs` already serves `/api/ReadingList/update-by-multiple`. |
| 14 | **Kavita's publication status and age rating** are decoded on Android, not on iOS, and displayed on neither | Parental-control adjacent. |
| 15 | **A theme does not follow a mid-book appearance flip** — `ThemePreset.matching` is a fixed map resolved once at reader construction | |
| 16 | **`PredictiveBackHost` is written and called nowhere** — all 11 in-app Android back destinations use a plain `BackHandler` | Pure wiring. |
| 17 | **The transport line (SMB 2/3, encryption) appears only in the add-share sheet**, never on the source's own detail screen | Answers "is this share encrypted?" where the reader looks. |
| 18 | **A failed download verification is never re-queued once**, on either platform | The spec asks for it. |
| 19 | **iOS's `AppSettings.turnPagesWithVolumeButtons`** is unit-tested and drives nothing | Deliberate divergence, dead setting. Delete it. |

### Streaming honesty — the two open tasks in `format-scope-and-libraries`

Task **5.2** (download instead of stream, with the size stated) is not implemented on
either platform, and its recorded blocker is now wrong. The capability is computed
correctly and consumed almost nowhere: `.downloadOnly` has a single producer
(`PublicationIndexer.swift:341`) and **zero** production readers on iOS; Android has one
branch (`DetailActions.kt:54`) whose sentence renders with **no button** to act on it,
because `onDownload` is `null` on that path (`AppScreens.kt:229`). The size is stated
nowhere before a single-publication download on either platform, and the shipped SMB
behaviour is the inverse of the requirement — `SmbBrowserView.swift:145-158` copies the
whole file silently with `entry.length` in hand and never shows it. Underneath all of it,
no remote source can produce `.downloadOnly` at all: `PublicationIndexer.swift:145-178`
hardcodes `streaming: .refused` for every remote CBR.

Task **5.3** (a downloaded solid archive opens with no notice) is **vacuously true**: no
solid-archive or streaming notice exists anywhere in either codebase to suppress, and no
test asserts its absence. The solid-RAR4 refusal itself is correctly implemented on both.

### The reader-theming remainder

Four tasks are open and they block `/opsx:sync` (task 7.7): **3.6** live preview rendered
by the real renderer, **4.3b** the second raster that would let Curl work over reflowable
text, **5.2** Natural as a selectable theme, and **5.4** its paper grain. The Natural
palettes are generated and consumed by nothing (`StoryArcTokens.swift:93,117`); grain does
not exist in any form on either platform, in code or prototype. Fonts (Phase 6) shipped
completely — five families, registered with Readium *and* each platform's native text
stack.

### The 800-line cap

Five Kotlin files are over it: `feature/reader/ReaderScreen.kt` 1888,
`feature/library/LibraryViewModel.kt` 1681, `feature/epubreader/EpubReaderActivity.kt` 986,
`ThemeSheet.kt` 911, `ReaderViewModel.kt` 811. Task 6.3 of
`one-library-three-destinations` names the gate. The two files that task originally called
out are fixed: `MainActivity.kt` is 170 lines and `LibraryScreen.kt` is 641.

---

## 4. What genuinely needs hardware

Short, and worth keeping short — everything else on this page can be built and proven
without leaving the desk.

| Item | Why a simulator or emulator will not do |
| --- | --- |
| **iOS Curl, judged** | The simulator accepts no injected finger-tracked input; `apps/ios/README.md` records the attempts. The code ships on both platforms. |
| **Read-aloud through a real interruption** | A simulated interruption is not a phone ringing. The state machine is tested on both platforms and passes on the simulator; the audio session under a real call is not. |
| **Local-network permission denied (iOS)** | The iOS Simulator has no Local Network privacy gate to deny. The detection and the sentence can both be built and unit-tested first. |
| **Widgets (iOS)** | Deferred by ADR-0011, and blocked on an Apple signing team for the App Group entitlement — not on hardware. A simulator runs widgets. The Android half is buildable now. |
| **Metered-connection override, end to end** | The flow, the confirmation and the stated size are all buildable and testable; only "this is really a cellular link" wants a device. |

**Everything server-shaped is covered in-repo.** `pnpm opds` (port 4444), `pnpm kavita`
(port 5000, and note macOS AirPlay Receiver often holds 5000 — pass `--port`), and
`pnpm smb` serve the fixture corpus, with `--encrypted` on the SMB script for the
refuse-an-encrypted-server case. Nothing in §3 is blocked for want of a server.

---

## 5. Where the verification tooling stands

`pnpm smoke:android` walks every route and asks logcat whether the process died;
`pnpm a11y:android` reads the real accessibility tree at real density; `pnpm pseudo:android`
walks nine routes under `en-XA`. All three now resolve `adb` through `scripts/adb.mjs`, and
the Android gates resolve their own JDK and SDK through `scripts/gradle.mjs` — before that,
two of the three device scripts could not find `adb` on a Homebrew-only machine and Gradle
could not start in a fresh worktree.

iOS has one simulator-bound UI test, scoped to the library and currently
`XCTExpectFailure`d. `STATUS.md` names this divergence and says explicitly that it is
**not** deliberate: it is where the tooling happened to get built. Closing it means an iOS
route walk and an iOS pseudo-locale pass, plus the light/dark × default/largest capture
matrix that Android already has for eight settings screens and iOS has for three.
