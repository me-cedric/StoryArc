# Tasks — audiobooks, and one player for everything that speaks

> **design.md moved on 2026-09-01 after this list did.** Three of its claims were
> contradicted by measurement during the iOS half — the chapter call's locale argument, the
> Readium rate that does not exist, and a truncated file that reports itself intact — and a
> fourth, the Android starting point, was simply wrong. The corrections are in design.md;
> the tasks they touch (2.5, 2.7, 4.2) carry them in their own entries.

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
      **`LibraryScanner` had a gate of its own that none of that reached**, and only the
      emulator showed it: a candidate-extension pre-filter with no audio in it, and a
      folder rule that counted images alone. Both are audio-aware now in all four places
      that have to agree — the `File` walk, the SAF walk, and the two snapshot listings
      the reconcile compares — and the SAF folder path asks `FolderKind` the same question
      the `File` path already asked. Four cases in `LibraryScannerTest`, two of them
      mutation-checked. Verified on `storyarc-j6`: every fixture appears with the right
      format label, and an `.m4a` shows as **M4B**, which is the treated-identically
      scenario arriving as a row in a real library.
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
      fails `AudiobookIndexingTest`.
      **And a second gap the device found, which the unit tests could not.** The sniffer
      names a locked file by its brand — but `LibraryScanner` never opened one. Its cheap
      extension pre-filter had no `.aax` in it, so a scanned folder dropped every protected
      audiobook in silence, which is precisely the outcome "refused by name" forbids. The
      extension is now a *hint about what is worth opening*, kept apart from the playable
      set so a locked file cannot become a folder's chapter, and the brand is still the
      fact. `LibraryScannerTest` asserts the skip carries the protection as its reason;
      the emulator now reports "1 couldn't be opened" where it previously showed nothing —
      `docs/designs/screenshots/audiobooks-2026-09-01/07-protected-counted-light.png`.
      **Still partial:** on the *scan* path the reason is carried by `ScanEvent.Skipped`
      and the library shows only a count. The words land on the open-with path, which is
      where a reader who chose the file is looking. iOS half outstanding.
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
      **Now proved on a device, though not yet by a test.** A twenty-minute M4B with three
      `chpl` chapters was built with ffmpeg, pushed to `storyarc-j6`, and opened: the player
      lists *The Shiants* 5:00, *Bird Island* 7:00 and *The Fank* 8:00, which are the marks
      the container carries. So the 1.11.0 bump does what the class-list check said it
      would. **What is still missing is an instrumented test** that drives an `ExoPlayer`
      over the corpus's own `chaptered.m4b` and asserts the manifest's three — a
      screenshot is evidence and not a gate.
- [x] 2.8 Android: bump media3 to **1.11.0** and declare `media3-exoplayer` and
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
      **Ticked after re-checking what was actually missing, which was neither the version
      nor the catalog entries.** Both were already there — `libs.versions.toml:63` reads
      `media3 = "1.11.0"` and both aliases resolve to it. What the tick needed was the
      *declaration* reaching a module: `:core:playback:dependencies --configuration
      debugCompileClasspath` now shows `media3-exoplayer` and `media3-session` 1.11.0 on the
      **compile** classpath, which a runtime transitive never is, and
      `:feature:epubreader:dependencies --configuration debugRuntimeClasspath` shows
      Readium's own `1.10.0 -> 1.11.0` with no conflict. The `@UnstableApi` opt-in is at two
      sites and no more: `AudiobookSource.adoptChapters`, which is the only place a
      `metadata.Chapter` is read, and `PlaybackService`, whose whole media3 session surface
      is unstable.

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
- [x] 3.4 Android: a real `MediaSessionService` with
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
      **Ticked on that recorded device run, and the tick is worth reading narrowly.** The
      code exists and something asserts it; the assertion is instrumented, and the emulator
      was held by another agent, so it was re-*compiled* here rather than re-run —
      `pnpm build:android:tests` passes. `pnpm gradle :app:connectedDebugAndroidTest --tests
      "app.storyarc.PlayerServiceIsDeclaredTest"` is the command that re-proves it.
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
      **Android: the field is written now, and — more to the point — it is no longer the only
      answer.** A process-wide field is null in exactly the case this callback exists for: a
      process the system has just created. So `PlaybackMemory` keeps the handful of strings
      needed to put the audio back — the URIs, the part titles, an index and an offset — in a
      preferences file the service reads synchronously, and `onPlaybackResumption` falls back
      to it. `PlaybackHost` writes it when a book starts and moves it on every publish, and
      forgets it when the session ends.
      **Not the reading position, deliberately.** That is `reading-progress`'s and the app
      stores it; this is a service's own note of what to put on the air, kept where a service
      with no scope and no database can read it. Eight cases in `PlaybackMemoryTest`.
      **Still not proved end to end:** that a killed process comes back through the carousel
      needs the process killed between two runs, and that has not been done.
      **The half of it a host test can reach is now reached, and it was the half where a
      silent error would have lived.** "Written, not proved" was accurate about the carousel
      and it was hiding an untested mapping: the `startIndex` handed back is one media3 throws
      on if the book no longer has it, *inside a callback the system is already showing a row
      for*, and a folder re-downloaded with fewer files is exactly how that index arrives.
      `PlaybackResumption` is that mapping, lifted out of the service so it can be asserted
      without one — seven cases in `PlaybackResumptionTest`: the saved place is the place it
      starts, a stale index and a negative offset clamp, an empty memory starts at zero rather
      than at minus one, a ragged title list still produces an item, and every item names the
      publication and its own chapter. Mutation-checked: dropping the clamp fails two.
      `onSetMediaItems` builds its answer there too, which is what keeps a car's "carry on"
      and the shade's "resume" one place rather than two nearly identical calculations.
      **Still owed, and still a device exercise:** `adb shell am force-stop app.storyarc` while
      a book is paused, then the shade's carousel row, then play. Nothing else can prove it.
- [x] 3.7 Android: `MediaLibraryService` and `automotive_app_desc.xml`.
      **Done.** The service is a `MediaLibraryService`; the descriptor declares `media` and
      nothing else, because declaring a capability the app cannot honour is how an app
      appears in a car's launcher and then does nothing.
      `PlayerServiceIsDeclaredTest` reads the `com.google.android.gms.car.application`
      meta-data off the installed package, which is how a head unit reaches it.
      **When this entry was first written the browse tree was still media3's default** —
      `onGetLibraryRoot` and `onGetChildren` were unimplemented, so a head unit could drive
      what was *playing* and could not browse anything. Superseded by the paragraph below;
      kept because it says what the tree replaced.
      **Android: there is a tree now.** `onGetLibraryRoot` answers a browsable
      `MEDIA_TYPE_FOLDER_AUDIO_BOOKS` root — unimplemented it answered an error, so a car that
      had found the app in its launcher could start nothing — and `onGetChildren` puts the
      book being listened to under it, from `PlaybackMemory`. `onGetItem` and `onSetMediaItems`
      turn a chosen row into the audio *at the place the row named*, so pressing play in a car
      carries on rather than restarting chapter one.
      `PlayerBrowseTreeTest` binds a real `MediaBrowser` to the installed service and asks it,
      which is what a car does; mutation-checked by restoring the error from
      `onGetLibraryRoot`. Every controller call goes to the main thread and every wait comes
      off it — media3 throws on the first and deadlocks on the reverse.
      **Still not the library.** One node, and it is "carry on with this". `:core:playback`
      has no library in it and a tree built from a copy of one goes stale the moment a
      download finishes; offering the whole shelf from a car needs the app to publish it, and
      that is not built.
      **Ticked for the two things this task names**, both of which exist: `PlaybackService`
      *is* a `MediaLibraryService` and `res/xml/automotive_app_desc.xml` declares `media`
      alone, with the `<meta-data>` on the `<application>` where Android looks for it. The
      whole-shelf tree above is not this task and is not owed by it. Same narrow reading as
      3.4: the assertions are instrumented and were re-compiled rather than re-run —
      `pnpm gradle :app:connectedDebugAndroidTest --tests "app.storyarc.PlayerBrowseTreeTest"`
      re-proves them.
