# Tasks

**Ordering:** Phase 2 on iOS cannot start until the navigation shell from
`one-library-three-destinations` exists — there is no accessory slot without a
tab bar. Phases 0, 1 and 3 have no such dependency, and the whole Android side
has none.

**A task that changes a screen owes a screenshot from a booted simulator or
emulator**, light and dark, default and largest text size, per
[AGENTS.md §6](../../../../AGENTS.md).

**What a tick means here.** A task whose deliverable is code plus a host test is
ticked when both have landed. A task whose deliverable is an *observation* — a
screenshot, a notification tapped, a call taken — stays unticked until somebody
has run it on a simulator, an emulator or a device, however finished the code
underneath it is. Where the code for such a task has landed, the note under it
says so and names what is left to watch.

## Phase 0 — Prove the assumption

- [ ] **0.1** iOS: start speech, dismiss the reader, confirm the voice continues
      with the audio-session category and background modes the app already
      declares. Deliverable: a yes or no, on a booted simulator and — because
      audio-session behaviour on a simulator is not a device — recorded as
      simulator-only until someone runs it on hardware.
- [ ] **0.2** Android: confirm the existing foreground service keeps speaking when
      the reader activity is finished while the app stays in the foreground, which
      is a different case from the backgrounding the service was built for.

## Phase 1 — Move the ownership

- [x] **1.1** iOS: lift the session out of the reader's model into something that
      outlives a screen. The reader observes it; it does not own it.

      **Lifted on both platforms, because Android's ownership was not as correct as
      `design.md` assumed.** `ReadAloudCentre` (iOS) and `ReadAloudHost` (Android)
      now own the synthesizer or controller, the sentence cursor, the media
      controls, the interruption contract and the position writer. A reader on
      screen registers as a follower to draw the sentence and move the page, is held
      *weakly*, and is let go without a word when it disappears —
      `EpubReaderView.onDisappear` and `EpubReaderActivity.onDestroy` release the
      follower instead of ending the session, and `EpubReaderModel.readAloud` is now
      read from the centre rather than stored.

      Android needed the same lift for a reason the design did not have. The
      foreground service is real and does survive backgrounding, but
      `ReadAloudController` belonged to the activity and ran on its `lifecycleScope`,
      so finishing the reader while the app stayed in the foreground cancelled the
      walk and released the engine. The service was never the thing that died; the
      thing driving it was.

      **Where they live, and why.** Both sit in the module that already owns the
      reader — `EpubReaderFeature` and `feature/epubreader` — because they hold a
      Readium object and ADR-0005 keeps Readium behind that module, and because a
      feature module may not depend on another. The app layer already depends on
      both to open the reader, so Phase 2's transport can observe the session
      without inverting that rule. Each type carries the reasoning in its own doc
      comment.
- [x] **1.2** The position handoff: the reached position is written when the
      session ends, whoever ended it and whatever screen was on top. **A test, not
      an inspection** — this is the path that can lose an hour of listening.

      **Written on every sentence, and again when the session ends.** `SpokenPosition`
      holds the identity, the reading order and the store, all copied out of the
      reader when the session begins, so the write never reaches back into a screen
      that may be gone. `ReachedPosition` is the pure half — the locator and the
      progression, turned into the `ReadingProgress` the store takes — and it is what
      the tests assert on both platforms.

      Per sentence rather than only at the end, and that is the deliberate part: a
      process the system reclaims gets no ending at all, so the only position that
      survives one is a position already written. While a reader is on screen its
      navigator writes at the same rate, because the page follows the voice; this is
      that rate carrying on after the screen has gone.
- [x] **1.3** Mirrored host tests on both platforms: closing the publication mid
      sentence, reopening it, ending from outside the reader, and the platform
      taking the session away.

      **Written and mirrored case for case — 25 tests each — but the iOS suite has
      not been run here.** `ReadAloudSessionTests.swift` and `ReadAloudSessionTest.kt`
      grew the same ten cases in the same order: audio taken for good, audio given
      back, a reader's own pause surviving both, an idle session ignoring both, the
      three handovers (silence, the same book, a different book), and the three
      position ones (what a record contains, the end of the book, a sentence with no
      locator).

      The Android suite runs green on the host. The iOS suite lives in `StoryArcEpub`,
      whose test target needs a booted simulator — `pnpm test:ios:epub` is an
      `xcodebuild test` against one — and this session had no simulator to use. It is
      compiled, through `xcodebuild build-for-testing`, which builds the test target
      without booting anything. **Running it is the first thing to do with a
      simulator.**
