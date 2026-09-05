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

- [~] **0.1** iOS: start speech, dismiss the reader, confirm the voice continues
      with the audio-session category and background modes the app already
      declares. Deliverable: a yes or no, on a booted simulator and — because
      audio-session behaviour on a simulator is not a device — recorded as
      simulator-only until someone runs it on hardware.

      **The declarations are all in the tree and nobody has heard the result.** What the
      assumption needed is present: `project.yml` declares `UIBackgroundModes: audio` (line 96
      on 2026-09-05 — it was 90 when this note was written, and the floor comment above it
      moved the number, which is why the key is named rather than the line);
      `PlaybackAudioSession.activate()` sets category `.playback` with mode `.spokenAudio`,
      which is what keeps a book talking through a screen lock; and the session claims it
      through `PlayerCentre.begin` → `platform.sessionBegan()`, reached from a read-aloud
      session because `ReadAloudCentre.begin` calls `adoptSystemPlatform()` first. Nothing
      new was declared for this change, which is what the task asked to confirm.

      **What is still owed is the listening.** Boot a simulator, open a reflowable fixture,
      press read-aloud, dismiss the reader with the swipe, and confirm the voice carries on
      and the accessory appears above the tab bar. One frame with the reader gone and the
      voice running is the evidence; the control is the same shell one second earlier with
      the reader still over it. Then the same walk on hardware, because an `AVAudioSession`
      on a simulator is not a phone — the task already says to record the simulator answer
      as simulator-only.
- [~] **0.2** Android: confirm the existing foreground service keeps speaking when
      the reader activity is finished while the app stays in the foreground, which
      is a different case from the backgrounding the service was built for.

      **The cause of the old failure is gone and the observation is not made.** 1.1 found
      what would have failed this: `ReadAloudController` ran on the activity's
      `lifecycleScope`, so finishing the reader cancelled the walk even though the service
      lived. It now owns a `SupervisorJob` scope of its own and is held by `ReadAloudHost`,
      an `object`. The manifest half is unchanged and correct —
      `feature/epubreader/src/main/AndroidManifest.xml` declares
      `FOREGROUND_SERVICE_MEDIA_PLAYBACK` and `android:foregroundServiceType="mediaPlayback"`
      on `.ReadAloudService`.

      **Owed on an emulator:** open a reflowable fixture, start read-aloud, press back out
      of the reader so the activity finishes while the app stays on the library, and confirm
      the voice carries on. Two frames: the library with the media notification in the shade
      and the reader gone, light and dark. `pnpm capture:android --list` names the routes.

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
- [~] **1.4** One session at a time: opening another publication ends the current
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

      *Phase 2:* the surface exists now. `ReadAloudDock` is where a listener would be
      told, and it is the right place — they are looking at the navigation, not at a
      book. Still no wording, so still not ticked.

      *2026-09-05, checked against the tree rather than against the note above.* **The
      surface is real and its name in this task is wrong.** `ReadAloudDock` no longer
      exists — `audiobooks-and-playback` deleted it in `8991d439` and put one compact bar in
      the accessory slot for both a narrator and a voice. The place a listener would be told
      is `PlayerDock` in `StoryArcKit/Sources/PlayerFeature`, which that change owns. Nothing
      about the argument moves: it is still the right surface, there is still no wording, and
      5.5 still sends the sentence to the vocabulary slice, which is not yet a change in
      `docs/openspec/changes/`.

      **The other two clauses hold on both platforms, and one of them holds less widely on
      Android than the tick above implies.** iOS asks `PlayerCentre.handover(opening:)`, which
      knows about *both* kinds of session, so opening an EPUB while an audiobook is narrated
      displaces it too. Android asks
      `SessionHandover.opening(bookId, ReadAloudHost.book.value?.id)` in
      `EpubReaderActivity.prepareReadAloud`, which sees only the voice: `ReadAloudHost` and
      `PlaybackHost` are two independent sessions there, and `PlaybackHost`'s own KDoc says
      so — "read-aloud has its own engine and its own host today, and the seam that lets it
      become a second `PlayerSource` is `start`". So on Android a narrated audiobook and a
      spoken EPUB can speak at once. That is `audiobooks-and-playback`'s to close, not this
      change's: `STATUS.md` already lists "read-aloud does not drive the player yet" as one of
      its open items, and this change's delta scopes the scenario to "a different publication
      **while the voice is speaking**", which Android does answer.

      *2026-09-05, later the same day, checked against the tree.* **The Android clause above
      is closed and the paragraph it sits in is now wrong about the code.**
      `audiobooks-and-playback` shipped `SpokenAudio` in `:core:playback` — one authority both
      hosts register with — and `EpubReaderActivity.prepareReadAloud` now asks
      `SpokenAudio.shared.claim(bookId, by = ReadAloudHost)` rather than
      `SessionHandover.opening(bookId, ReadAloudHost.book.value?.id)`. `SpokenAudio.speaking`
      reads across every registered speaker, so a narrated audiobook is visible to a voice
      about to start and vice versa; `claim` silences what it displaces, **position first**,
      before it returns. Adopting is guarded at both ends the same way — `isHeldOnlyBy(by)`
      downgrades an `ADOPT` to a `DISPLACE` when anything else holds the same publication,
      which is the guard iOS reaches from the other side. `SpokenAudioTest` asserts it without
      a process. So the sentence *"on Android a narrated audiobook and a spoken EPUB can speak
      at once"* is no longer true, and neither is the reason given for it: `PlaybackHost` and
      `ReadAloudHost` are still two engines behind two services — collapsing them is that
      change's task 6.1 — but they are no longer two *authorities*.

      **The clause this task is still short of is the third, and its owner is the open
      question.** The vocabulary slice *is* a change now —
      `docs/openspec/changes/one-vocabulary-in-four-languages/` — so the sentence above about
      it not existing is stale. But reading its tasks against this: §1–§3 promote **existing**
      English literals to keys, §4 reconciles keys the two platforms word differently, §5 adds
      the check that catches a literal. **None of those accepts a sentence that has never been
      written on either platform**, which is what "the listener is told once that the voice
      stopped" needs. So the wording is not merely unwritten, it is unowned: 5.5 hands it to a
      change whose scope, as drafted, does not take it. Nothing is invented here — that is
      5.5's rule and the standing hazard's — and this stays `[~]` with the gap named rather
      than papered over. **The owner has to place it**: widen the vocabulary slice by one
      task, or let this change ship the one key with its four translations against 5.5.