- [~] 3.8 Both: interruption tests — audio taken and returned with the resume hint
      resumes; a pause the listener made is never undone; audio taken for good ends
      the session and records the position.
      **iOS done.** All three, over both source kinds, in `PlayerInterruptionTests` —
      plus the transitions themselves in `PlaybackTransitionTests`, which now run on the
      host in `pnpm test:ios` rather than in a suite no gate ran.
      **Android: the table is asserted and the wire is not connected, and that distinction
      matters.** `PlaybackSession.endingInterruption` is mutation-checked in
      `PlaybackSessionTest`, and `AudiobookSource.interrupted()` and
      `PlaybackCentre.endInterruption` exist — **with no caller on the audiobook path**.
      media3 handles audio focus itself (`setAudioAttributes(…, handleAudioFocus = true)`)
      and reports a focus loss as a plain `onIsPlayingChanged(false)`, which this code
      currently reads as *the listener paused*. So for a narrated book media3's own
      behaviour decides what a returning phone call does, and the rule the table exists to
      enforce — "a pause the listener made is never undone" — is **not** enforced yet.
      Read-aloud does connect it, through `ReadAloudController`'s own focus listener.
      Closing this means a focus listener beside media3's, or reading media3's own
      `Player.getPlaybackSuppressionReason`.
      **Android half now done — the second way, and no second focus request.** `PlaybackFocus`
      maps media3's three facts onto the shared table: `isPlaying`, `playWhenReady`, and the
      suppression reason. A transient loss suppresses and leaves `playWhenReady` **true**,
      which is the one signal a listener's pause does not carry; a loss for good clears
      `playWhenReady` with `PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS`, and the source
      hands that to `PlaybackCentre.endInterruption(false)` so the position is written before
      anything is stopped. Read from the player rather than remembered, so media3's callback
      order cannot change the answer. `PlayerInterruptionTest`, seven cases, four of them
      failing before the change; mutation-checked three ways.
      **One widening of the shared table, and iOS owes the same.**
      `PlaybackSession.pausedByListener` guarded on `isPlaying`, so a listener pausing *during*
      a call left the session marked as the interruption's — and the suppression then lifts by
      itself, because media3 gives the focus up, which would have started a book somebody had
      deliberately silenced. The guard is `isActive` now. iOS's `pausedByListener()` still
      guards on `isPlaying`.
- [~] 3.9 Both: route-change test — headphones removed pauses, and reconnecting does
      **not** resume.
      **iOS done.** `PlayerCentre.routeLost` records the pause as the *listener's*, which is
      the mechanism that makes "does not resume by itself" true rather than a promise —
      nothing the platform sends afterwards can undo a listener's pause. Asserted over both
      source kinds. `PlaybackAudioSession` acts only on `.oldDeviceUnavailable`, because
      the notification also fires when headphones are plugged *in*.
      **not** resume.
      **Android: `setHandleAudioBecomingNoisy(true)` is on the player**, which is media3's
      own answer to the first half. Nothing asserts either half, and the second half — that
      reconnecting does not resume — is media3's behaviour rather than a decision this code
      makes, so it is *believed* and not *checked*.
      **Android half now asserted, and the second half is this code's decision after all.**
      media3 names its own reason when the route goes noisy —
      `PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY` — and `PlaybackFocus` deliberately
      leaves it out of "audio lost for good", so it lands as the **listener's** pause. That is
      the same mechanism iOS's `PlayerCentre.routeLost` uses, and it is what makes "does not
      resume by itself" true rather than believed: nothing the platform sends afterwards
      undoes a listener's pause. `PlayerInterruptionTest`, one case. What is still believed
      rather than checked is that a real disconnection produces that reason; that needs
      headphones and a device.

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
      **Android half done.** Six cases in `:core:designsystem`, Robolectric with
      `GraphicsMode.NATIVE` for the reason `WhatsNewLayoutTest` sets out: every clause after
      the first is a **layout** claim, and legacy graphics measure a glyph at about a pixel
      wide, so a suite run that way passes against a bar that clips.
      The whole shell is composed rather than the bar alone, because every claim is about
      the *relationship* between the two and a bar composed on its own has none.
      Mutation-checked twice: putting the bar in a `Box` over the navigation control fails
      the displace/cover/resize case, and pinning the bar to 64 dp with one-line text fails
      the largest-text case. iOS half outstanding.
- [ ] 4.2 iOS: generalise `ReadAloudDock` in `tabViewBottomAccessory` to the shared
      session, so a narrated book and a spoken one produce the same bar.
      **Unblocked, and the first half is in.** The blocker recorded here — Readium 3.11.0's
      `Configuration` carries no rate and `AVTTSEngine.swift:131` is commented out upstream —
      is still true and is no longer a blocker: `design.md` decided the fourth way out, the
      `AVTTSEngineDelegate` upstream points the caller at two lines below the commented one.
      `Playback/SpeechRate.swift` is the mapping that decision needs, with `SpeechRateTests`
      pinning all three anchors. **Mutation-checked**: straightening it into the obvious
      single lerp puts 1× at `0.2` against the platform's own default of `0.5`, and the suite
      fails on exactly that.
      **iOS done — one bar, one session, and the second dock is deleted.** `SpokenVoice` is the
      `AVTTSEngineDelegate`, injected through `PublicationSpeechSynthesizer(engineFactory:)`;
      `SpokenSource` is the second `PlaybackSource`, so Readium's tokenisation, locators and
      highlight mapping are untouched. `ReadAloudCentre` is now only what a narrator has no
      equivalent of — the sentence on a page, and the reflowable position a voice writes — and
      `ReadAloudControls.swift` and `ReadAloudDock.swift` are **gone**: their lock screen,
      their interruption contract and their bar are `NowPlaying`, `PlaybackAudioSession` and
      `PlayerDock` now. `AppShell.PlaybackAccessory` has one branch left, the iOS 26.1
      availability one.
      **Where the bar's row goes is `CompactPlayer.wayBack`, and it asks the *file*.** A
      narrated audiobook has no screen behind it, so the row opens the player; a publication
      being read aloud has a reader, so the row goes there and the player gets a chevron of
      its own — neither `audio-playback`'s "a way to open the full player" nor `ebook-reader`'s
      "the compact bar is how the reader gets back to it" is traded away. Three cases in
      `CompactPlayerTests`, two of them driven over **both** source kinds, which is what pins
      that the engine does not decide it. New string `player.back`, in all four languages.
      **Photographed on a device**, in `docs/designs/screenshots/after-2026-09-01-ios-read-aloud/`:
      the shelf's four destinations at the height the no-session control shows them, one bar
      naming *Harbour Lights 01* and *Chapter 1*, and the full player with `1×` on it — the
      speed control the blocker said could not exist.
      **And the walk found a real crash on the way, which is the whole argument for taking the
      picture.** `EngineFactory` is a bare `() -> TTSEngine` and Readium builds its engine from
      a `lazy var` inside its own detached task; a closure written inline in a `@MainActor`
      method inherits that isolation, so the first utterance tripped
      `swift_task_checkIsolated` and the process died on `EXC_BREAKPOINT`. Nothing in `pnpm
      check` sees it — it is a runtime isolation check, and the app compiles clean. The fix is
      `SpokenVoice.makeEngine`, a `nonisolated` method reference.
      *The Android half of the compact bar is 4.3.*