- [ ] **1.4** One session at a time: opening another publication ends the current
      one at a sentence boundary, records the position, and says so once.

      **Two of the three landed; the third needs a word this change may not ship.**
      `SessionHandover` answers what opening a publication does to a voice that is
      already speaking — nothing, adopt it, or displace it — and both readers consult
      it as the book opens. Displacing ends the session and writes down the sentence
      it reached before the new publication draws a word; the sentence locator the
      voice is on *is* a sentence boundary, which is what makes the ending honest
      rather than abrupt. Adopting is the other half of the same question, and it is
      what makes reopening the book being spoken pick the voice up rather than start
      a second session on it.

      What is missing is "says so once". Telling a listener their voice stopped needs
      a string, and 5.5 sends every new user-facing string to the vocabulary slice.
      Rather than invent one here, or leave a flag nothing reads, the mechanism ends
      at the displacement. **Ticking this needs the vocabulary slice's wording and a
      surface to show it on — which on iOS is Phase 2's transport.**

## Phase 2 — The iOS transport

- [ ] **2.1** The docked control in the shell's accessory slot, with the inline
      form when the navigation is minimised. **Plain controls inside it** — the
      slot is already glass, and this codebase has a comment recording what
      glass-on-glass did to three glyphs.
- [ ] **2.2** Choosing it returns to the publication at the spoken sentence,
      without the voice stopping, from every destination and from any depth.
- [ ] **2.3** It appears when a session starts, goes when it ends, and reserves no
      space when absent. Screenshot: with a session and without, on each
      destination.
- [ ] **2.4** Accessibility: reachable in the reading order, labelled per action,
      and it does not take focus when it appears. Verified with the screen reader
      on, not by reading the code.
- [ ] **2.5** Screenshot at the largest text size, where a compact transport
      truncates first.

## Phase 3 — Android, which adds no bar

- [ ] **3.1** Confirm the notification and lock-screen controls are correct while
      the app is foregrounded with no reader on screen — not only while
      backgrounded. Screenshot the notification in both states.
- [ ] **3.2** Returning from the notification lands in the publication at the
      spoken sentence, not at the app's launch destination.

      **Built, and unticked only because nobody has tapped it.**
      `ReadAloudService.reopen` targeted `getLaunchIntentForPackage` under a comment
      saying the reader activity could not be targeted, "because the reader needs a
      publication and a location to be started with, and neither survives in a
      notification that may outlive the screen that made it".

      The obstacle was real and 1.1 removed it. The book being spoken now belongs to
      `ReadAloudHost` rather than to an activity, so the three strings
      `EpubReaderActivity.intent` needs travel on every refresh of the notification —
      and are kept between refreshes, because a button press arrives on an intent
      carrying nothing but its action. The *sentence* needs nothing extra: 1.2 writes
      the reached position on every sentence, so the reader opens at the recorded
      position and that position is the sentence the voice is on. A reader still on
      screen is rebuilt rather than brought forward, which re-parses the publication
      and then adopts the running session by 1.4's `ADOPT` — the voice does not
      notice, because it is no longer that screen's.

      A `TaskStackBuilder` keeps the launcher entry point underneath as the parent of
      the back stack: a listener who lands in the book from the shade and presses
      back expects their library, not the app disappearing. **What is left is tapping
      it on an emulator**, with the reader closed and with it open.
- [x] **3.3** Explicitly assert that no in-app docked bar is added, and record why
      in the handoff, so the divergence is not read as an omission and "fixed"
      later.

      **Asserted: no in-app docked bar is added on Android, and none should be.**
      `ReadAloudBar.kt` exists and stays exactly where it is — in-reader chrome, on
      screen only while the book is open, beside the return control and above the
      percentage. It is not promoted anywhere, and nothing outside `EpubChrome`
      composes it.

      The reason, so the next reviewer does not "fix" this: Material has no
      persistent accessory slot above a navigation bar, so an in-app bar would be a
      control invented to make two screenshots match. Android already has the better
      answer to the same question — a media notification and lock-screen controls
      that survive the app being backgrounded, which a bar inside the app cannot. The
      Android work here was therefore to make the existing transport correct when the
      reader is *gone* rather than only when the app is backgrounded (1.1), and to
      make its way back land in the book (3.2). A screenshot pair will show a docked
      bar on iOS and no docked bar on Android, and that is the requirement rather
      than a gap in it.

