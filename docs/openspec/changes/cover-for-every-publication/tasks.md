A ticked box here means: the code exists on every platform the task names, a test that fails
without it landed, and any frame the change needs exists. A tick does **not** mean a person
watched it on a device.

## 1. The rungs that need no network

- [x] 1.1 **Finish embedded artwork on the Android Storage Access Framework paths** (android). **Done, 2026-10-07 (close-all-yellow, wave 2).** Both SAF call sites in `LibraryScanner.kt` pass the cover directory, and the instrumented test of 6.6 runs both and passed on the emulator.
  Task 16.9 of `close-the-audited-gaps` covers every path that holds a real file. It is open
  where Android indexes audio through SAF, because neither the single-file nor the folder SAF
  path can reach a file to read. Two call sites in `LibraryScanner.kt`, one reader for a SAF
  child. Write the extracted image to the data directory, not the caches directory.
  **Done 2026-10-06.** `LibraryScanner.scan(resolver, tree, …)` now carries the directory the
  artwork is written to, and both Storage Access Framework call sites use it: a single document
  through `UriSource`'s open descriptor, whose `/proc/self/fd/N` is the path
  `MediaMetadataRetriever` accepts, and a picked folder through
  `LibraryScanner.looseCoverFrom`, which copies the folder's own `cover`/`folder`/`poster`
  child out through the provider once. The directory is `filesDir` and not `cacheDir`: artwork
  written to a cache directory left the cached shelf beside it pointing at files the system had
  removed.
  **Reopened 2026-10-06 by the wave 11 review.** Two faults were fixed: every audiobook in a
  picked folder wrote its cover over the one before, because the cover was filed under the
  reused `/proc/self/fd/N` path (`AudiobookCoverKeyTest`); and the incremental index passed no
  cover directory and indexed an audiobook folder as comic pages. What is still owed is a test
  that fails without the scanner plumbing: no test runs `LibraryScanner.scan` or `index` over
  a content tree with a cover directory. That needs an instrumented test. See 6.6.
- [x] 1.2 **A loose cover image beside the file becomes the cover** (both). `cover`, `folder`
  or `poster`, in the publication's own folder or an audiobook's folder, when the file carries
  no artwork. This is the cheapest rung after the bytes themselves and it is common in ripped
  audiobook folders.
  **Done 2026-10-06.** `LooseCover` on both platforms: `cover`, `folder` or `poster` against
  five extensions, beside a file or inside a folder. `AudiobookCover.folderCoverNames` is that
  list now, so one rung answers for every format instead of for audiobooks alone.
- [x] 1.3 **One place answers "what is this publication's cover"** (both). The shelf, the
  player, the media session and the publication page each resolve covers today. The ladder has
  to be one function they all ask, or a later rung reaches three of the four. Keep
  `CoverCache`'s key and size behaviour.
  **Done 2026-10-06.** `CoverLadder` on both platforms — the reader's own picture, then the
  publication's own bytes, then a loose image beside the file. The shelf (`LibraryModel.cover`
  and `LibraryViewModel.cover`), the player and the publication page reach it through that one
  call, and Android's car shelf asks `CoverLadder.coverFile` where it used to read
  `Publication.coverPath` itself — the fourth caller that made one place necessary.
  `CoverCache`'s key and size behaviour are unchanged.

## 2. The reader's own picture

- [x] 2.1 **A cover-override store, keyed by content digest** (both). Outside the caches
  directory. Falls back to the stable identifier for a publication with no digest, and records
  which key it used so the app can say what moving it costs.
  **Done 2026-10-06.** `CoverOverrideStore`, keyed by `sha:<contentDigest>` and falling back to
  the stable identifier, in Application Support on iOS and under `filesDir` on Android.
  `keyKind` reports which was used, and the publication page says plainly that moving a
  publication filed under its path loses the choice.
- [x] 2.2 **The system picker sets a cover** (both). `PHPickerViewController` on iOS, the photo
  picker on Android. No permission prompt on either, which is the reason for choosing these two
  over a file-read. Crop to the cover shape before storing.
  **Done 2026-10-06.** SwiftUI's `PhotosPicker`, which is `PHPickerViewController`, and
  `ActivityResultContracts.PickVisualMedia`; neither asks for a permission. `CoverArtwork`
  centre-crops to 2:3 before storing.
- [x] 2.3 **The coverless well offers it** (both). `CoverlessWell` draws a glyph and a format
  name and offers nothing. It becomes the entry point.
  **Done 2026-10-06.** The empty well is the button — `CoverlessWell(format:action:)` on iOS, a
  clickable `DetailCover` on Android — and the same offer is made in words underneath, because
  a silently tappable well is one nobody taps.