- [x] 4.3 Android: hand-compose the row in `NavigationSuiteScaffold`'s `content`
      slot, full-width `surfaceContainer`, sharing the navigation bar's container
      colour. **Not** `BottomSheetScaffold` (no `bottomBar` slot, so the peek row
      would sit behind the navigation bar), **not** `HorizontalFloatingToolbar` and
      **not** `BottomAppBar` — both compile without complaint and both are ruled out
      by guidance. `design.md` records why, because the build will not.
      **Done, in the `navigationSuite` slot rather than the `content` slot** — and that is
      a correction to the plan, not a deviation from it. This app uses
      `NavigationSuiteScaffoldLayout`, whose `content` slot is *behind* the control; a bar
      there would cover the content's last row. Put in a `Column` above the control inside
      the navigation slot, the layout hands its measured height back to the content, which
      is what makes "does not cover" and "content still scrolls to its end" true together.
      The colour is asked of `ShortNavigationBarDefaults.containerColor` rather than named,
      so the two stay one assembly through a dynamic-colour change.
      **A gap, recorded rather than dressed up:** on a rail the slot is a column *beside*
      the content, so a tablet's bar sits over the rail rather than at the foot of the
      content pane. Moving it there is a change to the layout's own arrangement.
      **Closed.** The bar is drawn in the navigation slot only where the control is a row
      beneath the content; on a rail it goes into the content slot, in a column above the
      content's own weighted box — so it takes its height out of the content there exactly as
      the navigation slot's height does on a phone. `CompactPlayerRailTest` composes the shell
      at `w1024dp-h800dp` and measures both claims; before the change the bar spanned
      `0..1024 dp` from the top of the window with the rail's destinations at `0..96 dp`
      underneath it. Mutation-checked by restoring the single arrangement, which fails both.
      **Ticked against a run rather than against the entry**: eight host cases across
      `CompactPlayerTest` and `CompactPlayerRailTest` pass —
      `pnpm gradle :core:designsystem:testDebugUnitTest --tests "*CompactPlayer*"`.
      **One thing this task does not deliver, and it is `design.md`'s, not the spec's.** The
      *Where the two platforms deliberately differ* table gives Android's bar
      seek-back / play-pause / seek-forward, "the same three controls" as the notification's
      three slots. The shipped bar carries play/pause alone. `audio-playback` asks the bar
      only for "play, pause and a way to open the full player", so the spec is satisfied and
      the design is not. `CompactPlayerBar` is `:core:designsystem`'s and was held by another
      agent this wave; the two skip controls are a separate, small piece of work.
- [x] 4.4 Android: flat `LinearProgressIndicator` for the progress line.
      **Done**, in the compact bar and in the full player. Flat, not wavy: Material says a
      linear indicator "shouldn't be used in any elements smaller than 40dp" and cautions
      the wavy variant "may not be as visible" at small sizes. Null progress draws **no**
      line rather than an empty one, which is `audio-playback`'s "position without a total
      rather than inventing one" carried into a pixel.
      **Re-checked against both call sites, and the claim above is accurate.**
      `CompactPlayerBar` draws its line inside `progress?.let { … }`, and `AppShell` hands it
      null unless the part states a duration greater than zero; `PlayerScreen.Position` draws
      the whole-publication line only when `elapsedTotalMillis`, `statedTotalMillis` and a
      positive total are all present, and offers the scrub `Slider` only where the duration
      is `Known`. Both use the flat indicator; neither has a wavy one anywhere.
      **What is not true is that a test says so.** Neither the null case nor the flatness is
      asserted: `CompactPlayerTest` composes the bar with `progress = 0.4f` in every case, and
      no case composes it with null. The tick is a reading of two call sites, not a
      regression guard, and adding one belongs with `:core:designsystem`'s owner.
- [~] 4.4b Both: a publication with no cover gets the **same coverless treatment every other
      surface draws** — the title set as artwork — and so does the system's media controls.
      From a design review on 2026-09-01: `FullPlayerView.swift:89` draws
      `Image(systemName: "headphones")`, and its own comment claims that is "the same
      placeholder the library draws", which is **wrong** — the library draws `CoverlessWell`.
      The player is the one surface a listener stares at for an hour, and the lock screen
      inherits whatever it uses.
      **iOS done, and the misleading comment is gone with the glyph.** `PlayerArtwork` sets the
      title into the well, and `PlayerArtworkImage.png` renders **that same view** at 512 square
      for `MPMediaItemPropertyArtwork` — so the lock screen, Control Centre and a car display
      are given the picture the player draws rather than a second treatment that would have to
      be kept in step. `NowPlaying` caches it per book, because `publish()` runs four times a
      second while the clock moves and re-rendering that often would burn a battery redrawing
      something that cannot have changed; the cache is cleared with the session so a second book
      cannot start under the first's cover. Bytes rather than an image across the seam, because
      `Playback` has no SwiftUI and must not — `Formats` depends on it for `AudiobookPart`.
      **It is not `CoverlessWell` itself, and that is a compromise rather than a choice.** That
      view lives in `LibraryFeature`, and `Package.swift` records the rule importing it would
      break: "one module per screen area, and no feature depends on another". Its right home is
      `DesignSystem`, which `LibraryFeature`, `PlayerFeature` and the app target **all already
      depend on** — so the move needs no new module edge, only the file, its test, and one
      `import` in `App/OnDeviceShelf.swift`. It was not done here because two other agents held
      `LibraryFeature/**` and `DesignSystem/**` in the same wave. **Follow-up, and until it
      happens there are two views drawing one treatment** — which is the drift
      `CoverlessWell`'s own comment warns about at length.
      One deliberate difference while they are apart: `CoverlessWell` drops the title at an
      accessibility text size because a `headline` in a 146 pt grid cell holds part of one word,
      and this well is 320 pt and holds four lines of the largest size. The rendered image must
      draw it at any rate — a lock screen has no caption under it and no text size at all.
      **Not done: a real cover.** Nothing extracts embedded artwork from an audiobook yet (4.5),
      and a read-aloud EPUB that *has* a cover still gets the coverless well here, because
      loading it needs the library's cover cache. No case is worse than the glyph it replaced.
      **Photographed** at the default and largest text sizes —
      `docs/designs/screenshots/after-2026-09-01-ios-player-artwork/`, against
      `after-2026-09-01-ios-player/` as the before, which shows the glyph.
      The largest-text pair is the half a default-size picture cannot settle: the well holds the
      title whole at `AccessibilityXXXL`, which is why the player draws it unconditionally where
      `CoverlessWell` drops it. **The lock screen itself is not photographed** — XCUITest cannot
      reach a simulator's lock screen — but the render path is demonstrably exercised: it crashed
      the app the first time it ran (see the fix below).
      *The Android half is not started.*
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
      **Android: everything but the cover and the sleep timer.** `PlayerScreen` takes a
      `NowPlaying` and **not** a publication, which is how "opening it never restarts"
      is made structural rather than tested: a screen that took a publication would have
      to start something to draw anything.
      Photographed playing on `storyarc-j6`, light and dark, at the default and largest
      text sizes — `docs/captures/audiobooks/`.
      **Two things the screenshots caught that no unit test would have.** The first draft
      was a bare `Column` and the title sat under the status-bar clock; it is a `Scaffold`
      with a top bar now, like every other screen a reader comes back from. And the skip
      controls could not state their intervals with a glyph: Material ships `Replay5`,
      `Replay10` and `Replay30` and **no `Replay15`**, so a numbered icon would have drawn
      "10" on a control that moves fifteen. The number is text beside the arrow instead,
      which states the right interval and grows with the reader's text size.
      **Not done: the cover** (nothing extracts embedded artwork yet) **and the sleep
      timer** (5.3). iOS half outstanding.
