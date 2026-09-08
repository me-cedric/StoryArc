# What is left before StoryArc is a working MVP

Written 2026-09-07. Everything a machine can check here is green: `pnpm lint` exits 0,
the iOS suite runs 2228 tests, `swiftlint --strict` reports 0 violations in 739 files,
and all four GitHub workflows pass.

This page lists the work that a machine here cannot do. Each item says what it needs,
what question it answers, and how you know the answer is real.

Read [`openspec/STATUS.md`](openspec/STATUS.md) for the per-capability detail. This page
does not repeat it.

## The one number that matters

**Nobody has watched StoryArc work.** 227 scenarios are built and tested on both
platforms. 119 more are built and no test asserts them. Not one of the 367 has been
driven on a device by a person or by an automated walk. A unit test proves a function
returns a value. It does not prove a reader can open a book.

That is the MVP gap. It is not a code gap.

## A. No device and no server needed

These run on this Mac. A simulator or an emulator is enough. They are listed first
because they are the cheapest and they block the rest.

1. **Run the two accessibility audits.** They fail in CI four times and have never run
   here. The first local attempt hung for more than one hour and was killed. The cause was
   simulator contention, and `-collect-test-diagnostics never` now stops a 600-second
   sysdiagnose after each failure. Run one audit at a time. Give it a simulator that
   nothing else holds.
2. **Repair the iOS EPUB reader audit.** It reported zero findings and had measured the
   publication page. The element it tapped was not hittable. It now proves it arrived and
   skips instead, so the iOS EPUB reader is unaudited. Give it a hittable path to the
   reader.
3. **Take the owed screen captures.** Several task lines carry `[~]` because a frame is
   owed, not because code is missing. `pnpm partial:tasks` names them:
   `reader-theming-and-page-transitions` owes 6 and `source-lifecycle` owes 3.
4. **Assert the 119 untested scenarios.** Each one has code on both platforms and no test
   on at least one side. Revert the production line and confirm the new test fails by
   name. A test that cannot fail is worse than no test, and this repo has shipped three.
5. **Build the 6 scenarios that no platform implements.** *Frame budget* is one of them.
   Its instrument now exists on both platforms, so the scenario needs a measurement and a
   threshold, not new machinery.

## A2. The twelve player tests, which have never passed

`PlayerAuditTests` and `PlayerScreenshotTests` fail twelve cases on every CI run, all at
`AudiobookWalk.swift:36`, with **"No audiobook on this device's shelf"**. That instruction
lives only inside the assertion, and nothing has ever carried it out.

Seeding a download does not answer it. Measured on 2026-09-07:

1. `scripts/seed-simulator.mjs` seeds a comic, and the Downloads screen draws it. The
   mechanism works.
2. An audiobook cannot be a download record. `PublicationFormat.init(mediaType:)` maps no
   audio type, and `PublicationFormat.mediaType` answers nil for `.audiobook`, so an
   audiobook never round-trips through `DownloadStore`.
3. `AudiobookWalk` looks on the **Library** tab. A download is drawn on the **Downloads**
   tab, so even a working record would be looked for in the wrong place.

Three ways out. The choice is yours, because each changes production code for a test.

| Option | Cost |
| --- | --- |
| Give `.audiobook` a media type, so an audiobook can be a download | Smallest. Also closes a real gap: an audiobook fetched from a catalogue cannot be classified today. |
| Add a launch argument that seeds the local library | A test-only hook in the app. |
| Bundle an audiobook fixture in the app and import it behind a flag | Ships a fixture in the product. |

Whichever is chosen, `test:ios:ui` needs the order build, install, seed, then
`test-without-building`: a seed must land after the install and before the run.

## B. An iOS device

A simulator answers none of these. Each one depends on hardware the simulator models
incorrectly or not at all.

1. **A background transfer while the app is suspended.** The simulator does not suspend an
   app the way iOS does, and it does not wake one for a completed transfer. Start a
   download, leave the app, lock the phone, and return after the transfer window.
2. **The cellular branch.** The simulator always reports Wi-Fi, so the "hold this download
   until Wi-Fi" rule has never taken its own branch. Turn Wi-Fi off. Confirm the queue
   holds. Turn Wi-Fi on. Confirm the queue resumes.