- [x] 2.4 **Removing a chosen cover falls back down the ladder** (both), and deletes the image.
  **Done 2026-10-06.** *Remove cover* deletes the image, drops both cover caches and lets the
  ladder resolve the rung below on the next draw.
- [x] 2.5 **A chosen cover survives a cache clear** (both). A test that runs
  `StorageUsage.clearCache` and asserts the cover is still there.
  **Done 2026-10-06.** `ChosenCoverSurvivesCacheClearTest` composes the real `StorageUsage`
  against a real `Context` under Robolectric, and the iOS twin asserts the same two things: the
  clear empties the cover cache, and the store's own directory is not under any directory the
  clear reaches.
- [~] 2.6 **Frames**: the coverless well before, and a publication with a chosen cover after, on
  both platforms, light and dark, default and largest text.
  **Done 2026-10-06.** Sixteen frames in
  `docs/designs/screenshots/cover-for-every-publication/`: the coverless well and a publication
  with a chosen cover, on both platforms, light and dark, at the default and the largest text
  size. The README there records how the *after* state was staged, because the system picker
  runs in another process and no test may fill the device's photo library.
  **Reopened 2026-10-06 by the wave 11 review:** five of the eight Android frames do not show
  the state their names claim. The emulator was failing under the capture harness when they
  were taken. Retake them on a healthy emulator. See 6.5.

## 3. The lookup, off until it is turned on

- [~] 3.1 **A setting that names its providers** (both), off by default, stating what leaves
  the device for each kind of request.

      `AppSettings.lookUpMissingCovers` on both platforms, false by default, and absent in a
      stored file reads as false rather than as consent. The row sits on the Privacy screen,
      which is where a choice about what leaves the device belongs: iOS
      `SettingsFeature/CoverLookupSettings.swift`, Android
      `feature/settings/.../CoverLookupRow.kt`. Both build the provider list from
      `CoverLookupProvider` rather than from a literal beside it, so a fourth provider cannot
      be added without a word on the screen. `CoverLookupSettingsTests` and
      `CoverLookupRowTest` assert the default, the older-file read and the provider list.
      Frames: `docs/designs/screenshots/cover-lookup-2026-10-06/` -- iOS only, see 3.6.

      **Reopened 2026-10-06 by the wave 11 review.** The row named only the identifier
      services and said one identifier "and nothing else" leaves the device, while the same
      switch gates the title search, which sends the title and the author to AniList and
      MangaUpdates as well. Fixed: the row is built from both lists, and the note says what
      each kind of request sends, in four languages. Still owed: the Android frame of the
      setting. See 6.5.
- [x] 3.2 **Lookup by identifier** (both): Open Library by ISBN, Cover Art Archive by MBID, **Done, 2026-10-07 (close-all-yellow, wave 2).** The client is now called by the shelf ladder on both platforms (6.1), and the rung tests show one provider asked once while the switch is on and nothing asked while it is off. Every test uses a stub transport; a check against the three live catalogues stays an owner step.
  Audnexus by ASIN. One request per publication. Every answer cached to disk.

      `CoverLookupProvider.swift` and `CoverLookupProvider.kt` pair each identifier with the
      one provider that answers it, validate it before it reaches a URL, and ask Open Library
      with `default=false` so a blank placeholder is not stored as a reader's cover. The
      clients consult the cache first and write every answer after, so a publication is asked
      about once. The cache sits in the app's data directory rather than its cache directory:
      clearing decoded pages is not permission to crawl three catalogues again.

      **Reopened 2026-10-06 by the wave 11 review: the client is built and nothing calls it.**
      No indexer reads an ISBN, an MBID or an ASIN, and no rung of the ladder asks the client,
      so a reader who turns the switch on gets no cover. The review also hardened the client:
      every request and every redirect must land on a listed https host (`CoverImageHosts`),
      an answer is read up to 8 MB and no further, and `coverImage` hands back the picture an
      image provider already sent instead of fetching it twice. See 6.1.
- [~] 3.3 **Lookup by title shows candidates and waits** (both). Never adopts a match on its
  own. Open Library `search.json`, AniList for manga, MangaUpdates — all keyless.

      **2026-10-06: built and tested; not reachable yet.** `CoverTitleSearch` builds all three
      requests and reads all three answers on both platforms, `candidates(title:)` returns
      them and applies none, and `CoverCandidateSheet` draws them with no best match and no
      automatic dismissal. The blocker this note named is gone: the coverless well (task 2.3)
      is on main. What is missing now is the call: no screen opens the sheet. Title-search
      answers are now cached, filtered to listed hosts and de-duplicated by picture. See 6.2
      and 6.3.