## Phase 2 — The iOS transport

- [x] **2.1** The docked control in the shell's accessory slot, with the inline
      form when the navigation is minimised. **Plain controls inside it** — the
      slot is already glass, and this codebase has a comment recording what
      glass-on-glass did to three glyphs.

      **`ReadAloudDock`, in the slot `AppShell` has been holding open.** It names the
      publication and the chapter, carries the four verbs the lock screen carries,
      and the whole of its title area is the way back. Placement is read from
      `tabViewBottomAccessoryPlacement`: expanded keeps the chapter and all four
      controls, inline drops to the title, play and stop — that placement *is* the
      minimised tab bar, three destinations and a search button wide, and four more
      glyphs there would leave the title nothing.

      **Two transports, deliberately, and one vocabulary.** `ReadAloudBar` stays in
      the reader with `.glass` buttons inside the reader's own
      `GlassEffectContainer`; the dock uses plain controls because the slot is
      already the material — §3.0's budget, and the device evidence in
      `ReadAloudBar`'s own header. That difference cannot be parameterised honestly,
      so they are two views. What they shared and could drift — five glyphs, five
      labels — is now `ReadAloudControl`, and both read it.

      The dock is `public` and lives in `EpubReaderFeature` for the reason
      `ReadAloudCentre` does, plus one more: the `readaloud.*` keys live in that
      module's catalogue, and a copy in the app target's would be the same five
      strings in two places for a fifth locale to keep in step. See 5.5.