3. **A frame rate under a real GPU.** A simulator frame rate measures the Mac, not the
   phone. Measure on the oldest supported device, not the newest.
4. **Reading in sunlight and at night.** The reader's themes and its brightness rule are
   judged by an eye, not by an assertion.
5. **The share sheet and the file importers.** They open a system process. Confirm a real
   CBZ and a real EPUB arrive from Files, from Mail, and from another app.

## C. An Android device or tablet

1. **The 840 dp cover tier and the two-pane layout.** Both were decided without hardware.
   A 10-inch tablet in landscape is the case that decides whether the tier is right.
2. **Volume-button page turns.** This is Android-only and deliberate. It needs a real
   volume rocker. A key event injected by a test is not the same event.
3. **The content observer that watches a picked folder.** Add a file to the folder from
   another app. Confirm the library notices. Neither platform's watcher has been seen
   working.
4. **A manual library refresh.** Android has one and iOS has none. Confirm the Android
   control does what its label promises.
5. **The unnamed WebView on the publication page.** TalkBack reads it. Confirm what it
   says.

## D. The Kavita server

`pnpm live:check` reaches the server and mints a token. It reads. It has never written.

1. **Add the server end to end.** `connect()` asked `Server/server-info`, a route that has
   never existed in any shipped Kavita, so adding a server always failed. The version gate
   was deleted on 2026-09-07 and the path has not run against a live server since. This is
   the first check to run.
2. **Reorder a reading list.** `update-by-multiple` appends rather than reorders, so the
   client sends `update-position` instead. No live server has answered it.
3. **Write to a server collection.** The client's write shape is derived from the published
   specification and has never been accepted or refused by a server.
4. **Unmark a chapter.** `/api/Reader/mark-chapter-unread` is absent from all five published
   specifications, so the write is dead against every Kavita. The nearest route is
   `mark-multiple-unread`, and its body is a different shape. Measure the real answer before
   changing the caller.
5. **Mark a chapter read on an older server.** `/api/Reader/mark-chapter-read` is absent
   before v0.9.0. Confirm what v0.8.x answers, then decide whether the app supports it.

Also worth asking the live server: what a permission refusal looks like for a reader who
cannot write, and what a real progress conflict looks like when two clients read the same
chapter.

## E. The SMB server

1. **A share that truly requires encryption.** `STORYARC_SMB_REQUIRES_ENCRYPTION` was set
   to 1 on 2026-09-06 and the share accepted an unencrypted connection anyway. Reconfigure
   the share to refuse one. The app's encryption notice has never been triggered by a
   server.
2. **A bare LAN hostname.** A TrueNAS answered to `<name>.local` and not to `<name>`, and
   the server replied `NT_STATUS_NOT_FOUND`. The app reports that status as a missing
   share. A reader who mistypes a hostname is told the wrong thing.
3. **A dropped connection mid-read.** Unplug the network cable while a page is loading.
   The reader shows a notice at 2 seconds and another at 60. Confirm both, and confirm the
   read resumes.
4. **A share with 10000 files.** Every scan has run against a fixture. Confirm the scan
   finishes and the list stays responsive.
5. **A file the reader cannot open.** Point the app at a directory it lacks permission to
   read. Confirm the message names the cause.

## F. Blocked, and not by a test

**Widgets need an Apple Developer signing team.** The App Group that a widget reads cannot
be provisioned without one. See [ADR-0011](decisions/0011-home-screen-widgets.md). No code
change removes this.

**CarPlay needs the same team, for the same reason.** Apple grants
`com.apple.developer.carplay-audio` against a development team, and the scene does not
activate without it. So iOS cannot be driven in a car or in the CarPlay simulator here. The
rows a car draws are built and asserted on the host as `CarShelf` and `CarShelfTests`, and
`App/CarScene.swift` holds the two templates. `audiobooks-and-playback`'s design note "The
day an Apple team exists" lists the four steps the owner takes.

## Suggested order

1. Section A, item 1. The accessibility audits gate every claim about whether the apps are
   usable.
2. Section D, item 1. Adding a Kavita server was broken until today, and every other
   Kavita check depends on it.
3. Section A, items 3 and 4. They close the paperwork and the vacuous-test risk.
4. Sections B and C. They need hardware in your hands.
5. Section E. It needs the server reconfigured first.