- [x] 3.4 **A refusal is quiet** (both). 403, 404, 429 or silence leaves the cover as it was,
  shows the reader no error for something they did not ask about, and does not retry in a loop.

      Nothing throws out of `cover(for:identifier:)` on either platform: 403, 404, 429, 500 and
      no answer at all come back as nothing, and each is recorded, so nothing retries.
      `CoverLookupCache.forget` is the one way back, for a reader who asks again by hand.
- [x] 3.5 **The egress rule holds** (both). A test that asserts no cover request is made while
  the setting is off.

      `nothing is asked while the setting is off` and `a title search is silent too while the
      setting is off`, on both platforms, counting the requests a recording transport saw.
      Proved able to fail: removing the gate makes iOS report `Expectation failed: found ==
      nil` and `Expectation failed: asked.value.isEmpty`, and Android `CoverLookupClientTest >
      nothing is asked while the setting is off FAILED`.
- [~] 3.6 **Frames**: the setting, and the candidate chooser.

      **2026-10-06: the setting is photographed on iOS only, and the chooser not at all.**
      `docs/designs/screenshots/cover-lookup-2026-10-06/` holds the Privacy screen on an
      iPhone 17 Pro in light and dark, at the default and the largest text size. The
      Pixel_7_Pro emulator on this machine would not stay responsive long enough to walk to
      the screen -- three cold boots ended in *System UI isn't responding* or in `uiautomator`
      answering `null root node returned by UiTestAutomationBridge`. The chooser is not
      reachable until task 2.3 opens it. The set's README states both gaps.

## 4. The web hand-off

- [~] 4.1 **The system browser opens an image search for the title** (both).
  `SFSafariViewController` on iOS, a Custom Tab on Android. Not a `WKWebView`, not a
  `WebView` — see design.md, which records why at length.

      **2026-10-06: built and tested; not reachable yet.** `CoverWebSearch` builds the address
      on both platforms. iOS wraps `SFSafariViewController` with no delegate; Android builds an
      `ACTION_VIEW` intent carrying the Custom Tabs session extra, which needs no new
      dependency. The row that offers it is written and is placed on no screen. The blocker
      this note named, the coverless well of task 2.3, is on main now. See 6.2.

      The engine is DuckDuckGo, which design.md does not decide: the app has no analytics and
      no account, and an engine that profiles a signed-in reader would undo that at the one
      moment the app chooses the address.
- [x] 4.2 **A test asserts the app reads nothing from that browser** (both): no capture, no
  injected script, no image received. The only route in is the picker of task 2.2.

      Two halves on each platform, because one alone would pass for the wrong reason. The first
      reads the hand-off's own API -- a closure taking a URL and answering nothing on iOS, an
      intent with no result on Android -- and finds no channel data could return through. The
      second reads the source, with comments stripped, and refuses a web view, a script and a
      capture. Proved able to fail: a `WKWebView` string in the iOS file reports `Expectation
      failed: !text.contains(forbidden)`, and a `WebView` string in the Kotlin file reports
      `CoverSearchHandoffTest > the hand-off is a Custom Tab, never a web view this app owns
      FAILED`.
- [ ] 4.3 **Frames**: the hand-off, and the publication afterwards with its new cover.

      **2026-10-06: neither frame exists.** Both need the entry point of task 2.3, and the
      second needs the override store of task 2.1 as well. The commits that add the drawing
      code carry `Visual-proof: flag`.

## 5. Writing back where it works

- [~] 5.1 **A cover set on a Kavita reading list the reader owns may be written back** (both).
  One POST per client, base64, an 8 MB guard. The confirmation says it changes the cover for
  everyone who can see that list.

      **2026-10-06: the route, the guard and the words exist; the button is placed on no
      screen.** `uploadReadingListCover` posts once to `Upload/reading-list` as base64 on both
      platforms, refuses an empty picture and anything above eight megabytes before the request
      is built, and goes through the versioned path so an older Kavita says so once.
      `CoverWriteBackButton` holds the confirmation -- *This changes the cover for everyone who
      can see that list* -- in en, fr, de and es.

      **The seam the merge has to join:** the button takes the chosen cover's bytes as
      `image: () async -> Data?`, and `suspend () -> ByteArray?` on Android, rather than
      reaching for them, because the override store that holds them is task 2.1. Nothing is
      sent when it answers nothing. The store of task 2.1 is on main now, so the blocker this
      note named is gone; the button is still placed on no screen. See 6.4.

      Proved able to fail: removing the ceiling check reports `KavitaCoverUploadTest > a
      picture above the ceiling is refused before anything is sent FAILED`.
