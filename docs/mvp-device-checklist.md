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

**The iOS widget on a device needs an Apple Developer signing team.** The App Group that the
widget reads cannot be provisioned without one. The widget, the snapshot and the group are
built, and the unsigned simulator build reads the group. `WidgetSigningTests` holds the
group, the target and the URL scheme equal. Set `DEVELOPMENT_TEAM` in `project.yml`, build,
and install. Then add the widget, read a book, and check the cover, the title and the part
read. The Android widget needs no team: add it, read a book, and check the same three. See
[ADR-0011](decisions/0011-home-screen-widgets.md), "The owner's step".

**CarPlay on a device needs the same team, for the same reason.** Apple grants
`com.apple.developer.carplay-audio` against a development team, and a device build with the
key cannot be signed without one. The simulator build carries the entitlement and the scene
manifest already (`App/StoryArc.simulator.entitlements`, `App/Info.simulator.plist`), and
the device build carries neither. A guard test, `CarSimulatorOnlyTests`, asserts both. To see
the scene, open the iOS Simulator's CarPlay window (I/O, External Displays, CarPlay), open
StoryArc there, and check the list, the resume row and now-playing. In a car, the owner takes
the four steps in `audiobooks-and-playback`'s design note "The day an Apple team exists".

## G. Wave 4 of close-all-yellow, 2026-10-09

Each item is an owner step that an emulator or a simulator cannot answer.

1. **The A to Z rail tick (both).** On a phone, drag a finger down the rail. Feel one
   selection tick for each new letter. The unit tests prove the call, not the feel.
   Task `close-the-audited-gaps` 24.6.
2. **One stop in French (both).** With VoiceOver, and then with TalkBack, set to French,
   open the list of publications that could not be opened. Swipe once on an entry. The
   screen reader must read the file name and the French reason together. Task
   `one-vocabulary-in-four-languages` 1.8.
3. **The sleep-timer chips (Android).** With TalkBack, check that each chip (5, 15, 30
   and 45 min) is read once. Tasks `close-the-audited-gaps` 24.5 and
   `audiobooks-and-playback` 8.1.
4. **The rotation freeze (Android).** On the phone that froze, record a Perfetto trace
   or run `adb shell dumpsys gfxinfo` while the library page rotates. Task
   `close-the-audited-gaps` 21.1.
5. **The web row note (iOS).** Open the cover menu on a publication page. Check that the
   subtitle of the web row wraps fully inside the menu. Task `close-the-audited-gaps` 24.1.
6. **The reader proofs (both).** Look at the paper grain in light and dark (task
   `reader-theming-and-page-transitions` 0.5). Do the second drag during a curl settle
   (7.5). Listen with VoiceOver and with TalkBack over the theme sheet (7.6).

## H. Wave 5 of close-all-yellow, 2026-10-09

Each item is an owner step that an emulator or a simulator cannot answer. Each item names
what the emulator or simulator proved.

1. **Read-aloud after the reader closes (iOS).** Start read-aloud, close the reader, lock the
   phone, and hear the voice continue. Simulator: the bar still offers Pause four seconds
   after the reader closes. The sound and the lock screen are not proved. Task
   `read-aloud-beyond-the-reader` 0.1.
2. **Read-aloud after the reader closes (Android).** Start read-aloud, back out of the
   reader, and hear the voice continue. Emulator: one media session in state PLAYING, one
   app notification, the app holds the audio focus. Google speech synthesis crashes there
   (SIGILL), so no sound was made. Task `read-aloud-beyond-the-reader` 0.2.
3. **A call during read-aloud (Android).** Start read-aloud, take a call, hang up, and hear
   the voice carry on. Then pause, take a call, hang up, and check the voice stays silent.
   Emulator: `adb emu gsm call` gave PAUSED then PLAYING, and PAUSED then PAUSED. The test
   `aCallEndingResumesTheVoice` fails and its cause is not isolated. Task
   `read-aloud-beyond-the-reader` 4.1.
4. **An audiobook, an EPUB and a call (Android).** Start an audiobook, open an EPUB (the
   narrator stops), start read-aloud (one voice), take a call, end the call, and confirm that
   only the voice speaks. Emulator steps 1 to 7 passed. In step 8 the voice could not start
   while the call held the audio focus. Also check that the displaced audiobook comes back
   where it stopped: on the emulator a never-finished book now resumes (46136 ms against a
   stored 46095 ms, and 68414 ms against 68373 ms), but a book that was finished once still
   restarts at 0. Task `audiobooks-and-playback` 6.1.
5. **Reopen an audiobook after a force quit (iOS).** Play a book for two minutes, force quit
   the app, reopen the book, and confirm the same minute. Simulator: chapter Two at 0:01.
   Task `audiobooks-and-playback` 13.3.
6. **The chapter list with a screen reader (both).** With VoiceOver or TalkBack on, confirm
   that the list says finished, in progress and nothing on the right rows. Proved by reading
   the row labels: iOS "Finished, One", "In progress, Two, 1 second left", "Three"; Android
   "Finished", "Playing", no mark. Task `audiobooks-and-playback` 15.6.
7. **Headphones removed (Android).** Play a book over wired or Bluetooth headphones,
   disconnect them, and confirm the audio pauses. Reconnect and confirm it does not start
   again. The emulator image refuses the broadcast (no root). Task `audiobooks-and-playback`
   3.9.
8. **Split View beside another app (iPad).** Put StoryArc in Split View beside another app,
   then drag the divider narrow and wide again. The narrow slot must drop the sidebar and
   fill with the page. The widened slot must show the same publication in both panes.
   Simulator: a resized window only, compact width and back. Tasks
   `one-library-three-destinations` 4.1 and 4.3, `publication-detail` 4.1.
9. **A foldable at half-open (Android).** On a Pixel Fold AVD or a real foldable at the
   half-open posture, open a publication in the library pane. Take the frame and write the
   posture in the README. Task `one-library-three-destinations` 4.2.
10. **A writable share as the sync place (both).** Sync, open a second device on the same
    share, and check both show the same position. Simulator and emulator: the document is
    written and overwritten on a signed and an encrypted Samba share, a stopped share gives
    the grey "cannot be reached" line, and a foreign or newer file is refused with nothing
    written over it. A real NAS and a second device were not used. Task `library-sync` 2.2.
11. **A cloud folder as the sync place (both).** Pick a folder in iCloud Drive (iPhone) and
    in Google Drive (Android), write on one device, see the file arrive on the other,
    relaunch, and check the place still works. Proved with a local folder on both: the grant
    or bookmark holds across a relaunch and the next sync rewrites the file. No cloud
    provider was used. Task `library-sync` 2.3.
12. **Background sync on a locked phone (both).** Turn sync on, read to a new page on device
    A, lock it for 20 to 30 minutes, and check device B shows the position after it opens.
    Android emulator: the 15-minute periodic job exists and `adb shell cmd jobscheduler run
    -f` rewrote the file. iOS simulator: not proved, because `BGTaskScheduler.submit` fails
    there with code 1. Task `library-sync` 4.3.

## Suggested order

1. Section A, item 1. The accessibility audits gate every claim about whether the apps are
   usable.
2. Section D, item 1. Adding a Kavita server was broken until today, and every other
   Kavita check depends on it.
3. Section A, items 3 and 4. They close the paperwork and the vacuous-test risk.
4. Sections B and C. They need hardware in your hands.
5. Section E. It needs the server reconfigured first.
