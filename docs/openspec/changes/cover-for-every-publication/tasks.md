A ticked box here means: the code exists on every platform the task names, a test that fails
without it landed, and any frame the change needs exists. A tick does **not** mean a person
watched it on a device.

## 1. The rungs that need no network

- [ ] 1.1 **Finish embedded artwork on the Android Storage Access Framework paths** (android).
  Task 16.9 of `close-the-audited-gaps` covers every path that holds a real file. It is open
  where Android indexes audio through SAF, because neither the single-file nor the folder SAF
  path can reach a file to read. Two call sites in `LibraryScanner.kt`, one reader for a SAF
  child. Write the extracted image to the data directory, not the caches directory.
- [ ] 1.2 **A loose cover image beside the file becomes the cover** (both). `cover`, `folder`
  or `poster`, in the publication's own folder or an audiobook's folder, when the file carries
  no artwork. This is the cheapest rung after the bytes themselves and it is common in ripped
  audiobook folders.
- [ ] 1.3 **One place answers "what is this publication's cover"** (both). The shelf, the
  player, the media session and the publication page each resolve covers today. The ladder has
  to be one function they all ask, or a later rung reaches three of the four. Keep
  `CoverCache`'s key and size behaviour.

## 2. The reader's own picture

- [ ] 2.1 **A cover-override store, keyed by content digest** (both). Outside the caches
  directory. Falls back to the stable identifier for a publication with no digest, and records
  which key it used so the app can say what moving it costs.
- [ ] 2.2 **The system picker sets a cover** (both). `PHPickerViewController` on iOS, the photo
  picker on Android. No permission prompt on either, which is the reason for choosing these two
  over a file-read. Crop to the cover shape before storing.
- [ ] 2.3 **The coverless well offers it** (both). `CoverlessWell` draws a glyph and a format
  name and offers nothing. It becomes the entry point.
- [ ] 2.4 **Removing a chosen cover falls back down the ladder** (both), and deletes the image.
- [ ] 2.5 **A chosen cover survives a cache clear** (both). A test that runs
  `StorageUsage.clearCache` and asserts the cover is still there.
- [ ] 2.6 **Frames**: the coverless well before, and a publication with a chosen cover after, on
  both platforms, light and dark, default and largest text.

## 3. The lookup, off until it is turned on

- [x] 3.1 **A setting that names its providers** (both), off by default, stating that one
  identifier and nothing else leaves the device.

      `AppSettings.lookUpMissingCovers` on both platforms, false by default, and absent in a
      stored file reads as false rather than as consent. The row sits on the Privacy screen,
      which is where a choice about what leaves the device belongs: iOS
      `SettingsFeature/CoverLookupSettings.swift`, Android
      `feature/settings/.../CoverLookupRow.kt`. Both build the provider list from
      `CoverLookupProvider` rather than from a literal beside it, so a fourth provider cannot
      be added without a word on the screen. `CoverLookupSettingsTests` and
      `CoverLookupRowTest` assert the default, the older-file read and the provider list.
      Frames: `docs/designs/screenshots/cover-lookup-2026-10-06/` -- iOS only, see 3.6.
- [x] 3.2 **Lookup by identifier** (both): Open Library by ISBN, Cover Art Archive by MBID,
  Audnexus by ASIN. One request per publication. Every answer cached to disk.

      `CoverLookupProvider.swift` and `CoverLookupProvider.kt` pair each identifier with the
      one provider that answers it, validate it before it reaches a URL, and ask Open Library
      with `default=false` so a blank placeholder is not stored as a reader's cover. The
      clients consult the cache first and write every answer after, so a publication is asked
      about once. The cache sits in the app's data directory rather than its cache directory:
      clearing decoded pages is not permission to crawl three catalogues again.
- [~] 3.3 **Lookup by title shows candidates and waits** (both). Never adopts a match on its
  own. Open Library `search.json`, AniList for manga, MangaUpdates — all keyless.

      **2026-10-06: built and tested; not reachable yet.** `CoverTitleSearch` builds all three
      requests and reads all three answers on both platforms, `candidates(title:)` returns
      them and applies none, and `CoverCandidateSheet` draws them with no best match and no
      automatic dismissal. What is missing is the entry point: the coverless well that opens
      the sheet is task 2.3, which another agent owns. The sheet takes `candidates` and an
      `onChoose`, which is the seam the merge joins.
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
      dependency. The row that offers it is written and is placed on no screen, because the
      coverless well that would hold it is task 2.3.

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
- [~] 4.3 **Frames**: the hand-off, and the publication afterwards with its new cover.

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
      sent when it answers nothing. Placing the button on the server reading-list screen waits
      on that store.

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