- [x] 5.2 **Nowhere else offers it** (both). A test that asserts no write action appears on a
  Kavita series, chapter, collection or library, nor on any OPDS row, so the feature cannot
  drift into offering a 403.

      `CoverWriteBack.offer` is the one place that decides, and its subject type is exhaustive,
      so a later row has to pick a case rather than fall through to an offer. A promoted
      reading list is refused too: `ReadingList/lists` answers with the reader's own lists plus
      the promoted ones, so promoted is the only case where the answer does not prove
      ownership. Proved able to fail: offering the write on a Kavita series reports
      `Expectation failed: CoverWriteBack.offer(for: subject) == .none` on iOS and
      `CoverWriteBackTest > no Kavita entity but a reading list is offered a write FAILED` on
      Android.
- [ ] 5.3 **Check the live server** (owner step, android and ios). The repo's Kavita client was
  built against documentation rather than a live instance for some routes. The owner has a
  Kavita server; the upload shape needs one real call before this is claimed to work.

## 6. From the review of wave 11

A review of wave 11 read sections 1 to 5 against `cover-art` and `AGENTS.md`. It fixed what a
reader meets today: a chosen cover now appears at once and upright, every audiobook in a picked
folder keeps its own cover, a loose cover beside a picked-folder document is found, a failed
replacement is reported, a Kavita reading list draws a chosen cover, and the lookup reaches only
listed hosts. These are what it did not close.

- [x] 6.1 **The lookup is a rung of the ladder** (both). Read the identifier at index time: an **Done, 2026-10-07 (close-all-yellow, wave 2).** The lookup is the last rung of the shelf ladder on both platforms (Android `LibraryViewModel.cover` to `CoverLookupRung` to `CoverLookupClient`; iOS `LibraryModel.cover` to the same client). The setting gates the rung and the client. The client asks only https hosts in `CoverImageHosts`, reads at most 8 MB and checks each redirect host. The reviewer found and fixed two faults: a refused picture was not recorded, so each draw asked the host again (both platforms, commits `884113db` and `eec30f8c`), and the Android answer cache was an unsynchronised map written from the IO pool (now `@Synchronized`). A frame needs network access and an EPUB with an ISBN and no cover; the rung draws no new view, so no frame is owed here.
  ISBN from an EPUB's OPF, a MusicBrainz release-group id and an Audible ASIN from audio tags.
  Ask `CoverLookupClient.coverImage` after the rungs that need no network, only while the
  switch is on. Until then the switch does nothing, and task 3.2 stays partial.
- [ ] 6.2 **The publication page offers the title search and the web search** (both). Put a
  "Find a cover" action that opens `CoverCandidateSheet`, and the web hand-off of task 4.1,
  beside the cover choice. The title search only while the switch is on; the hand-off always,
  because the browser makes that request and the app does not.
- [x] 6.3 **The candidate sheet shows each picture, through the client** (both). The Android **Done, 2026-10-07 (close-all-yellow, wave 2).** The candidate sheet loads each picture through `CoverLookupClient.image` (the setting and the host are checked) on both platforms, and iOS no longer uses `AsyncImage`. Each row is keyed by position, so two equal answers are two rows. The picture is decorative and keeps a 44 x 66 frame while it loads. No string is new. No screen opens the sheet until task 6.2 adds "Find a cover", so the frames (light and dark, default and largest text) are taken with 6.2; commit `f5004eea` records `Visual-proof: flag`.
  sheet shows no picture, so the reader chooses blind. The iOS sheet loads pictures through
  the shared session and not through `CoverLookupClient.image`, which is the one path that
  checks the host. Key the Android rows on something two equal answers cannot share.
- [ ] 6.4 **The write-back button is on the Kavita reading-list screen** (both), and only once a
  cover is chosen. Today it is placed nowhere, and its own view draws it with no cover chosen,
  where Send does nothing.
- [ ] 6.5 **Retake the frames** (android). Five of the eight frames of task 2.6, and the setting
  of task 3.1, on an emulator that stays responsive under the harness.
- [x] 6.6 **An instrumented test runs the scanner over a content tree** (android), with a cover **Done, 2026-10-07 (close-all-yellow, wave 2).** `LibraryScannerCoverTreeInstrumentedTest` ran on the storyarc-ci emulator (API 35) through `pnpm gradle :core:format:connectedDebugAndroidTest`: 4 tests, 0 failures, through a real `DocumentsProvider` (`TestTreeProvider`). A temporary mutation that passed a null cover directory at the index call site made `theIncrementalIndexGivesEachAudiobookItsOwnCover` fail by name (reviewer).
  directory, and asserts each audiobook's own cover path. It closes task 1.1.