## Phase 4 — The unhappy paths

- [ ] **4.1** Audio taken by a call and given back: the voice resumes; a pause the
      listener made is never undone.
- [x] **4.2** Audio taken for good: the session ends, the position is recorded,
      the transport goes.

      **It was a live defect on iOS, and it is fixed on the same table both platforms
      read.** `observeInterruptions` handled `.began` and `.ended` and nothing else,
      so an `.ended` without `.shouldResume` — audio taken and not given back —
      matched no branch: the session sat paused for ever, with no position written,
      nothing telling the listener, and no way out but force-quitting the app.

      `ReadAloudSession.endingInterruption(mayResume:)` now answers all three cases —
      nothing, resume, lost — and both platforms route their audio callback through
      it, which is what finally gives `lostAudio()` a production caller on either
      side. Audio taken for good ends the session whoever silenced it, because a
      session nothing can start is exactly what the spec forbids; a pause the reader
      made is still never *resumed* by an interruption ending, which is the other
      clause of the same sentence. Ending writes the reached position first and takes
      the media controls down with it.

      Asserted in four mirrored host tests each. **Hearing it happen still wants a
      real call on a device** — `AVAudioSession` interruptions on a simulator are not
      a phone ringing.
- [ ] **4.3** End of the publication: the voice stops, the highlight is withdrawn,
      the transport and the media controls both go away.
- [x] **4.4** The process is reclaimed mid-session: nothing is left claiming to
      play, and the last recorded position is where the voice actually got to.

      **Answered by 1.2's write rate, which is why it is written per sentence.** A
      reclaimed process gets no ending, no `onDestroy` and no interruption — so
      anything a teardown would have written is lost. The last position on disk is
      therefore the last sentence the voice reached, because it was written when the
      voice reached it.

      Nothing is left claiming to play. On iOS `MPNowPlayingInfoCenter` goes with the
      process. On Android the service was already correct and stays so: it is
      `START_NOT_STICKY`, and a restart with a null intent calls `stopSelf()` under a
      comment saying the only honest thing it could do is stop, "because the book it
      was reading is gone with the process". A restarted service now has one more
      reason to be honest — `ReadAloudService.commands` is set by the host when a
      session begins and cleared when it ends, so a button on a stale notification
      reaches nothing rather than a dead reader.

      The position half is asserted in the mirrored tests. **The reclaim itself needs
      a device** — `adb shell am kill`, or the memory pressure that is the real case.

## Phase 5 — Gates

Ticked when the change is complete; Phase 2 has not landed. What this slice ran,
and what it could not: `corepack pnpm lint` passed (5.1 and 5.4 included);
`swiftlint lint --strict` passed over 451 files; `swift test` in `StoryArcKit`
passed, 1156 tests; `:feature:epubreader:lint` and
`:feature:epubreader:testDebugUnitTest` passed, 25 read-aloud tests among them.
`StoryArcEpub` was compiled with `xcodebuild build-for-testing`, which builds the
test target without booting anything, but **its tests were not run and
`pnpm build:ios` was not run** — both need a simulator this session did not have.
No new user-facing string ships from what has landed so far (5.5).

- [ ] **5.1** `corepack pnpm spec:validate`.
- [ ] **5.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm test:ios:epub`, `pnpm build:ios` — this change touches what the app
      target and StoryArcEpub compile. 400-line cap.
- [ ] **5.3** Android: `./gradlew :feature:epubreader:lint
      :feature:epubreader:testDebugUnitTest`, then the fuller run if anything
      outside that module moved.
- [ ] **5.4** `corepack pnpm lint`.
- [ ] **5.5** No new user-facing string ships from this change. If the iOS
      transport needs a label, hand it to the vocabulary slice.
- [ ] **5.6** Screenshots complete and referenced in the handoff, including the
      Android notification, which is a screen a reader sees even though it is not
      a screen the app draws.
