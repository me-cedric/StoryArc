# Tasks — audiobooks, and one player for everything that speaks

Test-first throughout. The Android list is longer than the iOS one on purpose:
Android's media contract reaches the notification shade, the lock screen, process
death and Android Auto, and iOS already has the compact-bar surface from
`read-aloud-beyond-the-reader`. That asymmetry is platform obligation, not scope
creep — see [`design.md`](design.md).

## 1. The shared player model

- [x] 1.1 Both: `PlaybackSessionTests` / `PlaybackSessionTest` — one session type
      with two sources, and the surfaces cannot tell which is behind them. Assert by
      driving the same assertions over both.
      **iOS done.** A new `Playback` target in `StoryArcKit` — host-testable, so
      `pnpm test:ios` covers it with no simulator. `PlaybackSource` has two places the
      sources may differ (a part's duration, and what a skip moves) and **no `kind`,
      no `isNarrated` and nothing a view can switch on**; `PlayerCentre` is the one
      session object. Nine of the sixteen tests are parameterised over both source
      kinds, which is what "driving the same assertions over both" means here.
      **Android half done.** New module `:core:playback`: `PlayerSource` (the interface
      with two implementations), `NowPlaying` (everything a surface draws, and nothing
      that names the engine), `PlaybackCentre` (the one session), `PlaybackSession` (the
      state table). `PlaybackSessionTest` drives one set of assertions over a narrated
      part list and a spoken one.
      **And the read-aloud session was not a second copy left standing** — the table
      moved out of `:feature:epubreader`'s `ReadAloud.kt` and read-aloud now reads it
      from `:core:playback`, so "one session type" is a fact about the build rather than
      a claim. `ReadAloudSessionTest` keeps only what a voice has that a file does not.
- [x] 1.2 Both: parts, position, duration and speed as the design's table defines
      them. Assert that a source with **no known duration** reports position without
      a total rather than inventing one.
      **iOS done.** `PlaybackTime` carries `total: TimeInterval?` and `isScrubbable`,
      and `PlayerCentre.scrub(to:)` refuses to reach a source that cannot answer — so
      the scrubber is *absent* rather than present and refusing. Mutation-checked:
      making `isScrubbable` always true fails both the spoken-duration test and the
      scrub test. *The Android half is not started.*
      **Android half done.** `PlaybackPart`, `PlaybackPosition`, `PlaybackDuration`,
      `PlaybackSpeed`. Duration has **three** cases, not two: `Known` from the
      container, `Estimated` from characters and rate, `Unknown`. `statedMillis` is null
      for an estimate and `isScrubbable` is false — so "never presented as exact" is
      enforced by the type rather than by a comment. Mutation-checked: making
      `Estimated.statedMillis` return its millis fails two tests. A total across parts is
      all-or-nothing; mutation-checked by summing unknown parts as zero. iOS half
      outstanding.
- [x] 1.3 Both: starting a second publication stops the first, records its position
      first, and does not resume it when the second ends.
      **iOS done.** `PlayerCentre.begin` calls `end()` first, and `end()` writes the
      position before it clears anything. Mutation-checked: deleting that call fails
      the displacement test. *The Android half is not started.*
      **Android half done.** `PlaybackCentre.start` records, then stops, then plays, and
      the test asserts the **order** rather than the effects — mutation-checked by moving
      the record after the stop, which fails it. iOS half outstanding.

## 2. Audiobooks open

- [x] 2.1 Both: format-detection tests for M4B, MP3, FLAC and Ogg from **contents**
      rather than extension — an `.m4b` and an `.m4a` holding the same audio behave
      identically. `FormatSniffer` on both platforms, plus `Container.isAudio` so the
      reader-or-player question is asked in one place. Mutation-checked on both.
      *The folder half moves to 2.2*, which is where the folder scanner lives.
- [x] 2.2 Both: a folder of audio is one audiobook, and a folder mixing audio and
      images is the kind the majority of its entries are. `FolderKind` on both
      platforms, seven tests each, mutation-checked (make a tie an audiobook and the
      tie test fails). Asserted against the corpus's own two folders read from disk,
      not from a literal, so regenerating the fixtures differently fails it.
      `PageOrdering.isPage` split so audio reuses the resource-fork and dotfile
      exclusions rather than restating them.
      **A tie is a comic — a product decision, recorded as one**, because a folder of
      images is what StoryArc has always made of a folder.
      **And this one reads extensions where the rest of the layer reads bytes**, which
      is documented at the type: the unit being detected is the folder, its cheap
      evidence is its entries' names, and sniffing each entry would be one read per
      file to answer a question asked before anything is opened. Each part is still
      sniffed when opened.
      *Still to come with the player:* turning an audiobook folder into a
      `Publication`, which needs the model to carry an audio format.
      **The folder half is now done on Android** — see 2.3.
- [~] 2.3 Both: an audiobook with no chapter markers opens, its parts standing in for
      chapters, and nothing is reported as missing.
      **iOS done.** `AudiobookReader.read(fileAt:)` returns one unnamed part rather than an
      empty list, and `skippedPageCount` stays 0 so `isPartial` is false — nothing is
      reported as missing. `AudiobookReaderTests` and `AudiobookIndexingTests` assert both,
      against `unchaptered.m4a` read from the corpus. *The Android half is not started.*
      **Android half done.** `PublicationFormat` gains `M4B, MP3, FLAC, OGG,
      AUDIO_FOLDER` and an `isAudio`; `AudiobookFolder` reads a directory's parts through
      `PageOrdering.naturalCompare` rather than a second copy of it; `PublicationIndexer`
      routes audio to a `Publication` at **both** entry points, and asks `FolderKind`
      which kind a directory is instead of assuming a comic. `AudiobookIndexingTest`
      drives the corpus.
      **One containers-not-extensions decision worth naming**, because a flat `AUDIOBOOK`
      case was the obvious alternative: `local-library`'s imported copies work a file's
      extension back out of its media type, so one case would have written a copied MP3
      back out as an `.m4b`. Four container cases round-trip; `AudiobookFormatTest` pins it.
      **And no chapter marks are read while indexing** — that is the design and not a
      gap. An extractor per file would cost a library of five hundred audiobooks a full
      decode pass per scan to fill a list nobody opened; the player reads the container's
      markers when it opens the book. An unchaptered single file indexes as one part
      standing in for the whole, with nothing reported as missing. iOS half outstanding.
- [~] 2.4 Both: an `.aax`/`.aaxc` is refused by name, states the store's content
      protection as the reason, prompts for no key or account, and is distinct from
      an unsupported container. **Detection done and mutation-checked** — the brand is
      read at offset 8 and gets its own container case, so the refusal is structural
      rather than a message a caller chooses. What remains is the *wording* the user
      sees, which needs the player's own surface to say it on.
      **iOS wording done.** `IndexError.contentProtected` is a case of its own carrying
      **no payload** — there is no key to ask for, so there is nowhere a prompt could get
      its wording from. `RefusedFile.isProtected` says "protected by its store's content
      protection", names no format list (the format *is* supported), and suggests no way
      around it. Mutation-checked: throwing `.unsupported` instead fails the refusal test.
      A second test asserts the scanner's reason mentions no key, account, activation code,
      password or sign-in. *The Android half is not started.*
      rather than a message a caller chooses.
      **Android wording now done too, and the note above was wrong about needing the
      player's surface for it** — the refusal is shown by `RefusedFileDialog`, which
      already existed. `IndexException.ContentProtected` is a third case beside
      `Unsupported` and `Unreadable`, `OpenedFile.Outcome.ContentProtected` carries it to
      the dialog, and `open_in_protected` is written in all four languages. The library
      scanner and the download queue answer it separately too — a locked file is terminal
      and is not a failed verification to retry.
      `ProtectedAudiobookPromptsForNothingTest` is the guard: the branch must use its own
      string, the refusal path must construct no text field, the dialog must keep exactly
      one action, and every locale must carry the message.
      **The guard's first draft had to be thrown away and the reason is worth keeping**:
      it searched for the word "activation" and failed on the doc comment explaining that
      nothing ever asks for one. A guard that forbids describing the rule it enforces gets
      the comment deleted rather than the defect fixed, so it strips comments and matches
      what a prompt is *built* out of. Mutation-checked twice: pointing the dialog's branch
      at `open_in_unsupported` fails the guard, and throwing `Unsupported` from the indexer
      fails `AudiobookIndexingTest`. iOS half outstanding.
- [~] 2.5 Both: a truncated audiobook plays what it can and states how much it could
      not, in the player's controls, without interrupting playback.
      **iOS half done, and the other half is named rather than claimed.** A *folder* with an
      undecodable part is counted at index time — `Audiobook.unreadablePartCount` reaches
      `Publication.skippedPageCount`, so `isPartial` is the same flag a comic missing pages
      sets — and `PlaybackSource.unreadablePartCount` carries it to the player.
      **A truncated single file is not detected at index time and this is measured, not
      assumed**: `truncated.m4b` was cut with `+faststart`, so `AVURLAsset` reads its `moov`,
      reports the full 6 s duration, all three chapters and `isPlayable == true`. Nothing
      before playback says the media is short. Stating it needs the player to notice the item
      failing, which is §4/§5 work and is **not done**. *The Android half is not started.*
      **Android: the counting half is done, the stating half is not.**
      `AudiobookFolder` counts a zero-length part as skipped rather than dropping it, the
      indexer carries that count onto the `Publication`, `PlayerSource.skippedPartCount`
      and `NowPlaying.isPartial` carry it to a surface, and `AudiobookIndexingTest` pins
      that `truncated.m4b` still **opens** rather than being refused. What no test yet
      covers is a part that fails mid-decode — that is ExoPlayer's error path and belongs
      with 2.7 — and nothing yet draws the count, which belongs with 4.5.
- [x] 2.6 Add audiobook fixtures to the shared corpus: a chaptered M4B, the same
      chapters as ID3 CHAP frames, an unchaptered single file, a folder of parts
      whose names defeat lexical sort, a folder mixing audio and images, a truncated
      M4B, and a locked-file *stub* for 2.4 carrying the signature and nobody's
      content. Seven fixtures, 100 kB, byte-deterministic.
      `packages/test-fixtures/scripts/generate.py`, `manifest.json`, `README.md`.
      Two things the work turned up and the corpus now records: the first truncated
      fixture had no `moov` at all — ffmpeg writes it last, so a cut file pinned
      "damaged beyond opening" instead of "plays what it can", and `+faststart`
      fixed it; and `protected.aax` still holds a **decodable** stream, so the
      refusal has to come from the brand rather than from a decoder choking.
- [~] 2.7 iOS: `AVURLAsset` + `loadChapterMetadataGroups`. Android: media3 ExoPlayer.
      **iOS done** — `AudiobookReader`, asserted against all five audio fixtures read from
      disk. **`design.md`'s API claim needs one correction and it is load-bearing.** The
      method it names is right; the obvious argument is not. Passing the reader's preferred
      languages — `bestMatchingPreferredLanguages: ["en"]` — returns **zero** groups for both
      chaptered fixtures, because each declares its chapter titles under the `und` locale.
      Measured 2026-09-01: `availableChapterLocales` answers `["und"]`, `["en"]` yields 0
      groups and the asset's own identifiers yield 3. So the asset is asked what languages it
      has before it is asked for its chapters. Mutation-checked: restoring `["en"]` turns a
      three-chapter book into one unnamed part and fails two tests — which is exactly how it
      would have shipped, since nothing in a build would have said a word.
      *The Android half (media3 ExoPlayer) is not started.*
      **Android half written, and half of it is proved.** `AudiobookSource` is
      `PlayerSource` over an `ExoPlayer`, and `AudiobookChapters` holds every rule worth
      arguing about — asserted on the JVM against `ChapterMark`, a shape of our own, so
      that "an unchaptered book is one part and never an empty list" does not need a
      decoder running to be checked. Mutation-checked: returning an empty list for an
      unchaptered book fails two tests.
      **Where media3 puts chapters is worth writing down**: not on `MediaMetadata`. A
      `Chapter` is a `Metadata.Entry` hung off a track's `Format`, so it arrives with
      `onTracksChanged` and not with the item, and `Chapter` is `@UnstableApi`.
      **Not yet proved:** that a real `chaptered.m4b` decodes to those three marks. That
      needs an instrumented test driving an `ExoPlayer` over the corpus, and it is the
      honest gap in this task.
- [ ] 2.8 Android: bump media3 to **1.11.0** and declare `media3-exoplayer` and
      `media3-session` explicitly in the version catalog. Readium only puts 1.10.0 on
      the classpath at runtime scope. **Nothing else in this section is blocked on
      the bump** — see `design.md`: ID3 chapters already parse at 1.10.0, so the
      MP3-folder path, detection and the unchaptered case all land without it, and
      the bump buys M4B's own chapter atom and nothing else.
      **Android done, and both halves of `design.md`'s claim were re-checked against the
      shipped artifacts** rather than carried from the plan, by unzipping both extractor
      AARs and reading their class lists. At **1.10.0**: only `id3.ChapterFrame` and
      `id3.ChapterTocFrame`, no class anywhere carrying the string `chpl`, and nothing in
      `mp4/` referring to a chapter type. At **1.11.0**: `extractor.metadata.Chapter` is
      new, `mp4/BoxParser` carries `chpl`, and `Mp4Extractor` refers to `Chapter`. So the
      bump buys exactly what the plan says it buys.
      `:feature:epubreader:dependencies` confirms Readium puts `media3-session` and
      `media3-exoplayer` 1.10.0 on the **runtime** classpath — which is why this is a
      declaration as well as a bump, a runtime transitive being uncompilable-against.
      `:app:dependencies` shows Readium's 1.10.0 resolving to 1.11.0 with no conflict and
      `assembleDebug` passes.
      **One thing the plan does not say and every caller hits:** `metadata.Chapter` is
      `@UnstableApi`, so reading an MP4's chapter marks needs an opt-in at the call site.

## 3. The platform session

- [x] 3.1 iOS: `AVAudioSession` category `.playback`, mode **`.spokenAudio`**.
      `PlaybackAudioSession`, which also carries the interruption and route-change
      observation — **one copy for both sources**, which is what `design.md` asks for. The
      read-aloud session had these rules and a narrated book now reuses them rather than
      growing a second set that can drift. Not asserted by a host test: an audio session
      cannot be interrupted from one. Everything downstream of it is — see 3.8 and 3.9.
- [x] 3.2 iOS: extend the existing `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`
      wiring to the narrated source, so both feed the same lock screen.
      `NowPlaying`, driven by `PlayerCentre`, so both sources publish through one object.
      Which buttons are enabled follows what the source can *do* rather than which source
      it is: skip-by-seconds and a scrubber where there is a duration, sentence skip where
      there is not — `audio-playback`'s "present and refusing" rule applied to the lock
      screen. The elapsed/total pair is published only where a total exists, because a zero
      duration there is not a blank, it is a scrubber pinned at the end.
      Publishing lives inside `PlayerCentre`, at the end of all eleven methods that change
      it, and `everyChangePublishes` asserts each path reaches the platform.
      Mutation-checked: dropping the publish from `setSpeed` alone fails that test.
- [x] 3.3 iOS: speed without pitch — `AVPlayer.rate` with
      `audioTimePitchAlgorithm = .timeDomain`.
      `NarratedSource`. The algorithm is set on **every `AVPlayerItem`**, not once on the
      player: it is the item's property, and a folder makes a new item at every part
      boundary — the one place this would regress into chipmunk narration with nothing in a
      build saying so. `setSpeed` while paused records the number instead of applying it,
      because `rate` is also what starts an `AVPlayer`.
      **Not heard.** Nothing here has been listened to on a device; see §9.
- [ ] 3.4 Android: a real `MediaSessionService` with
      `foregroundServiceType="mediaPlayback"` and both `FOREGROUND_SERVICE`
      permissions. Assert the service is declared in the merged manifest.
      **Done.** `PlaybackService` is a `MediaLibraryService`, which is a
      `MediaSessionService` with a browse tree on top, declared in `:core:playback`'s own
      manifest with both permissions and both intent-filter actions.
      **Asserted of the installed package rather than of a file.**
      `PlayerServiceIsDeclaredTest` asks the `PackageManager` — a source guard over the
      module manifest would pass with the app not depending on the module, and the merger
      is exactly where that mistake lands. Five assertions, run on `storyarc-j6`, all
      passing. Mutation-checked on the device: changing the type to `dataSync` and dropping
      the `MediaBrowserService` action fails two of them.
- [x] 3.5 Android: media3's automatic `MediaStyle` notification — hand-rolling it is
      how the shade and the lock screen fall out of step.
      **Done, and the work was to install nothing.** No `MediaNotification.Provider` is
      set, so media3's `DefaultMediaNotificationProvider` draws it. What *is* chosen is
      which two buttons flank play/pause — `setMediaButtonPreferences` with
      `SLOT_BACK` / `SLOT_FORWARD`, not the deprecated `setCustomLayout`, because a
      preference says which slot a button wants and lets each surface place it.
      Not yet photographed in the shade — that is a capture and it belongs with §6.
- [~] 3.6 Android: `MediaSession.Callback.onPlaybackResumption` returning the saved
      position, so the shade carousel works after process death.
      **Written, not proved.** The three-argument overload; the two-argument one is
      deprecated at 1.11.0. `isForPlayback` is answered the same either way on purpose —
      the carousel's row and the audio behind it have to name the same place, and giving
      the drawing pass a different one is how a listener presses play on "Chapter 4" and
      gets chapter 1. The position arrives through `PlaybackService.resumption`, a
      process-wide handoff rather than a database read, because `:core:playback` does not
      depend on `:core:persistence` and a service the system just started has no scope.
      **Nothing writes to `resumption` yet** — that is the app's job and it lands with the
      surfaces. And proving it needs the process killed between two runs, which is a device
      exercise nothing here has done.
- [ ] 3.7 Android: `MediaLibraryService` and `automotive_app_desc.xml`.
      **Done.** The service is a `MediaLibraryService`; the descriptor declares `media` and
      nothing else, because declaring a capability the app cannot honour is how an app
      appears in a car's launcher and then does nothing.
      `PlayerServiceIsDeclaredTest` reads the `com.google.android.gms.car.application`
      meta-data off the installed package, which is how a head unit reaches it.
      **The browse tree itself is still media3's default** — `onGetLibraryRoot` and
      `onGetChildren` are unimplemented, so a head unit can drive what is *playing* and
      cannot yet browse the library. That is the honest state of this task.
- [~] 3.8 Both: interruption tests — audio taken and returned with the resume hint
      resumes; a pause the listener made is never undone; audio taken for good ends
      the session and records the position.
      **iOS done.** All three, over both source kinds, in `PlayerInterruptionTests` —
      plus the transitions themselves in `PlaybackTransitionTests`, which now run on the
      host in `pnpm test:ios` rather than in a suite no gate ran.
- [~] 3.9 Both: route-change test — headphones removed pauses, and reconnecting does
      **not** resume.
      **iOS done.** `PlayerCentre.routeLost` records the pause as the *listener's*, which is
      the mechanism that makes "does not resume by itself" true rather than a promise —
      nothing the platform sends afterwards can undo a listener's pause. Asserted over both
      source kinds. `PlaybackAudioSession` acts only on `.oldDeviceUnavailable`, because
      the notification also fires when headphones are plugged *in*.

## 4. The surfaces

- [~] 4.1 Both: `CompactPlayerTests` / `CompactPlayerTest` — the bar names the
      publication and the **chapter**, is absent when nothing plays, and does not
      displace, cover or resize the navigation control. Assert content behind it
      still scrolls to its end.
      **iOS done, in two halves.** What a value can hold is in `CompactPlayerTests`: the
      title and the chapter, the chapter following the audio, absence when nothing plays,
      and all three endings withdrawing the bar. The layout half is not assertable from a
      unit test — a tab bar cannot be one — so it is the pair of captures in
      `docs/designs/screenshots/after-2026-09-01-ios-player/`: the same shelf with and
      without a session, minutes apart, with the four destinations at the same height in
      both. **Photographed on a device**, and the bar names *Sea Room* and the chapter
      *Two* — read from the M4B's own chapter atom, which is also the end-to-end proof of
      the locale correction in 2.7. *The Android half is not started.*
- [ ] 4.2 iOS: generalise `ReadAloudDock` in `tabViewBottomAccessory` to the shared
      session, so a narrated book and a spoken one produce the same bar.
      **Not done, and blocked on a measured fact rather than on effort.** `PlayerDock` exists
      and takes the slot whenever `PlayerCentre` is running; `ReadAloudDock` still takes it
      for a spoken session, and `AppShell.PlaybackAccessory` chooses between them in one
      place with the blocker written at it.
      **Readium 3.11.0 cannot change speech rate.**
      `PublicationSpeechSynthesizer.Configuration` carries a `defaultLanguage` and a
      `voiceIdentifier` and nothing else, and `AVTTSEngine.swift:131` — the line that would
      apply a rate to the utterance — is **commented out upstream**; `rateMultiplier`
      appears nowhere else in the TTS sources. Checked in the pinned checkout on 2026-09-01.
      So a read-aloud session driving `PlayerCentre` would offer a speed control that does
      nothing, which `audio-playback` forbids by name: "every control the player offers
      works, or is absent — none is present and refusing".
      There are three honest ways out and choosing between them is a `design.md` decision,
      not an implementation detail: let a source declare that it offers no speed and have the
      surface omit the control; replace Readium's engine with our own `AVSpeechSynthesizer`;
      or carry a patched dependency. **`/opsx:update` before this task is picked up again.**
- [ ] 4.3 Android: hand-compose the row in `NavigationSuiteScaffold`'s `content`
      slot, full-width `surfaceContainer`, sharing the navigation bar's container
      colour. **Not** `BottomSheetScaffold` (no `bottomBar` slot, so the peek row
      would sit behind the navigation bar), **not** `HorizontalFloatingToolbar` and
      **not** `BottomAppBar` — both compile without complaint and both are ruled out
      by guidance. `design.md` records why, because the build will not.
- [ ] 4.4 Android: flat `LinearProgressIndicator` for the progress line.
- [~] 4.5 Both: the full player — cover, publication, chapter, position, duration,
      play/pause, skip both ways, scrub, chapter list, speed, sleep timer. Assert
      opening it never restarts, reloads or repositions the audio.
      **iOS done.** `FullPlayerView`, presented as a sheet from the compact bar. It holds no
      engine and no state beyond which sheet is open — it reads `PlayerCentre` and writes to
      it — so "opening it never restarts, reloads or repositions the audio" is true by
      construction rather than by care, and there is nothing in the file that *could*
      restart anything. The scrub control is drawn only where a duration exists, and the
      branch asks the **time** whether it has a total rather than asking which source is
      playing. **Photographed on a device** — cover, publication, chapter, a scrub control
      reading the chapter's own `0:00 / 0:02`, skip glyphs carrying 15 and 30, and the
      chapter list, speed and sleep timer.
- [~] 4.6 Both: a publication with no chapter markers lists its parts in playing
      order rather than showing an empty list.
      **iOS done, and there is no branch for it.** A source with no chapter markers reports
      one part rather than none — the rule lives in `AudiobookReader`, where the container is
      read — so `ChapterListView` never has an empty case to handle. What is left is naming
      an unnamed part, which `PlayerLabels.chapter` answers with its number and never with
      the file's name. *The Android half is not started.*

## 5. Controls

- [ ] 5.1 Both: speed changes without changing pitch, states a number, is remembered
      per publication and offered as the series default. Range 0.5×–3×.
- [ ] 5.2 Both: skip states its interval on the control, is configurable, and
      crossing a chapter boundary continues rather than stopping. Defaults 15 s back
      and 30 s forward — a **product decision**, recorded as one; media3's own
      defaults (5 s / 15 s) are wrong for spoken word.
- [ ] 5.3 Both: sleep timer offers durations **and end-of-chapter**, shows the
      remaining time, fades out rather than cutting, and records a position slightly
      before where the fade ended.
- [x] 5.4 Android: declare `COMMAND_SEEK_TO_PREVIOUS`/`NEXT` so the notification's
      three compact slots carry seek-back / play-pause / seek-forward.
      **Done.** All four are added in `onConnect`: the two chapter moves a head unit uses
      and the two second-counts the notification carries. The compact row's outer slots are
      `COMMAND_SEEK_BACK` and `COMMAND_SEEK_FORWARD` at 15 s and 30 s — media3's own
      defaults, 5 s and 15 s, are set aside on the `ExoPlayer.Builder`, and that is a
      **product decision** with no guideline behind it.

## 6. Playback outlives the publication

- [ ] 6.1 Both: leaving the reader while playing does not stop it, and the compact
      bar is the one action back.
- [ ] 6.2 Both: returning to a read-aloud session resumes at the sentence being
      spoken **then**, not where the reader left.
- [ ] 6.3 Both: reaching the end withdraws the highlight, dismisses the media
      controls and removes the compact bar.

## 7. Position

- [ ] 7.1 Both: an audiobook's position is an offset in a named part, survives close,
      restart and re-download, and resolves through content identity like every other
      position.
- [ ] 7.2 Both: a publication both read and listened to has **one** position, and
      returning never offers a choice of two.
- [ ] 7.3 Both: finishing by listening marks the publication finished and makes the
      same end-of-publication offers as finishing a comic.

## 8. Accessibility

- [ ] 8.1 Both: every control announced with a name and, where it has one, its value
      — speed, skip interval, remaining sleep time, position.
- [ ] 8.2 Both: the scrub control is an adjustable announcing its position **in
      time**, not as a percentage.
- [ ] 8.3 Both: the compact bar is one element with separate play/pause and open
      actions, and **does not steal focus when it appears**.
- [ ] 8.4 Both: at the largest accessibility text size nothing is truncated to one
      word and no transport control is pushed off the screen.

## 9. Docs and close-out

- [ ] 9.1 Module `README`s for the new player modules on both platforms.
- [ ] 9.2 Update `docs/openspec/STATUS.md` and the format table in the docs.
- [ ] 9.3 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 9.4 `agent-compass openspec-guard . --strict`.
- [ ] 9.5 `/opsx:verify audiobooks-and-playback`, then `/opsx:sync`.