- [x] **2.2** Choosing it returns to the publication at the spoken sentence,
      without the voice stopping, from every destination and from any depth.

      **The way back is `onOpen`, the same seam a cover on the shelf uses.** The dock
      hands the shell the publication and its URL — carried on `SpokenBook` since
      Phase 1, so the return opens the same bytes rather than searching a library for
      something that looks like them — and the app layer presents the reader it
      already presents. No second path, and no locator to carry: opening the book
      that is already being spoken is the case `SessionHandover` answers with
      `adopt`, so the reader picks up the sentence the voice is on and the voice
      never notices. `ReadAloudSessionTests` composes the two ends of that in
      *"Choosing the transport reopens the book the voice is on, and adopts it"*.

      Every destination and any depth come from where the two things are attached:
      the accessory belongs to the `TabView`, so it survives a push inside a tab, and
      the reader's `fullScreenCover` belongs to the window's root, so it covers
      whatever the listener had descended to. Neither is a new mechanism.
- [~] **2.3** It appears when a session starts, goes when it ends, and reserves no
      space when absent. Screenshot: with a session and without, on each
      destination.

      **Written and asserted as a value; the pixels are unwatched.** Absence is
      `ReadAloudTransport.of(_:speaking:)` returning `nil`, and the shell's accessory
      builder then produces no content at all rather than an empty view — the `if` is
      in `AppShell` and not inside the dock precisely so the slot is never handed a
      view to decide about. Five tests cover it: no session, a paused session that
      keeps its transport, and each of the three endings (the listener stopped it,
      the audio was taken for good, the book ran out of words).

      What no test here can reach is whether the platform reserves the slot anyway.
      **The screenshot that settles it is the shell with no session, next to one from
      before this change: the tab bar must be the same height.** If it is not, the
      answer is `tabViewBottomAccessory(isEnabled:)`, which is iOS 26.1 against a
      26.0 floor and would cost an availability branch — `AppShell` carries the note.

      *2026-09-05, checked against the tree.* **That screenshot was taken, it said the
      platform does reserve the slot, and the remedy is in the tree.** Not by this change:
      `audiobooks-and-playback` hit the same slot with the same question and
      `AppShell.PlaybackAccessory`'s own comment records the result — an empty builder still
      draws the glass capsule, so every destination lost that much height, and
      `tabViewBottomAccessory(isEnabled:)` is now applied behind `#available(iOS 26.1, *)`,
      the app's only availability branch. **On the 26.0 floor the empty capsule remains**, and
      that is a stated cost rather than a fixed defect — the delta says "no space is reserved
      for one", so a 26.0 device does not meet it and the branch is the honest half-answer.

      **Three names in the paragraph above are stale.** `ReadAloudTransport.of(_:speaking:)`
      is now `CompactPlayer.of(_:playing:)` in `StoryArcKit/Sources/Playback`, and it holds
      the same rule — `nil` for an inactive session, whoever ended it. The five tests are
      `CompactPlayerTests` (*"Nothing playing is no bar at all, not an empty one"*, *"Every
      ending withdraws the bar"* over both source kinds, *"A paused session keeps its bar"*)
      plus `PlaybackSessionTests.endingWithdraws`. The `if` is still in `AppShell` and not
      inside the bar, for the reason this note gave.

      *2026-09-05, later the same day — the branch is deleted and the floor answers the
      requirement.* **`AppShell` no longer carries an `#available`, and the empty capsule is
      gone from every device the app installs on.** The floor moved 26.0 → 26.1 in
      `apps/ios/project.yml` for this one API, so `tabViewBottomAccessory(isEnabled:)` is
      reachable unconditionally; the `else` that kept the capsule had no reader left and was
      removed. `PlaybackAccessory.body` is now one line. That also restores
      [ADR-0003](../../../decisions/0003-platform-floors.md)'s own stated consequence — *"iOS:
      no `if #available` branches for design"* — which had been untrue of this app only for
      as long as the slot needed the branch.

      **The paragraph above is now wrong about the `if` on the way in, and it matters.** There
      is no `if` in `AppShell` any more: absence is the `isEnabled:` argument, and
      `PlayerDock.body`'s `if let bar = centre.compact` is the *second* gate, inside the bar.
      Both are needed and they answer different halves — `isEnabled:` is what stops the
      platform reserving the space, and the `if let` is what stops an active-but-unrenderable
      session drawing a half-bar. The note's original reasoning ("the slot is never handed a
      view to decide about") is what `isEnabled:` now does properly.

      **Nothing in the type system tells the two calls apart**, which is how the empty capsule
      shipped in the first place, so the revert now has a guard:
      `ShellWiringTests.theSlotIsWithheldWhenNothingPlays` reads `AppShell.swift`'s code lines
      — comments filtered, the same precision `tabDeclarations(in:)` uses, because this file's
      prose quotes both spellings — and fails if the slot is applied without `isEnabled:`, if
      it is applied more than once, or if an `#available` branch returns. **Proved able to
      fail** per AGENTS.md §5: reverting the line to
      `content.tabViewBottomAccessory { if isPlaying { bar } }` failed it by name with the
      offending line quoted, and the line was put back. It is a source-text tripwire and not
      pixel evidence — the screenshot below is still owed and this does not stand in for it.

      **One thing Phase 2's bodies claim that the shipped bar does not do.** 2.1 says the
      transport "carries the four verbs the lock screen carries", and the delta's *Controlling
      it without going back* asks for pause, resume, **skip a sentence** and end. `PlayerDock`
      carries play/pause, stop, and — for a publication being read aloud — a chevron into the
      full player. **There is no skip control on the bar**, and its own comment says why: the
      minimised tab bar is four destinations wide, and skipping was left to the lock screen
      and the full player. Whether that meets "without opening the publication first" is a
      reading — the full player is not the publication — and it is
      `audiobooks-and-playback`'s file and its documented product decision, so it is recorded
      here rather than reversed from this change. `/opsx:verify` should settle it.

      *Settled, and not by widening the bar.* The owner's decision on 2026-09-05 was to
      **describe what shipped**: the bar carries pause, resume and end, and every other
      control of the session — sentence skip included — is one step away in the full player.
      The delta's *Controlling it without going back* now says exactly that, and the clause
      that still binds is the second one: reaching skip must stay **one step**, so a later
      change cannot bury it.

      **One case the delta's new wording does not survive, found reading `PlayerDock` against
      it.** The chevron into the full player is drawn under `if bar.wayBack == .publication,
      !isInline` — so in the **inline** placement, which is the tab bar minimised on scroll
      down, a read-aloud session's bar has no way into the player at all. Its title row goes
      to the publication. So while the bar is inline, sentence skip is not one step from the
      transport; it is one step through the book, which is the thing "rather than by finding
      the publication again" exists to exclude. Not reversed here for the same reason the
      paragraph above was not: it is `PlayerDock`'s own width argument in
      `audiobooks-and-playback`'s file, and a third glyph in a strip four destinations wide is
      the trade that change already refused. **Recorded for `/opsx:verify`**, which is where a
      reading of the delta against the shipped bar belongs.

      **Owed:** the shell on each of the four destinations with no session and with one, light
      and dark — the pair is what proves `isEnabled:` withholds the height rather than only
      the bar. No 26.0 frame is owed any more: the floor is 26.1 and there is no second code
      path to photograph.
- [~] **2.4** Accessibility: reachable in the reading order, labelled per action,
      and it does not take focus when it appears. Verified with the screen reader
      on, not by reading the code.

      **Built for it; not yet heard.** The dock is one `accessibilityElement(children:
      .contain)` group labelled `readaloud.start`, holding the book as a button and
      each verb labelled from `ReadAloudControl` — the labels ride on `Label` titles
      that `.labelStyle(.iconOnly)` hides visually and VoiceOver keeps, which is how
      `ReadAloudBar` has always done it. Each glyph gets a 44pt target. Nothing in
      the file moves focus, and that absence is the requirement: no
      `accessibilityFocused`, no screen-changed announcement.

      **One gap, named rather than papered over.** The way back is labelled with the
      publication and the chapter — what is playing — and not with what tapping does.
      Saying that needs a word this change may not ship (5.5), so the vocabulary
      slice should be asked for a `readaloud.return`; until then VoiceOver reads
      *"Read aloud, Sea Room, Chapter Two, button"*, which is what the platform's own
      mini players read and is short of the delta's *"each of its actions is labelled
      by what it does"*.

      *2026-09-05, checked against the tree.* **That gap is closed, and not by asking the
      vocabulary slice.** `audiobooks-and-playback` replaced `ReadAloudDock` with one
      `PlayerDock`, and its way-back row is labelled by what it does — `player.back` for a
      publication being read aloud, `player.open` for a narrated file that has no reader to
      go back to — with the title and chapter demoted to `accessibilityValue`, so VoiceOver
      reads the outcome first and what is playing second. `player.back` resolves in en, fr,
      de and es; `node scripts/ios-strings.mjs` passes. No `readaloud.return` is needed and
      the vocabulary slice should not be asked for one.

      The rest of the paragraph above still holds against `PlayerDock`: one
      `accessibilityElement(children: .contain)` group labelled `player.nowPlaying`, each
      control labelled from its own key, a 44pt target on every glyph, and no
      `accessibilityFocused` and no screen-changed announcement anywhere in the file — the
      absence being the requirement. **Every one of those is a source-text fact, which is
      exactly what this task refuses to accept as proof.** What is owed is a VoiceOver walk on
      a simulator: swipe into the bar from the tab bar and confirm it is in the reading order;
      hear the four elements in turn; and start a session with VoiceOver focused on a shelf
      cover and confirm the cursor does not move. Also owed: the same three with Full Keyboard
      Access on, because the delta names the keyboard and a switch beside the screen reader.

      *2026-09-05, later the same day.* **The source-text facts are not proof and were also
      not guarded, which are two different problems.** The task is right to refuse them as
      evidence for a tick; nothing followed from that about letting them be deleted silently.
      "No `accessibilityFocused`" is held by an absence, and adding one is a two-word edit that
      reads as a *courtesy* — announce the bar when it appears — that compiles, passes every
      suite, `swiftlint --strict` and both build gates, and moves a screen-reader user's cursor
      off the page they were reading every time a book starts speaking. Nothing in the
      repository would have failed.
      `StoryArcKit/Tests/PlayerFeatureTests/PlayerDockFocusTests.swift` now fails on any of six
      focus-moving symbols in `PlayerDock.swift`, and — paired, so that stripping the
      accessibility out does not satisfy the negative by leaving nothing to focus — on the
      absence of the containment, `player.back`, `player.open` or `accessibilityValue`. Both
      halves **proved able to fail**, mutations named in the file's header.

      **The tick still waits on the walk.** A tripwire says a modifier is declared; it cannot
      say what VoiceOver read out, whether the bar is in the reading order, or where the cursor
      went. The four owed observations above are unchanged.
- [~] **2.5** Screenshot at the largest text size, where a compact transport
      truncates first.

      **The words scale and the glyphs do not.** The control row is capped at
      `DynamicTypeSize.xxLarge` and the title and chapter are `lineLimit(1)` with tail
      truncation, so at an accessibility size the capsule spends its width on the
      book's name and the four controls stay hittable — a transport whose buttons grew
      until the title was three characters and an ellipsis would be worse for the
      reader who chose that size than for anyone else. **Unwatched: this is the
      screenshot that shows whether the trade lands.**

      *2026-09-05, checked against the tree.* **The trade survived the two bars becoming
      one, in the same three lines.** `PlayerDock.controls(_:)` caps its row at
      `.dynamicTypeSize(...DynamicTypeSize.xxLarge)` and the title stack is `lineLimit(1)`
      with `.truncationMode(.tail)`; the chapter is dropped entirely in the inline placement.
      `audio-playback` adds the clause that makes the truncation defensible rather than
      merely tidy — the accessory's height is the system's, so lifting the limit would clip a
      line mid-letter rather than grow the bar, and the text the tail eats is announced in
      full through `accessibilityValue`.

      **Owed:** the shell with a read-aloud session at `AX5` / the largest content size,
      light and dark, in both accessory placements — expanded above the tab bar, and inline
      after a scroll-down has minimised it — with a publication whose title is long enough to
      truncate. The inline frame is the one that matters: it is where a title, a chapter, a
      play button and a stop button compete for a strip four destinations wide.

## Phase 3 — Android, which adds no bar

- [~] **3.1** Confirm the notification and lock-screen controls are correct while
      the app is foregrounded with no reader on screen — not only while
      backgrounded. Screenshot the notification in both states.

      **Read end to end; nothing seen.** The state the task asks about is the one 1.1
      created, and the wiring for it is complete: `ReadAloudHost` is an `object`, so
      `announce()` still has a controller and a book after `EpubReaderActivity` has been
      destroyed, and `ReadAloudService.show` picks `startService` over
      `startForegroundService` once the service is up — which is the API 31 rule the
      companion's `isRunning` flag exists for. The notification is refreshed on every
      session change and on every change of the *line*, not of the sentence, so a chapter
      turning over redraws it and a sentence does not.

      **Two states worth photographing that this task does not name.** A refused
      `POST_NOTIFICATIONS` is a real state on API 33+: `EpubReaderActivity.startReadAloud`
      asks and ignores the answer, deliberately, because a refusal takes the shade's copy
      away and leaves the lock screen's own controls — which come from the `MediaSession` —
      untouched. And a *paused* session is `setOngoing(false)`, so the notification becomes
      swipeable and its `deleteIntent` is `ACTION_STOP`: swiping it away ends the session
      rather than orphaning it.

      **Owed:** four shade captures — speaking and paused, each with the app foregrounded on
      the library with no reader, and with the app backgrounded — plus one lock screen while
      speaking, and one shade with notifications refused showing that the lock screen still
      has its controls.
- [~] **3.2** Returning from the notification lands in the publication at the
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

      *2026-09-05, checked against the tree.* **The plumbing holds, and it has one
      consequence the note above does not state.** `EpubReaderActivity.intent(context,
      location, title, series)` takes exactly the three strings the service keeps, and
      `SpokenBook` carries all three, so the intent can be built with no screen alive. The
      activity is `launchMode` `standard`, and `TaskStackBuilder.getPendingIntent` puts
      `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK` on the launcher intent
      underneath — so returning from the shade **clears whatever else the listener had open
      in the app** and rebuilds library-then-reader. That is right for the common case and
      is the thing an emulator walk should look at hardest: a listener who was three screens
      deep in Settings loses that stack, silently.

      Two smaller facts checked: a button press carries only its action, and `location` and
      `series` survive it because `onStartCommand` writes them only when the extra is
      present; and a service the system restarts with a null intent calls `stopSelf()`, so
      there is no notification left with a null `contentIntent` to tap.

      **Owed:** tap the notification with the reader already closed, and again with it open,
      and confirm both land on the sentence the voice is on rather than at the top of the
      chapter — then press back once and confirm the library is underneath. One frame per
      landing.
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

      *2026-09-05, checked against the tree.* **The conclusion holds and the reason above is
      now false**, which matters because a tick resting on a false reason is a tick nobody can
      re-derive. "Material has no persistent accessory slot above a navigation bar" was true
      when it was written. `audiobooks-and-playback` then built one —
      `AdaptiveNavigation.kt`'s `aboveNavigation` slot, carrying `CompactPlayerBar` for a
      narrated audiobook — because `audio-playback` requires a compact bar "above the
      navigation control". The slot exists on Android, it works, and it is drawn today.

      **So a voice is kept out of it by one thing, and that thing is an accident.** The bar
      reads `PlaybackHost.nowPlaying`, and `PlaybackHost` drives media3 while a voice lives in
      `ReadAloudHost` behind Readium. `SpokenAudio` unified the two *authorities* on 2026-09-05
      and deliberately did not unify the two *engines* — that is `audiobooks-and-playback` task
      6.1. **On the day 6.1 lands, a read-aloud session starts arriving in `nowPlaying` and
      this change's requirement is reversed by a merge nobody read as a product change**, with
      every unit suite, `lint` and both compile gates green throughout. That is exactly the
      failure this task exists to prevent, arriving from the direction it did not expect.

      **The tick was prose and now has a tripwire.** The task's own verb is *assert*, and until
      now nothing a build runs did. `apps/android/app/src/test/kotlin/app/storyarc/ReadAloudAddsNoBarTest.kt`
      holds three claims against source text — `:app` names no read-aloud symbol; the slot
      above the navigation still composes `CompactPlayerBar` and still reads
      `PlaybackHost.nowPlaying`, whose failure message is where the 6.1 risk is written down;
      and `ReadAloudBar` is composed by `EpubReaderOverlays.kt` and nothing else, so the
      in-reader bar cannot be promoted quietly. Each was **proved able to fail** with a
      compiling mutation, listed in the file's own header. It is a tripwire and not pixel
      evidence: 3.1's emulator capture is still what shows a listener the notification and no
      bar.

      **The requirement itself now conflicts with `audio-playback`'s on Android**, and no
      artifact says which wins: one asks for a compact bar above the navigation whenever
      something plays, the other forbids one while a voice speaks. They are reconciled today
      only by the engine split. `/opsx:verify` should settle it, and the reconciliation is a
      product decision rather than a wiring one.

## Phase 4 — The unhappy paths

- [~] **4.1** Audio taken by a call and given back: the voice resumes; a pause the
      listener made is never undone.

      **Both clauses are built and asserted on both platforms; neither has been heard.**
      This is 4.2's sibling and it landed with it, on the same table: `PlaybackSession`
      carries the *cause* of a pause, `interrupted()` refuses to overwrite a pause the
      listener made, `pausedByListener()` converts the other way so that reaching for pause
      *during* a call is a decision the call's ending cannot undo, and
      `interruptionEnded(mayResume:)` resumes only when the platform says so **and** the
      pause was the interruption's.

      The production wiring is complete on both sides and reaches that table rather than
      branching beside it. iOS: `PlaybackAudioSession` observes
      `AVAudioSession.interruptionNotification`, reads `.shouldResume` out of the options
      bitmask, and routes `.ended` through `PlayerCentre.endingInterruption(mayResume:)`'s
      three outcomes. Android: `ReadAloudController.focusListener` maps
      `AUDIOFOCUS_LOSS_TRANSIENT` and `..._CAN_DUCK` to an interruption's pause — the focus
      request sets `setWillPauseWhenDucked(true)`, so a duck is deliberately a pause here —
      and `AUDIOFOCUS_GAIN` and `AUDIOFOCUS_LOSS` to the same three outcomes.

      Asserted host-side on both: `PlayerInterruptionTests`' *"Audio given back carries on by
      itself"*, *"A pause the listener made is never undone"* and *"A pause made during an
      interruption is the listener's"*, each over both source kinds, mirrored in
      `PlaybackSessionTest`'s *"an interruption that may resume gives the audio back"* and
      *"a pause the listener made is never undone by an interruption ending"*.

      **What a host test cannot be is a phone ringing.** An `AVAudioSession` interruption on
      a simulator is not a call, and an emulator's audio focus is not one either. Owed on
      hardware, both platforms: start read-aloud, take a call, hang up, and hear the voice
      carry on by itself; then start it, press pause, take a call, hang up, and hear that it
      stays silent. Nothing to photograph — this one is heard, not seen, and the handoff
      should say so rather than attaching a frame that proves nothing.
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
- [~] **4.3** End of the publication: the voice stops, the highlight is withdrawn,
      the transport and the media controls both go away.

      **Built on both platforms; one of the three clauses had no guard at all, and it does
      now.** The chain on iOS is Readium reporting `.stopped` → `SpokenSource.ended` →
      `PlayerCentre.end()` → `finish` → `source.stop()` → `SpokenSource.onSilence` →
      `ReadAloudCentre.finish()` → `follower?.withdrawSpokenHighlight()`. The transport goes
      because `CompactPlayer.of` returns `nil` for an inactive session, and the media
      controls go because `finish` calls `platform.sessionEnded()`, which clears
      `MPNowPlayingInfoCenter`. Android's is `ReadAloudController.speakNext` finding no next
      sentence → `stop()` → the host's collector → `ReadAloudHost.finish` →
      `withdrawSpokenHighlight()` and `ReadAloudService.dismiss`.

      **The highlight's clause was unasserted on the two endings the platform raises.**
      `source.stop()` is the *only* signal a source gets that a session is over, and it is
      what `SpokenSource` turns into `onSilence` — so it is the highlight's whole seam. It
      was asserted for the listener's own `end()` and for a displacement, and not for the
      book running out or the audio being taken for good: dropping it from `finish` would
      have left a decoration on the page of a finished book with `pnpm test:ios` green.
      Both endings now assert it, in `PlaybackSessionTests.runningOutEnds` and
      `PlayerInterruptionTests.audioTakenForGood`. **Proved able to fail** per AGENTS.md §5 —
      `source?.stop()` was removed from `PlayerCentre.finish`, both new assertions failed by
      name, and the line was put back.

      **Not watched.** That a highlight actually leaves the page at the last sentence is a
      pixel, and no host test reaches it. Owed: iOS simulator, the reader open on the last
      resource of a reflowable fixture, read-aloud running to the end — one frame at the
      moment the voice stops showing no spoken decoration and no accessory above the tab
      bar, light and dark; and the same walk on an Android emulator with the shade pulled
      down, showing the media notification gone. Android's teardown is unreachable from a
      JVM unit test — `ReadAloudHost` and `ReadAloudController` need `Context`,
      `TextToSpeech` and a Readium `Publication` — so on that side the emulator walk is the
      only evidence there will be.
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

**Phase 2 added one gate the last slice could not reach: `corepack pnpm build:ios`
passed.** It is the only one that compiles the app target, which is where the
accessory slot is wired, and it had been outstanding since Phase 1. Also passed
this slice: `corepack pnpm lint`, `swiftlint lint --strict` over 459 files,
`swift test` in `StoryArcKit` (1180 tests), and `xcodebuild build-for-testing` for
`StoryArcEpub`. **`pnpm test:ios:epub` was still not run** — it boots a simulator,
and the 31 read-aloud tests in `StoryArcEpub` are compiled but unexecuted. Running
them is still the first thing to do with a simulator, and Phase 2 added six of
them to the count.

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

      **Held on iOS: the transport ships no new string.** Every word in
      `ReadAloudDock` is an existing `readaloud.*` key or the publication's own
      metadata, and `node scripts/ios-strings.mjs` passes in all four languages.
      That is also why the dock lives in `EpubReaderFeature` — the keys are in that
      module's catalogue, and a copy in the app target's would be five strings in two
      places.

      **Two words the vocabulary slice should be asked for**, neither invented here:
      `readaloud.return`, so the way back is labelled by what it does rather than only
      by what is playing (2.4), and the sentence that tells a listener their voice
      stopped because they opened another book (1.4). The second has a surface now —
      this transport — and still no wording.
- [ ] **5.6** Screenshots complete and referenced in the handoff, including the
      Android notification, which is a screen a reader sees even though it is not
      a screen the app draws.

## Delta merge, 2026-09-04 — not this change's own work

`pnpm delta:drop` gained a check for **two active changes carrying a `## MODIFIED` delta on
one requirement**, and this change was one side of a pair. A MODIFIED requirement replaces the
whole block, so whichever of the two synced second would have deleted the other's scenarios —
silently, after the first change had archived and its delta was gone.

The pair was `ebook-reader` → *Reading aloud*, with
`audiobooks-and-playback`. **The two had also named one behaviour twice**: *Leaving the
publication while it speaks* and *Closing the publication while it is being read* are the same
scenario, and the gate compares scenarios by name, so the duplicate read as one dropped and
one added. This change's block keeps the richer wording under the **earlier** name — the name
that reaches the main spec when `audiobooks-and-playback` syncs — and gained that change's
player clause, its *The same controls as a narrated book* scenario, and the two compact-bar
bullets. The two blocks now agree, so the pair needs no recorded order at all.

Nothing here changes what this change builds or what its tasks say. It is recorded because the
edit lands in this change's delta and `openspec-guard` would otherwise report the plan as
having moved after the task list for no visible reason.