- [~] 4.6 Both: a publication with no chapter markers lists its parts in playing
      order rather than showing an empty list.
      **iOS done, and there is no branch for it.** A source with no chapter markers reports
      one part rather than none — the rule lives in `AudiobookReader`, where the container is
      read — so `ChapterListView` never has an empty case to handle. What is left is naming
      an unnamed part, which `PlayerLabels.chapter` answers with its number and never with
      the file's name. *The Android half is not started.*
- [~] 4.7 Both: the publication page's primary action says what a **listener** does.
      **Not in this list until now, and it should have been.** The page's one button said
      *Read* for an audiobook. The routing was never wrong — `StoryArcApp.open(_:at:)` has
      asked `format.isAudio` since audiobooks landed and sends one to the player — so this was
      a promise the button did not keep, which is the kind of wrong nothing fails on.
      `publication-detail` makes the wording a requirement rather than a preference: one
      action, "labelled with *which* of read and continue will happen — so a screen-reader user
      learns the outcome before taking it rather than after".
      **iOS done.** `PrimaryAction` has four answers, `PrimaryActionTests` pins them, and one
      case asserts that reading and listening never borrow each other's words — which is what a
      single progress-first branch would have got wrong for a *started* audiobook. New strings
      `detail.listen` and `detail.continueListening` in all four languages. `AuditWalk`'s shared
      `opensAPublication` predicate matches all four wordings now; it matched two, and
      `PlayerScreenshotTests` looked for the literal *Read*. *The Android half is not started.*

> **Two things about §5 that a reader of this list needs before picking it up.**
>
> **A listener could set a sleep timer that never fired.** The sheets shipped on both
> platforms; on iOS `setSleepTimer` stored a countdown that nothing ticked and nothing faded.
> That was a control which was present and did not work, which `audio-playback` forbids by
> name — so 5.3 was closer to a defect than to a feature, and it got that way by the surfaces
> landing before the mechanism. **Fixed for a narrated book on both platforms**; see 5.3.
>
> **5.3's fade for a *voice* is a `design.md` decision nobody has made, and it is still
> unmade.** A narrated file can fade its volume. A synthesised voice cannot fade mid-sentence —
> it either finishes the sentence or stops speaking in the middle of a word, and
> `AVSpeechUtterance.volume` applies to the *next* utterance rather than the one being spoken.
> The iOS agent declined to invent an answer, which was right. What has changed is that the
> undecided half no longer blocks the decided one: `PlaybackSource.setVolume(_:)` has a
> documented no-op default, so a read-aloud timer stops the voice without a ramp rather than
> read-aloud having no sleep timer at all. **Decide the ramp in design.md before either
> platform tries to give a voice one.**

## 5. Controls

- [~] 5.1 Both: speed changes without changing pitch, states a number, is remembered
      per publication and offered as the series default. Range 0.5×–3×.
      **Android done.** The first three clauses were already true — media3 keeps the pitch
      when only the speed moves, `PlaybackSpeed.label` states the number, and `PlaybackSpeed`
      clamps to 0.5×–3×. What was missing is the remembering, and it is `PlaybackPreferences`:
      two scopes resolved publication-then-series, with the publication's own always winning,
      so adjusting volume two does not reach back and change volume one. A choice writes
      **both** entries, which is what makes a series a *default* rather than a second setting.
      Applied before the first sound rather than after it. Seven cases in
      `PlaybackPreferencesTest`; instrumented, because `SharedPreferences` is a framework
      component like every other store in the module.
      **iOS done, and the store is Android's rule with Android's cases.** The first three
      clauses were already true — `AVPlayer.rate` with `audioTimePitchAlgorithm = .timeDomain`
      keeps the pitch, `PlaybackSpeed` clamps to 0.5×–3×, and the number is on the control's
      face and in its announced value. What was missing is the remembering, and the two hooks
      that existed for it — `PlayerCentre.onRecallSpeed` and `onRememberSpeed` — had **no
      caller anywhere in the app**, so every book started at 1× however often a listener had
      changed it. `Persistence/PlaybackPreferences.swift` is the same two scopes resolved
      publication-then-series, the publication's own always winning, and a choice writing both
      entries. Nine cases in `PlaybackPreferencesTests`, seven of them Android's own.
      **Two cases Android's store does not have, because `UserDefaults` differs from
      `SharedPreferences` in exactly one dangerous way**: it answers `0` for a key it has never
      seen with no way to pass a sentinel, so a stored zero is not believed — otherwise every
      untouched book would start *stopped*, which is the one value a speed may never be. And a
      rate outside the offered range comes back as stored rather than being rewritten: a store
      is not where a range is validated, and `PlaybackSpeed(_:)` is what clamps it.
      The wire is `StoryArcApp.wirePlayerSpeed`, called from the app's `init` rather than beside
      the session's other wiring — **which is the one thing here that is not a mirror**.
      `wirePlayerRecording()` is called from `listen(to:at:)`, so a listener who only ever read
      a book aloud would never have run it, and read-aloud begins its session from
      `ReadAloudCentre.begin` inside `StoryArcEpub`, which cannot see the app target. One call
      at start-up is the only place that covers a session begun from either source.
      Applied before the first sound: `begin(_:source:)` asks the hook and calls `setSpeed`
      before `play`, and `NarratedSource.setSpeed` on a paused player records the number and
      applies it on the next `play` rather than starting the audio.
- [x] 5.2 Both: skip states its interval on the control, is configurable, and
      crossing a chapter boundary continues rather than stopping. Defaults 15 s back
      and 30 s forward — a **product decision**, recorded as one; media3's own
      defaults (5 s / 15 s) are wrong for spoken word.
      **Android done, and the boundary clause was quietly false before this.**
      `PlaybackHost.skip` added the interval to the offset, clamped at zero, and carried a
      comment saying the hard case was free: "for a single file that is free … for a folder
      media3 carries the seek into the next item itself". **media3 does not.**
      `BasePlayer.seekToOffset`, read out of the shipped `media3-common-1.11.0.aar` with
      `javap -c` on 2026-09-02, is `min(getCurrentPosition() + offset, getDuration())` then
      `max(…, 0)` then `seekToCurrentItem(…)` — the current *item*, clamped at both of its
      own ends. So skipping back five seconds into chapter two landed at the start of chapter
      two, which is the stop this task forbids by name, and nothing in a build said so.
      `PlaybackTimeline` is the fix and it is iOS's, mirrored case for case: out to whole-book
      time, add, and back. Fourteen cases, mutation-checked — restoring the clamp fails four.
      **A folder had no part lengths at all, and three other features were waiting on that.**
      The format layer deliberately does not measure them (`OpenedAudiobook`: an extractor per
      file would cost a five-hundred-book library a decode pass per scan) and media3 has no
      per-item duration API — `getDuration()` answers for the item playing and the rest are on
      a `Timeline`'s windows. `AudiobookSource.adoptDurations` takes them from
      `onTimelineChanged`, which is what makes the carry possible *and* gives a folder its
      whole-publication progress line, its elapsed/total pair and *end of chapter* on the
      sleep timer. Eleven cases in `AudiobookSkipTest`, mutation-checked twice.
      **Configurable, and the shade agrees with the app about it.** `SkipIntervals` is the
      pair (iOS's field for field), `SkipPreferences` stores it beside `PlaybackMemory` and for
      its reason — the service has no scope and no database — and the label is formatted from
      the stored number in all four languages rather than written out. The choice is on the
      player, where the speed slider and the sleep timer already are.
      **The notification's two buttons had to stop being player commands.**
      `COMMAND_SEEK_BACK`/`_FORWARD` are answered by media3 itself, with the clamp above, so
      the shade would have stopped at a folder's boundary while the app carried across it.
      They are session commands now, handled in `onCustomCommand` through the same
      `PlaybackTimeline`. The player commands stay declared, because a car's voice command and
      an Assistant send those and they are not ours to redirect — that one path still clamps,
      at the right interval, and it is the honest remainder.
      **Four intervals, and the set is media3's rather than a fifth product decision.**
      `CommandButton` draws a numbered glyph for exactly 5, 10, 15 and 30 seconds each way, so
      anything else leaves the notification with a lying figure or a bare arrow. Both defaults
      are in the set and neither was re-litigated.
      **Not exercised on a device.** Everything above is asserted by host tests —
      `pnpm gradle :core:playback:testDebugUnitTest` and `:app:testDebugUnitTest` — and nothing
      in the notification, the lock screen or a car has been pressed. The emulator was held by
      another agent. Owed: `pnpm capture:android Player --out shot.png` at both text sizes and
      both appearances, and a press of each shade button on a folder audiobook at a file
      boundary.
      *The iOS half is not started, and it is smaller than it looks:* `SkipIntervals`,
      `SkipDirection`, `SkipUnit`, `PlayerCentre.skipIntervals` and
      `PlaybackTimeline.skip(_:by:from:)` all exist, and `PlayerLabels.skip` already states the
      configured interval. What is missing there is a store and a control — `skipIntervals` has
      **no setter anywhere in the app**, so the value is configurable in the type and not by a
      listener.
      **iOS's half landed 2026-09-03, and it was the smaller half in code and the larger one
      in consequence.** `SkipIntervals`, `SkipDirection`, `SkipUnit`, `PlayerCentre.skipIntervals`
      and `PlaybackTimeline.skip` all existed; `PlayerLabels.skip` already stated the configured
      interval. **What was missing was a setter — `skipIntervals` was written by nothing anywhere
      in the app**, so every listener got the defaults for ever and this task's *configurable*
      clause was unmet with nothing failing. That is the shape of gap a tick hides.
      `SkipPreferences` mirrors Android's store case for case, including the one decision that
      matters: **a half-written pair reads as the defaults, not as a control that moves nothing**.
      Zero is what an unwritten key answers *and* the one value a skip may never have, and
      neither `UserDefaults` nor `SharedPreferences` offers a sentinel between them — so the pair
      is read as a pair. Seven host cases.
      `SkipIntervalsSheet` is the control, two sections because back and forward are genuinely
      different distances, one store because to a listener they are one setting. **The offered set
      is stated in `SkipIntervals.offered` rather than in the view, and it is Android's** — a
      listener who sets ten seconds on a phone and finds no ten on a tablet is a listener the set
      has drifted under.
      **It is not drawn where a skip cannot mean seconds.** A synthesised voice skips a
      *sentence*; `SkipUnit` carries that and `audio-playback`'s "works, or is absent" says the
      control is not drawn rather than drawn and inert.
      **And the lock screen had to be told.** `MPRemoteCommandCenter.preferredIntervals` is
      published once when the commands are wired, so without `skipIntervalsChanged` the player
      would say ten seconds while the lock screen, Control Centre and a car display went on
      saying fifteen — three surfaces this task requires the interval to be stated on.
      `PlayerCentre.swift` crossed SwiftLint's 400-line cap, so the setter is in `PlayerSkip.swift`
      beside `PlayerSleep.swift`, which took the same seam for the same reason.
      **Captures owed**: the sheet and the control, light and dark, default and largest text. Both
      devices were sweeping every screen when this landed.
- [~] 5.3 Both: sleep timer offers durations **and end-of-chapter**, shows the
      remaining time, fades out rather than cutting, and records a position slightly
      before where the fade ended.
      **Android done, and the model carries the weight.** `SleepTimer` holds both cases as one
      remaining time, and the difference is only in what moves it: a duration counts itself
      down, *end of chapter* is re-read from where the audio has reached — so a listener who
      skips forward inside the chapter has moved the end nearer rather than being stopped in
      the middle of the next one. Thirteen cases in `SleepTimerTest`.
      **End of chapter is absent, not inert, where nothing knows how long the chapter is** —
      `SleepTimer.of` answers null and the chip is not drawn, which is `audio-playback`'s
      "works, or is absent" applied to the one control that cannot always be honoured.
      The fade is a straight ramp over the last thirty seconds, applied to the controller's
      volume by a half-second tick that holds while the book is paused; and the rewind is
      **the same thirty seconds**, which is the argument for that number: the fade is exactly
      the stretch a listener stopped taking in, so starting again where it began is starting
      at the last thing they properly heard. Recorded by the host when it elapses, because the
      next tick that would have written it only runs while something is playing.
      Both the fade length and the five offered durations are **product decisions**, recorded
      as such; neither Material nor Apple publishes a set.
      **iOS done for a narrated book, and it was a defect rather than a gap.** The sheets had
      shipped and nothing ticked them: `setSleepTimer` stored a countdown, `sleepTimerElapsed`
      knew what to do with one, and the only caller of the second in the whole tree was a test.
      A listener set *Sleep in 30 minutes*, the remaining time never moved, and the audio never
      stopped — which is a control that is present and refusing, forbidden by name.
      The model is `SleepCountdown` in `Sources/Playback/SleepTimer.swift`, mirrored on
      Android's case for case: one remaining time for both kinds, a duration counting itself
      down, *end of chapter* re-read from where the audio has reached, a straight ramp over the
      last thirty seconds, and a rewind that is **the same thirty seconds**. Nineteen cases in
      `SleepTimerTests`, thirteen more through the session in `SleepTimerRunningTests`; the
      paused hold, the ramp and the end-of-chapter re-read are each mutation-checked.
      The fade reaches `AVPlayer.volume` through a new `PlaybackSource.setVolume(_:)`, and the
      **player's** volume rather than the item's — a folder audiobook swaps items at every part
      boundary and a gain set on the item would jump back to full when a fade crossed one.
      **The half-second clock is the platform's, not the centre's**, which is where iOS's seam
      differs from Android's: `PlaybackPlatform.sleepTimerChanged(isRunning:)` owns a `Task`,
      and `platform` is `nil` in every host test — so the whole of the behaviour is asserted by
      calling `tickSleepTimer(by:)` rather than by waiting out a thirty-second fade in real
      time. `PlayerCentre.swift` crossed SwiftLint's 400-line cap on the way, so the timer is
      its own extension file, `PlayerSleep.swift`, as the position already is.
      End of chapter is absent on iOS too: `SleepTimerSheet` asks
      `PlayerCentre.canSleepAtEndOfChapter` and does not draw the row a read-aloud session
      could not honour. The remaining time is on the face of the control and **moves**, and the
      control now announces a name *and* a value — it announced only the value, which is the
      defect the speed button beside it was already fixed for.
      **Two numbers changed to Android's, and that is deliberate**: the fade was 5 s and the
      rewind 10 s, and the durations offered a sixth stop at 10 minutes. Both were iOS
      inventions against a product decision recorded for the other platform, and
      `SleepTimerTests` now pins them to Android's — a listener falling asleep in a different
      place on the two platforms is the divergence this task exists to prevent.
      **Captured, and the capture is one frame where the requirement wants two — stated rather
      than dressed up as an exception.**
      `docs/designs/screenshots/after-2026-09-01-ios-player-artwork/ios-sleep-timer-set.png` shows
      `5:00 left` on the control, and `testCaptureSleepTimerSet` asserts that string is the
      control's announced *value* while *Sleep timer* stays its name. A single frame cannot tell
      the fix from the defect, so what proves the moving is `SleepTimerRunningTests` rather than a
      picture.
      **The second frame ran into a pre-existing defect, and finding it is worth more than the
      frame was.** The countdown moves only while the book plays, and **pressing any transport
      control inside the full player dismisses the full player**: `PlayerDock` hosts the player's
      `.sheet` on a view inside `if let bar = centre.compact`, so the moment `CompactPlayer`'s
      value changes — which pressing play does, and which crossing a chapter does — the sheet's
      host is rebuilt and the presentation is torn down. A skip-back tap and a chapter-row tap each
      left the publication page on screen with the compact bar still playing, and **the same run
      against the pre-§3.2 `FullPlayerView` failed identically**, which is what proves it predates
      the Close pill's removal.
      **Fixed on 2026-09-01.** The presentation moved to the shell's `TabView`, which exists for
      as long as the app does, through a `playerSheet(isPresented:centre:)` modifier in
      `PlayerFeature`. Wrapping the dock's `if let` in a container would have fixed the teardown
      and broken something else: `audio-playback` requires the compact bar to be "absent rather
      than present and empty", so the dock's body must keep producing *nothing* when there is
      nothing to draw — and a host that is stable cannot also be a host that sometimes does not
      exist. The modifier owns the one case the old accident handled for free: the player closes
      when the **session** ends, on `isRunning` and not `isPlaying`, because dismissing on a pause
      would be the original defect rebuilt by hand.
      `PlayerAuditTests.testATransportTapDoesNotDismissThePlayer` is the regression test, and it
      was **mutation-checked against the whole pre-fix shape** — the sheet put back inside the dock
      and the modifier removed from the shell — where it fails with its own message.
      **The first attempt at this was parked for a day by its own mutation evidence, which is the
      lesson worth keeping.** The parked branch left `PlayerDock`'s `.sheet` in place under a
      `// MUTATION: the defect, put back on purpose` comment, so the committed tree had *two*
      sheets bound to one binding, and a capture walk failed in a way that looked like a genuine
      SwiftUI limitation. Its own note had even recorded that binding two sheets to one binding
      "failed for a different reason" — and then shipped exactly that. **Undo a mutation before
      committing, and never leave one behind a comment that explains it**; a comment does not
      un-break the build it is sitting in.
      **Still `[~]`, and the reason is not a platform**: a *synthesised voice* cannot fade.
      `AVSpeechUtterance.volume` applies to the next utterance and not the one being spoken, so
      `setVolume` has a documented no-op default and a read-aloud timer stops the voice without
      a ramp. That is the `design.md` decision the note above §5 says nobody has made — it is
      still unmade, and the default is what keeps the undecided half from blocking the decided
      one. Android has the same gap for the same reason: its read-aloud host is not a
      `PlayerSource` yet, so nothing there fades a voice either.
- [x] 5.4 Android: declare `COMMAND_SEEK_TO_PREVIOUS`/`NEXT` so the notification's
      three compact slots carry seek-back / play-pause / seek-forward.
      **Done.** All four are added in `onConnect`: the two chapter moves a head unit uses
      and the two second-counts the notification carries. The compact row's outer slots are
      `COMMAND_SEEK_BACK` and `COMMAND_SEEK_FORWARD` at 15 s and 30 s — media3's own
      defaults, 5 s and 15 s, are set aside on the `ExoPlayer.Builder`, and that is a
      **product decision** with no guideline behind it.

## 6. Playback outlives the publication

- [~] 6.1 Both: leaving the reader while playing does not stop it, and the compact
      bar is the one action back.
      **Android: true for a narrated audiobook, and photographed.** The audio is the
      service's, not a screen's, so leaving the player leaves it playing;
      `docs/captures/audiobooks/03-library-with-bar-light.png` is the library with the book
      still going and the bar carrying it, against
      `01-library-no-bar-light.png` — the same screen, the same device, minutes apart.
      The bar's whole-row action opens the player and is the one action back.
      **Not done: read-aloud does not drive this player yet.** It has its own host and its
      own notification; the session table is now shared (1.1) and the source interface is
      where the two meet, but nothing has been rewired. That is the honest state.
      No test asserts the outliving — it is a process fact, and proving it needs the
      instrumented pass §9 still owes.
      **iOS done, and photographed for both sources.** Read-aloud drives this player now (4.2),
      so leaving the reader leaves the voice running and the shared bar carries it; the bar's
      row is *Back to the book* for a spoken session, which is the one action back.
      `after-2026-09-01-ios-read-aloud/ios-read-aloud-compact-bar.png` is the reader closed and
      the voice still going, against `after-2026-09-01-ios-player/ios-library-nothing-playing.png`
      for the four destinations at the same height. The narrated half is the same folder's
      `ios-compact-player.png`.
- [~] 6.2 Both: returning to a read-aloud session resumes at the sentence being
      spoken **then**, not where the reader left.
      **iOS: written, and blocked from being seen by a defect older than this change.** The
      path is `SpokenSource.reached` → `ReadAloudCentre.spoken` → `redrawSpokenSentence()`,
      reached through `SessionHandover.adopt` in `prepareReadAloud`; the voice keeps its cursor
      up to date with no reader on screen, so returning draws the sentence it is on rather
      than the locator the reader left. That is the same mechanism
      `read-aloud-beyond-the-reader` shipped, now hanging off the shared session.
      **The starting half is exercised on a device** — `UITests/ReadAloudPlayerTests` starts
      the voice, leaves the reader, and photographs the bar carrying it, which is §4.2's proof
      and §6.1's. **The returning half is not.** Going back in and asserting *which sentence*
      is drawn needs the walk to read the decoration inside a `WKWebView`, which XCUITest does
      not expose, so what is left is the code path and the reasoning above. Saying it is
      photographed would be saying more than the picture shows.
      **A false lead worth recording, because it cost an hour and reads exactly like a
      defect.** The read-aloud row is the last row of the reader's menu and sits below the fold
      on an iPhone; a SwiftUI `List` is lazy, so a row that has never been on screen is in no
      accessibility tree, and `app.buttons["Read aloud"]` came back empty. That is
      indistinguishable from `canReadAloud == false`, which `ebook-reader` genuinely allows for
      a publication with nothing to say. Ruled out by forcing the row to render
      unconditionally and finding the query still empty — the app was never the problem, the
      query was. The walk swipes now.
- [~] 6.3 Both: reaching the end withdraws the highlight, dismisses the media
      controls and removes the compact bar.
      **Android: written, and seen happening.** `PlaybackCentre.publish` drops the surface
      the moment a source goes idle, and `AudiobookSource` reports `STATE_ENDED` as a
      stopped session. Observed by accident and worth recording: the corpus's
      `chaptered.m4b` is six seconds long, so the first run played it out before the screen
      could be photographed — logcat shows `PLAYING(3), position=5903` then `STOPPED(1)`,
      and the player drew "Nothing is playing." That is the requirement, arrived at the
      wrong way round. `PlaybackSessionTest` pins the model half. iOS half outstanding.

## 7. Position

- [ ] 7.1 Both: an audiobook's position is an offset in a named part, survives close,
      restart and re-download, and resolves through content identity like every other
      position.
      **Android: the shape exists and nothing writes it.** `PlaybackPosition` is an offset
      in a part index, and `PlaybackHost.recordPosition` is the hook a store would hang
      off — **it is never set**, so closing an audiobook loses the place. That also leaves
      3.6's resumption answering from a position nothing updates. `reading-progress` needs
      a fourth `ReadingPosition` case, or `Reflowable` reused with a time-derived fraction;
      neither has been decided and neither should be decided in an implementation pass.
      **iOS half done.** `ReadingPosition.listening(part:partCount:offset:of:)` — the four
      fields Android's `Listening` has, for the same reasons, including `partCount`, which
      `design.md`'s three-field signature cannot derive and `fraction` cannot answer without.
      `ListeningPositionTests` pins the fraction table, the clamping, that it `matches` a page
      and a progression on the same scale, and that a record written before the case existed
      still decodes. `PlayerCentre.position(at:)` builds it; `ReachedListening` carries it to
      the app; `StoryArcApp.wirePlayerRecording` saves it — so closing an audiobook keeps the
      place. Six cases in `ListeningRecordTests`, two mutation-checked (not resetting
      `hasReachedTheEnd` on a new book, and inventing a zero duration for a voice).
      **No migration on iOS, and that is a real platform difference rather than an oversight:**
      the store keeps `positionData` as JSON of the enum, so a new case needs no schema change
      where Android's Room store needed four columns and `MIGRATION_2_3`.
      **One thing this cost that nothing warns about.** `StoryArcCore` is not built with
      library evolution, so its enum layout is baked into every client — and adding a case left
      an incrementally-built `StoryArcCoreTests` comparing the *old* layout. `ProgressMergeTests`
      then failed on two values that printed identically, and the whole suite took `SIGSEGV`.
      Neither is a defect and neither is flaky: `swift package clean` fixes both. Worth knowing
      before spending an hour on a compiler bug that is not there.
> **7.2 and 7.3 each appeared twice, and the duplication had eaten text.** Two pairs of
> entries carried the same heading: 7.2's first copy had lost its second line — "returning
> never offers a choice of two" — under a pasted Android body, and 7.3's first copy carried an
> Android paragraph that is about 7.2's subject, one position and no choice of two, not about
> finishing. Merged below with nothing dropped: each heading is whole again, the misfiled
> paragraph sits under 7.2 where it answers the requirement, and one stale "iOS half
> outstanding" is gone because the iOS paragraph it preceded is now in the same entry.
> **8.2 and 8.3 carry the identical defect** — duplicated entries, and 8.3's first copy holds
> a body about the skip and speed controls that belongs to 8.1/8.2. Left alone here: §8 is
> another agent's and both entries are already `[x]`.

- [~] 7.2 Both: a publication both read and listened to has **one** position, and
      returning never offers a choice of two.
      **Android: the position now exists, is stored, and survives.** `design.md` decided it
      on 2026-09-01 and `ReadingPosition.Listening(part, partCount, offsetMillis, ofMillis)`
      is it — a **third** case beside `Page` and `Reflowable`, not a fourth: there are two.
      `fraction` answers with the part when `ofMillis` is null, which is the read-aloud case,
      and refines it by the offset when a duration is known; `matches` keeps working because
      it compares fractions and this lands on the same 0…1 scale. `ListeningPositionTest`,
      fifteen cases, including that a listening position matches the bare fraction the store
      keeps a synced position as — the row of ADR-0006 that case equality once made
      unreachable for `Page`.
      **`partCount` is in the signature and is not in `design.md`'s**, which names three
      fields and then asks `fraction` for "the part index over the part count". That count is
      not derivable from the other three. `Page` carries its `total` for the same reason.
      **The store keeps it in columns, not JSON.** `design.md`'s note about a record decoding
      unchanged is iOS's — `StoryArcCore` keeps `positionData` as JSON of the enum; Android's
      Room store has always used columns. Four new ones, `MIGRATION_2_3`, and `part_index`
      defaulting to **-1** is the whole of the compatibility story: it is the discriminator,
      so a default of 0 would read every comic already on a phone back as an audiobook at
      chapter zero. `ProgressMigrationTest` upgrades a hand-written version-2 table and pins
      that; mutation-checked by setting the default to 0, which fails it. Four more cases in
      `ProgressStoreTest` pin the round trip, the absent duration, and one position per
      publication; mutation-checked twice.
      **And now wired.** `PlayingBook` sets `PlaybackHost.recordPosition` and starts a book
      *from* what the store remembers, and `ListenedPosition` is the pure mapping between a
      `PlaybackPosition` and a `ReadingPosition` — eleven cases in `ListenedPositionTest`,
      including that an `Estimated` part length is stored as **no** length rather than as a
      number. Written on a fifteen-second tick as well as at the end, because ADR-0006 makes
      the local store authoritative and an app killed in the background is the ordinary way a
      phone closes one; a book has no page turns to hang that on. The writer's scope is the
      process's, not an activity's — the audio outlives every screen and so must the writing.
      **Android: one position, by construction, and asserted.** There is one `position` field
      on `ReadingProgress` and one row in the store, so the second kind of position replaces
      the first rather than sitting beside it — `ProgressStoreTest` pins that a listening
      write over a reflowable record leaves one row holding the listening one. The "never
      offers a choice" half is `ListenedPosition.resume` answering **null** for a position
      left by reading: the book opens at its beginning, with no prompt, because there is no
      second place to offer. *(This paragraph was filed under 7.3 by the duplication above;
      it answers 7.2's requirement, so it is here.)*
      **iOS half done, and it is a guard rather than a feature.** `wirePlayerRecording` writes a
      listening position **only** for a publication whose format `isAudio`. A publication read
      aloud is still a reflowable publication, and what the voice writes for it is the
      reflowable position the eye would have written — `SpokenPosition`, unchanged. Without
      that guard the player would have written a second, time-shaped position for the same
      book, which is exactly the "choice of two places" `reading-progress` forbids.
- [~] 7.3 Both: finishing by listening marks the publication finished and makes the
      same end-of-publication offers as finishing a comic.
      **iOS: the marking is done; the offers are not checked.** `ReachedListening.isFinished`
      is true when the *source ran out*, which is the exact fact a comic has when it is on its
      last page. A threshold on the fraction was the obvious alternative and is wrong: the
      clock ticks four times a second, so the last place reported before the end of the
      corpus's six-second fixture is a fraction of about 0.96 — a book played to its end and
      never marked finished. Asserted over both source kinds and mutation-checked.
      **The end-of-publication offers are `FinishedCleanup`'s and the next-in-series shelf's**,
      and neither was traced from a finished audiobook. They hang off the same `isFinished` flag
      a comic sets, so the reasoning is that they follow; nobody watched them.
      **Android: the marking is done.** `ListenedPosition.isFinished` uses the fraction and
      the same 0.999 threshold `EpubReaderViewModel` uses, so the end of the last part marks
      the publication finished and the *start* of it does not; finished is sticky in the
      store, as it is for a comic. A source with no known duration never claims the end,
      which is the point of `PlaybackDuration.Estimated` carried through to the store.
      **Not done: the offers.** The next in the series and the delete-the-download prompt are
      the reader's end-of-publication surface, and the player has none. iOS half outstanding.

> **§8.4's compact-bar half was a spec-versus-platform conflict. `/opsx:update` settled it on
> 2026-09-01 and the requirement was what changed.** `audio-playback` asked the bar to "grow to
> fit its text rather than truncating the chapter to one word". iOS cannot: the height of
> `tabViewBottomAccessory` is the **system's**, so removing `PlayerDock`'s line limit trades a
> truncated title for a clipped one — strictly worse, and it would have made the audit's
> `Text clipped` finding permanent.
>
> The delta now gives the compact bar its own scenario, stating the outcome rather than the
> mechanism, and asks for growth **where the app owns the height**. Android grows and asserts
> it; iOS cuts honestly, announces the untruncated title, and opens onto a surface with room.
> The remaining iOS work is the accessibility label, and it is ordinary work now — see §8.4.

## 8. Accessibility

- [~] 8.1 Both: every control announced with a name and, where it has one, its value
      — speed, skip interval, remaining sleep time, position.
      **Android: names and values are on the controls that exist.** The skip controls are
      one element each, named "Back 15 seconds" / "Forward 30 seconds" rather than read out
      as an arrow and a loose number; the speed slider's state description is the number
      itself, because a screen reader saying "62 per cent" of a speed control tells a
      listener nothing they can act on. **No sleep timer exists to announce** (5.3).
      **Not verified by an accessibility scan** — `pnpm a11y:android` has no player route,
      and adding one is part of §9.
      **iOS: the names and values exist, and are now under the platform's own audit.**
      `PlayerLabels` decides each announcement and `PlayerLabelsTests` pins it; what was
      missing was a tool rather than a reading. `UITests/PlayerAuditTests` walks to six
      surfaces — the shelf with the bar, the player at the default and the largest text size,
      and each of the three sheets — and calls `performAccessibilityAudit` on each. It
      **reports rather than fails**, for the reason `AuditWalk.reportOnly` sets out: one
      expectation broad enough to absorb the known glass-chrome contrast findings is broad
      enough to absorb a navigation failure silently, and it did exactly that once.
      **Run on the iPhone 17 Pro simulator, 2026-09-01. No unlabelled control anywhere**,
      which is the finding §8.1 is about. What did come back, with the element each names:
      *Player* — one *Potentially inaccessible text*, no element reported, which is the cover
      placeholder (already `accessibilityHidden`). *Chapters* — two of the same.
      *Player at AccessibilityXXXL* — **nothing at all**.
      **And most of the rest are not the player's**, which is why the element matters: the
      three *Contrast failed* findings on each sheet are `Continue listening`,
      `On this device, readable with no network` and `Sea Room` — the **publication page
      behind** the sheet, the same class of finding `AccessibilityAuditTests` already records
      there. Reading them as sheet findings would have sent the next reader to the wrong file.
      One finding **is** the bar's, and it is real — see 8.4.
- [x] 8.2 Both. **Android half.** A `Slider` is already an adjustable; what it announces
      by default is a percentage, and the `stateDescription` replaces that with
      "0:42 of 5:00".
      **iOS half.** `FullPlayerView`'s scrub `Slider` is an adjustable by construction, and its
      `accessibilityValue` is `PlayerLabels.spokenTime` — *"1 minute, 10 seconds"*, built from
      `Duration.formatted(.units)` so the words are the platform's in every language. The face
      of the control keeps `0:09`, which is right in print and wrong read aloud; the two forms
      are separate functions for exactly that reason and `PlayerLabelsTests` pins both. The two
      ends of the slider are `accessibilityHidden`, so the time is announced once rather than
      three times.
- [x] 8.3 Both. **Android half.** `mergeDescendants` makes the bar one element;
      **Now asserted in a composition, and the sleep timer exists to announce.**
      `PlayerSemanticsTest` reads the rendered semantics rather than the source: the skip
      controls are one element each named "Back 15 seconds" / "Forward 30 seconds", the speed
      slider's state description is `1.4×` and not a percentage, and a running sleep timer
      states "Sleep in 12:34". Robolectric with `GraphicsMode.NATIVE`, for `CompactPlayerTest`'s
      reason: legacy graphics measure a glyph at about a pixel wide and would pass against a
      control drawn off the window. Still not verified by an accessibility *scan*.
- [x] 8.2 Both — Android half. A `Slider` is already an adjustable; what it announces
      by default is a percentage, and the `stateDescription` replaces that with
      "0:42 of 5:00". iOS half outstanding.
      **And now asserted rather than described** — `PlayerSemanticsTest` finds a node whose
      state description is exactly that, in a real composition.
- [x] 8.3 Both — Android half. `mergeDescendants` makes the bar one element;
      `CustomAccessibilityAction`s keep play/pause and open reachable separately. Not
      stealing focus is what *not asking for it* is — nothing in the bar requests focus,
      which is the whole of the requirement and is why there is no code to point at.
      **iOS half.** `.accessibilityElement(children: .contain)` with a container label of *Now
      playing*, which is the platform's own shape for "one element with its actions reachable
      separately" — a container plus addressable children rather than Android's merge plus
      custom actions. Each control is separately named: the row is *Back to the book* or *Open
      the player* by `CompactPlayer.wayBack`, and play/pause and stop carry their own labels.
      Not stealing focus is the same absence it is on Android: nothing in `PlayerDock` is
      `accessibilityFocused` and nothing posts a screen-changed announcement, which
      `PlayerDock`'s own header states as a rule so a later edit has to argue with it.
- [~] 8.4 Both: at the largest accessibility text size the transport stays usable, any cut
      to the text is honest, and text the bar cannot show is still reachable in full.
      **Android: asserted and photographed.** `CompactPlayerTest` measures that the bar
      grows rather than pinning, mutation-checked. The player was photographed at
      `font_scale 2.0` in dark — `06-player-dark-2x.png` — with the whole transport on
      screen and every stated value readable; the chapter list is what scrolls away, which
      is why the transport sits above it. The device was put back to 1.0 afterwards.
      **iOS: the player half is done and the bar half is a conflict the plan has to settle.**
      The player was photographed at `AccessibilityXXXL` — `after-2026-09-01-ios-player/`
      `ios-full-player-largest-text.png` — and the audit at that size returns **no findings at
      all**, which is the strongest form of "nothing becomes unreachable".
      **The compact bar truncates, and the spec used to say it must not.** `audio-playback`
      asked that "the compact bar grows to fit its text rather than truncating the chapter to
      one word". `PlayerDock.wayIn` is `.lineLimit(1).truncationMode(.tail)` on purpose and says
      so in a comment — and the audit caught it: *Text clipped*, on `StaticText … label: 'Sea
      Room'` at the bar's own coordinates. The comment and the requirement disagreed, and it
      turned out to be the requirement that was wrong; see below.
      **`/opsx:update` ran on 2026-09-01 and the requirement was the thing that was wrong.**
      The height of `tabViewBottomAccessory` is the system's, not this app's; removing the line
      limit inside a slot whose height we do not set does not make the bar taller, it trades a
      *truncated* title — honest and readable — for a *clipped* one. Satisfying the old wording
      would have made the `Text clipped` finding permanent instead of fixing it. Android's bar
      is hand-composed and measures itself, which is why `CompactPlayerTest` can assert growth
      there and nothing can assert it here.
      **So the delta now splits the bar into its own scenario** and asks for the outcome rather
      than the mechanism: the transport stays usable and above the minimum touch target, the cut
      is at a word and marked as cut, text the bar cannot show is announced in full and shown in
      full on the player it opens onto, and growth is required **where the app owns the height**.
      Android satisfies the growth clause; iOS satisfies the honest-cut and reachable-in-full
      clauses. Neither is excused a clause — they satisfy different ones, and which is decided
      by who owns the height.
      **Still outstanding on iOS**, and now implementable: `PlayerDock.wayIn` keeps its
      `.lineLimit(1).truncationMode(.tail)` and must additionally carry the **untruncated**
      title in its accessibility label, so what the bar cannot draw is still announced. Assert
      it, and re-run the audit to confirm `Text clipped` is what remains rather than something
      new. The comment at that call site should cite the scenario instead of arguing with it.
      **The screenshot is now a test too.** `PlayerSemanticsTest` composes the player at font
      scale 2 and asserts all three transport controls and the chapter are still displayed —
      which a photograph proves for one build and a test proves for every one after it. The
      sleep options wrap in a `FlowRow` for the same requirement: five durations and a chapter
      do not fit across a phone at that size.

## 9. Docs and close-out

- [~] 9.1 Module `README`s for the new player modules on both platforms.
      **Android done**, as a side effect of §5.2 rather than as this task: `:core:playback`
      had none and now carries one — files, public API, the two preferences files and why
      they are not in `:core:persistence`, the data flow across the service boundary, and
      which claims rest on host tests rather than on anything that has been heard.
      **Two things this does not cover.** iOS's `Playback` target has no `README`, and
      `apps/android/README.md`'s own module table is three modules old: it lists four, and
      the tree holds eight `core` modules and four `feature` ones. `:core:playback`,
      `:core:format`, `:core:persistence`, `:core:catalogue`, `:core:kavita`, `:core:smb`,
      `:feature:epubreader`, `:feature:reader` and `:feature:settings` are all missing from
      it. Left alone here because two other agents held rows in that table this wave.
- [ ] 9.2 Update `docs/openspec/STATUS.md` and the format table in the docs.
- [ ] 9.3 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 9.4 `agent-compass openspec-guard . --strict`.
- [ ] 9.5 `/opsx:verify audiobooks-and-playback`, then `/opsx:sync`.
