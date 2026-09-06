# Tasks

**What a tick means here.** A tick means the code exists, something asserts it,
and the named command passed. Where a task carries a capture, a tick also means
somebody looked at the picture — not that a preview was rendered. A tick does
**not** mean a translation was reviewed by a speaker of that language; where a
task ships a translation, the tick covers that the four locales resolve and the
layout survives them, and nothing more.

**Two open questions bound two tasks**, and neither blocks the rest: 4.3 cannot
close until the offline destination is named (design, Open Questions), and 4.4
carries the judgement calls the owner may want to see. Everything else is
answerable from the tree.

**Ordering is by seam, not by platform.** The proposal's sizing argument is that
a seam left half-done is worse than one not started — so each of §1, §2 and §3 is
one seam, and the platform pair inside it moves together.

## 1. The scanner and indexer reasons

The largest seam: 21 of the 30 literals, both platforms, one mirrored type. The
format layer stops being able to hold a sentence.

- [x] **1.1** Write the failing tests first, both platforms, case for case.
      iOS: extend the `PublicationIndexer` / `LibraryScanner` suites under
      `apps/ios/Packages/StoryArcKit/Tests/FormatsTests/` to assert each refusal
      case is *a case*, not a string — that a skipped publication's reason
      resolves through the catalogue and that no case carries free-form text.
      Android: the mirror in
      `apps/android/core/format/src/test/kotlin/app/storyarc/core/format/`.
      Verify: `pnpm test:ios` and
      `pnpm gradle :core:format:testDebugUnitTest` both **fail**, naming the
      cases. A test that passes before the change is the vacuous shape AGENTS.md
      §5 catalogues.

      **2026-09-06.** Two reds per platform, both watched before anything was
      changed. The catalogue guards compile against the old tree and fail on the
      assertion: iOS `SkipReasonCatalogueTests` — *the catalogue defines no
      "library.skipped.reason.unsupported %@"*, 2 tests, 2 failed; Android
      `SkipReasonCatalogueTest` — *values/strings.xml does not word
      library_skipped_reason_unsupported*, 2 tests, 2 failed. The case-set guards
      cannot compile against the old tree, and the compiler names each case:
      `type 'PublicationIndexer.IndexError' has no member 'notThere'` and four
      more, then `cannot find type 'SkipReason' in scope`; Kotlin,
      `Unresolved reference 'NotThere'` and `Unresolved reference 'SkipReason'`.
- [x] **1.2** Close the case set on iOS.
      `PublicationIndexer.IndexError.unreadable(reason: String)` in
      `apps/ios/Packages/StoryArcKit/Sources/Formats/PublicationIndexer.swift:23`
      becomes the closed set the code already constructs — *not there*, *format
      not recognised*, *archive password protected*, *archive unreadable*, *PDF
      unopenable* — with the call sites at `PublicationIndexer.swift:67,83,145`
      and `PublicationIndexer+Building.swift:67,71,182` moving to it.
      Verify: `pnpm test:ios` passes; `pnpm lint:ios` from the repository root,
      never after a `cd`.

      **2026-09-06.** Seven cases: `unsupported(format:)`, `notThere`,
      `formatNotRecognised`, `archivePasswordProtected`, `archiveUnreadable`,
      `pdfUnopenable`, `contentProtected`. `ScanEvent.skipped` carries a new
      `SkipReason`, which is those seven plus `unknown` for the walk's catch-all.
      `pnpm test:ios` — *2020 tests in 257 suites failed with 7 issues*, every one
      of the seven in `AppIconChooserAnnouncementTests` and pre-existing.
      `swiftlint lint --strict --no-cache` — *0 violations, 0 serious in 698
      files*.
- [x] **1.3** Close the case set on Android, identically.
      `IndexException.Unreadable(val reason: String)` at
      `apps/android/core/format/.../PublicationIndexer.kt:23`, call sites at
      `:133,:235,:239,:329,:370,:400,:404`. Same case names as 1.2 — the mirror
      is checked by reading, so a name that differs is a defect.
      Verify: `pnpm gradle :core:format:lint :core:format:testDebugUnitTest`.

      **2026-09-06.** Six cases, named as iOS names them. Android does not carry
      `pdfUnopenable`: `PublicationIndexer` indexes a PDF without opening it,
      because `PdfRenderer` is a framework class the indexer stays off, so that
      refusal cannot arise and a seventh case would be dead code. The difference
      is stated in both files' doc comments so the mirror still reads as one.
      `:core:format:testDebugUnitTest` — *287 tests, 0 failures*.
      `:core:format:lint` — *BUILD SUCCESSFUL*.
- [x] **1.4** Map case to key in the view module, iOS.
      `LibraryScanner.swift:351`'s `skipReason(for:)` and the catch-all at
      `:315` move out of `Formats`; the keys land in
      `LibraryFeature/Resources/Localizable.xcstrings` in en, fr, de and es.
      `Formats` gains no catalogue — `pnpm strings:ios` reads one table per
      module and that module draws nothing.
      Verify: `pnpm strings:ios` reports no MISSING and no UNTRANSLATED.

      **2026-09-06.** `Sources/LibraryFeature/SkipReasonWords.swift` maps each case
      to a `Text` literal, so `scripts/ios-strings.mjs` can see all eight keys.
      `Formats` gained no catalogue. `pnpm strings:ios` — *every key resolves, in
      en, fr, de, es*. The tick covers that the four locales resolve and that the
      keys are asked for as literals. No speaker of French, German or Spanish
      reviewed the words.
- [x] **1.5** Map case to key in the view module, Android.
      `LibraryScanner.kt:531,582,612,661,668`'s `reasonFor(cause)` moves to
      `feature/library`, keys into `values`, `values-fr`, `values-de` and
      `values-es` `strings.xml`.
      Verify: `pnpm gradle :feature:library:lint` — a translation gap fails lint,
      which is the parity iOS needs a script for.

      **2026-09-06.** `feature/library/SkipReasonWords.kt` maps each case to a name
      in `values`, `values-fr`, `values-de` and `values-es`.
      `:feature:library:testDebugUnitTest` — *460 tests, 0 failures*.
      `:feature:library:lint` reports **no `MissingTranslation` and no
      `ExtraTranslation`**, so the four locales are complete. That task fails on
      one error, `ViewModelConstructorInComposable` at
      `LibraryControlsAreNamedTest.kt:102` — **pre-existing**, in a file this change
      does not touch, added by commit `6c76fc16`. The tick covers that the four
      locales resolve. No speaker of French, German or Spanish reviewed the words.
- [x] **1.6** Reconcile the content-protection sentence to Android's wording.
      iOS says *it is protected by its store's content protection*
      (`LibraryScanner.swift:355`); Android names the kind —
      *this audiobook is protected by its store's content protection*
      (`LibraryScanner.kt:668`). Android's wins, per the spec's *the more
      informative one is the agreed wording*. One key, one value, both
      platforms.
      Verify: the mirrored assertions in 1.1 compare the same expected key on
      both sides.

      **2026-09-06.** One value, both platforms: *this audiobook is protected by
      its store's content protection*. iOS dropped *it is protected by …*.
      `SkipReasonCatalogueTests.contentProtectionIsReconciled` and
      `SkipReasonCatalogueTest` assert the same English on both sides.
      `AudiobookIndexingTests` asserted in English that the refusal prompts for
      nothing; that assertion moved to `SkipReasonCatalogueTests`, where it runs
      against all four languages. The move first narrowed it: English lost
      `key`, `password` and `log in`, and each translated language gained one
      token. The list now carries a key, a password, an account and a way to
      sign in, in all four languages, and `SkipReasonCatalogueTest` runs the
      mirror on Android, which had no such guard at all.
- [~] **1.7** Capture both skipped notices, in Spanish, at the largest text size.
      `SkippedNotice.swift` and `SkippedNotice.kt` are compact banners and the
      translations are longer than the English. Spanish is this app's measured
      worst case, not German — `localization`'s *Long translations* is the one
      scenario STATUS.md records as unsettled, and it was mis-premised on German
      for three review rounds.
      Walk: `pnpm capture:android --list` names the route; on iOS, scan a folder
      holding one file of an unread format.
      Capture light and dark, default and largest text size, both platforms.
      **Control:** the same notice in English at the same moment on the same
      device — a Spanish banner that fits proves nothing if the English one is
      the picture that was taken.

      **2026-09-06 — the frame this owes.** The words are in and the capture is
      not. The emulator lock is shared, so this frame belongs to the serialised
      capture pass. What it needs:

      - **Route.** Android: `SkippedNotice` above the shelf on the library
        screen, reached by scanning a folder that holds one file of an unread
        format. iOS: the same banner in `LibraryView`, reached by picking a folder
        holding `packages/test-fixtures/audiobooks/protected.aax`.
      - **The state to drive.** One skipped publication, so the notice is
        `Notice.One` and draws the reason under the name. The longest sentence is
        `contentProtected`, so `protected.aax` is the file to scan.
      - **Appearance.** Light and dark, both platforms.
      - **Text size.** Default, and the largest the accessibility settings offer:
        `accessibility-extra-extra-extra-large` on iOS, font scale 2.0 on Android.
      - **Control frame.** The same notice in English, same device, same moment.
      - **Language.** Spanish, and Spanish is the measured worst case here, not
        German. The Spanish value is 74 characters against 61 in English, 73 in
        French and 63 in German — the longest of the four. Counted, not
        estimated; the four figures recorded here first were each one low.
      - **What a unit test already says, so the picture does not have to.**
        `SkipReasonWordsTest` composes the banner at font scale 2.0 in a 320dp
        window and asserts every Spanish, German and French sentence is drawn
        inside the row the banner gives it, which is that window less two
        gutters. It reads the **unmerged** tree, so the node it measures is the
        sentence. Through the merged tree it measured the banner's padding
        instead, and no string of any length could fail it — this bullet claimed
        containment for two days that the test did not assert. What it still
        cannot say is whether the result reads well.
- [~] **1.8** Confirm a screen reader speaks the translated words.
      Both notices group with `accessibilityElement(children: .combine)` and its
      Android equivalent, so the reason is announced as part of the notice.
      Verify: VoiceOver on a booted simulator and TalkBack on an emulator, with
      the interface language set to French. No new string; this asserts 1.4 and
      1.5 reached the announcement and not only the label.

      **2026-09-06 — the frame this owes.** A screen-reader pass, not a picture,
      and it belongs to the serialised capture pass for the same reason as 1.7.
      What it needs:

      - **Route.** The same skipped notice as 1.7, on both platforms, with one
        skipped publication so the notice names it and states the reason.
      - **Screen reader.** VoiceOver on a booted simulator, TalkBack on an
        emulator. Both on, and the swipe that reaches the notice recorded.
      - **Language.** The interface language set to **French**, on the device and
        not only in the app.
      - **What to listen for.** One stop, saying the publication's name and the
        French reason together. Two stops is the defect. English inside a French
        announcement is the other defect, and it is the one this task exists for.
      - **Control.** The same swipe with the interface language set to English.
      - **What a unit test already says.**
        `SkippedNoticeAnnouncementTests.oneFailureIsOneStop` asserts the reason's
        **key** is inside the merged element, so the announcement and the label
        draw the same value. It runs on the host, where `String(localized:)`
        answers with the key, so it cannot hear a language.

## 2. The refused-file alert

Six literals, iOS only. Android's `RefusedFileDialog.kt` is already localised and
is the target shape.

- [x] **2.1** Write the failing test.
      `apps/ios/Packages/StoryArcKit/Tests/` — assert the alert's title, its
      button and each of the three `message` branches resolve through the
      catalogue. Verify: it fails first.
      **Done 2026-09-06.** `Tests/StoryArcCoreTests/RefusedFileWordingTests.swift`.
      It reads the app's source and the app's catalogue, because the app target has
      no test target and `pnpm test:ios` runs `swift test` over the package alone —
      the same second choice `ShellWiringTests` takes for `AppShell.swift`.
      It failed first with three named issues: *The alert draws no English literal*,
      *Every branch of the alert draws a key*, *The catalogue answers every key in
      four languages*.
- [x] **2.2** Localise `apps/ios/App/RefusedFile.swift`.
      `:29` (the supported-format list), `:37`, `:41`, `:44` (the three message
      branches), `:55` (`Text(verbatim: "Cannot open this file")`) and `:58`
      (`Text(verbatim: "OK")`). Keys go in `App/Resources/Localizable.xcstrings`.
      The format list at `:29` is data, not a sentence — the words around it are
      what get keys, and the comment at `:25-28` explaining why the list is not
      derived from the enum stays.
      Verify: `pnpm strings:ios`, then `pnpm build:ios` — this is the app target.
      **Done 2026-09-06.** Five keys, named to pair with Android's `open_in_*`:
      `open.in.refused.title`, `open.in.dismiss`, `open.in.protected %@`,
      `open.in.unsupported %@ %@ %@`, `open.in.unreadable %@ %@`. The format list
      stays a literal and shortened to `CBZ, CBR, CBT, EPUB, PDF, M4B`; the words
      *and other audiobooks* moved into the two sentences that carry it. `message`
      returns `Text` rather than `String`, because a `String` cannot hold a key.
      `pnpm strings:ios`: *every key resolves, in en, fr, de, es*. `pnpm build:ios`
      exits 0 with no `error:` line. The English values are unchanged, so the two
      platforms' wording still diverges where it diverged before — §4.2 owns that.
      **Corrected 2026-09-06.** `open.in.protected %@` stated the protection and
      stopped, so an iOS reader was left waiting for a field that never arrives.
      Android's `open_in_protected` says one sentence more, *there is nothing to enter
      here*, and `ProtectedAudiobookPromptsForNothingTest` asserts those words. The
      sentence is now in all four iOS values, word for word from Android.
      `RefusedFileWordingTests` guards the English one and failed by name first: *The
      protected refusal forecloses the field it does not draw*.
- [x] **2.3** Give the Android name fallback a key.
      `app/.../OpenedFile.kt:114`'s `"this file"` is interpolated into an
      otherwise-localised sentence, so a French dialog reads French around an
      English noun.
      Verify: `pnpm gradle :app:lint :app:testDebugUnitTest`.
      **Done 2026-09-06.** `open_in_unnamed`, in `values`, `values-fr`, `values-de`
      and `values-es`. `OpenedFile.index` now takes the activity's `Context` rather
      than its `ContentResolver`, because a resolver cannot answer for a string;
      `AppIntents.kt:63` passes `activity`. The fallback is lower case in every
      language, and the resource's comment says why. *BUILD SUCCESSFUL in 44s*.
- [~] **2.4** Capture the alert on both platforms in French, light and dark.
      **Control:** the same alert in English, same device, same moment.
      **Owed 2026-09-06.** Not captured: the emulator and the simulator locks are
      shared, so captures run serialised in their own pass. The brief for that pass:
      hand the app a file it refuses, on each platform, and photograph the alert.
      iOS route: Files → *Open with StoryArc* on a `.txt` file, which reaches
      `StoryArcAppActions.swift:38` and draws `open.in.unreadable`. Android route:
      the same file through the share sheet, which reaches
      `OpenedFile.Outcome.Unreadable` and draws `open_in_unreadable`. Appearance:
      light and dark. Text size: default. Control frame: the same alert with the
      interface language set to English, same device, same moment.

## 3. The Android reader failure

Two literals, and the largest hidden surface behind them.

- [x] **3.1** Count what is reachable, and write it down here.
      `ReaderViewModel.kt:437,495` assigns `cause.message` to what the reader is
      shown, so internal prose from anywhere in `core/format` can surface —
      `PdfDocumentReader.kt` alone throws *not a pdf*, *cannot open file*,
      *no file descriptor for …*, *page has no size*. The count does not change
      the approach, and an uncounted blast radius is how a one-line fix turns
      out to have been a twenty-file one. Verify: the list is in this task.

      **Counted 2026-09-06: 67 distinct English sentences, in 14 files.** Both
      catches take `Exception`, so every one of them reaches the screen. Counted
      from `core/format`'s own sources on this date; §1 is rewriting
      `PublicationIndexer`'s seven, so that row moves.

      | File | Count | The sentences |
      | --- | --- | --- |
      | `ZipReader.kt` | 16 | *no end of central directory record*, *archive is encrypted*, *unsupported method %d*, *inflate failed*, and *malformed zip: %s* carrying *zip64 sentinel present but no zip64 record*, *central directory outside the source*, *central directory slice invalid*, *zip64 EOCD offset outside the source*, *zip64 EOCD signature missing*, *negative uncompressed size*, *not a local header*, *implausible name length*, *local header runs past the source*, *local header signature missing*, *entry data outside the source* |
      | `HttpSource.kt` | 8 | *server does not serve ranges*, *206 with no Content-Range*, *asked for %s, told %s*, *expected %s bytes, got %s*, *length was %s*, *no length stated*, *answered from elsewhere*, *http %d* |
      | `PdfDocumentReader.kt` | 7 | *pdf unreadable*, *not a pdf*, *cannot open file*, *cannot open document*, *no file descriptor for %s*, *page has no size*, *no page at index %d* |
      | `PublicationIndexer.kt` | 7 | *unsupported format: %s*, *the format was not recognised*, *the archive is password protected*, *the archive could not be read*, *the file is not there*, *%s is protected by its store's content protection*, *%s is not an audio container* |
      | `ComicArchive.kt` | 5 | *unsupported container: %s*, *unrecognised container*, *archive is password protected*, *archive is unreadable*, *archive uses solid compression* |
      | `TarReader.kt` | 5 | *not a tar archive*, *size overflows*, *not an octal field*, *octal field overflows*, *entry lies outside the source* |
      | `RarReader.kt` | 4 | *not a rar archive*, *entry needs a decoder, method %d*, *archive declares too many entries*, *entry lies outside the source* |
      | `ByteReader.kt` | 3 | *seek out of range*, *skip past end*, *read past end* |
      | `EpubReader.kt` | 3 | *not an epub*, *no package document*, *no entry at %s* |
      | `RandomAccessSource.kt` | 3 | *read of %d bytes at %d exceeds source length %d*, *short read at %d*, *source unreadable* |
      | `CoverLoader.kt` | 2 | *no cover*, *cover unreadable* |
      | `RarDecoder.kt` | 2 | *libarchive could not open %s*, *libarchive could not read '%s' from %s* |
      | `PageDecoder.kt` | 1 | *bytes are not a recognised image* |
      | `UriSource.kt` | 1 | *no file descriptor for %s* |

      **And the set is not closed.** `catch (cause: Exception)` also catches what
      the platform throws, which carries its own English and no catalogue at all.
      `OpenedFile.kt` records a measured one: `FileNotFoundException:
      /proc/self/fd/117: open failed: EACCES`. So 67 is the floor.
- [x] **3.2** Write the failing test.
      `feature/reader`'s unit tests — assert that a failure carrying internal
      text surfaces the general refusal key and never the exception's own
      message. Verify: it fails first.
      **Done 2026-09-06.** `ReaderFailureSaysNothingInternalTest`. A source guard,
      because this module's unit tests run on a bare JVM and a `ReaderViewModel`
      cannot be built there — `SolidArchiveHasNoNoticeTest` reads the same tree the
      same way. It failed first with two named failures: *the reader is never shown
      an exception's own message* and *the reader is shown a translated refusal
      instead*. Its third test, *the view model still sets a failure*, passed both
      times: it is the non-vacuity assertion, and a guard over nothing passes for
      ever.
- [x] **3.3** Replace `cause.message` with a translated general refusal.
      `ReaderViewModel.kt:437,495`. **This removes information a reader can see
      today**, deliberately: it was written for a maintainer, and the diagnostic
      export — English by explicit design — is where a maintainer gets it.
      iOS has no equivalent surface, so the handoff says Android-only.
      Verify: `pnpm gradle :feature:reader:lint :feature:reader:testDebugUnitTest`.
      **Done 2026-09-06.** `failure` carries a string resource id instead of a
      sentence, so an exception message can no longer be put in it. The new key is
      `reader_cannot_open`, in all four `values*` files, and its comment records
      what was removed and where a maintainer now gets it. `ReaderScreen.kt:228`
      resolves it. *BUILD SUCCESSFUL in 7s*.
      **iOS is not clean, and the handoff's premise is wrong.**
      `ReaderFeature/ReaderModel.swift:286,325` sets `failure = String(describing:
      error)`, which is the same defect with a worse rendering. Left alone because
      this task says Android-only and `Sources/ReaderFeature/` is another agent's
      file in this wave. It wants its own task.
      **Corrected 2026-09-06.** Two claims above were wrong.
      The refusal read *the file may be damaged or incomplete*. The catch cannot know
      that: a rejected server credential, a denied permission and a cancelled read all
      reach the same line, and `PublicationAccess.openArchive` routes every registered
      remote scheme through it. The sentence now stops after the refusal, in all four
      languages.
      The diagnostic export does not carry the exception. `Diagnostic.text` emits
      [App], [Device], [Settings], [Reading defaults], [Storage] and [Sources], and the
      app writes no log, so a refusal's cause is now known to nobody. The four resource
      comments and the test's doc comment said otherwise and now say what happens.
      Task 3.5 owns the missing half.
- [~] **3.4** Capture the reader's failure message in French.
      Walk: open a truncated file from the corpus. Light and dark.
      **Control:** the same screen in English at the same moment — the sentence
      is what changed, so a picture of a failure screen proves nothing on its
      own.
      **Owed 2026-09-06.** Not captured: the emulator lock is shared, so captures
      run serialised in their own pass. The brief for that pass: open a truncated
      file from the corpus on Android, with the interface language set to French.
      Route: library shelf → the truncated publication → the reader, which fails in
      `ReaderViewModel.open` and draws `reader_cannot_open` through
      `ReaderScreen.kt:228`. Appearance: light and dark. Text size: default.
      Control frame: the same screen with the interface language set to English,
      same device, same moment.
- [ ] **3.5** Record a refusal's cause where a maintainer reaches it.
      3.3 removed the exception from the screen and put it nowhere. One `[Last
      failure]` section in `Diagnostic.text`, or one `Log.w` call at
      `ReaderViewModel.kt:436` and `:494`, closes it.
      **Blocked on a shorter file.** Either route adds a line to
      `ReaderViewModel.kt`, which `scripts/line-cap.mjs` records at 811 lines.
      Raising that record weakens the ratchet, so this slice shortens the file first.
      Verify: `pnpm gradle :feature:reader:testDebugUnitTest` and `pnpm lines:check`.

## 4. One state, one name

- [ ] **4.1** Regenerate the divergence list and commit it as the work item.
      629 keys pair across the two catalogues by normalised name, 595 carry
      identical English, **34 do not**. Regenerate rather than trusting the
      number here — five changes are in flight and it moves.
      Verify: the list is in this task, with each row marked *wording*,
      *placeholder syntax*, or *platform forces it*.
- [ ] **4.2** Reconcile the rows marked *wording*, one state at a time.
      A state whose two platforms agree is better than one where they do not,
      whatever else is open — so this is the one group in the change that may
      land partly without leaving a seam open.
      Verify: `pnpm strings:ios` and `pnpm lint:android`; re-run 4.1's
      comparison and watch the reconciled rows leave the list.
- [ ] **4.3** Reconcile the offline destination's vocabulary.
      iOS: *Nothing in your library is on this device yet*
      (`library.empty.onDevice`), *Nothing downloaded*, *%@ downloaded*.
      Android: *Nothing in your library can be read without a connection*,
      *Nothing on this device*, *%1$s on this device*. These are two different
      promises, not two phrasings.
      **Blocked on the open question**: direction §8.4 records the name as an
      owner decision never taken. Do not pick one. Ask.
- [ ] **4.4** Record the rows marked *platform forces it* as deliberate, in the
      key's own comment, so the next comparison does not re-report them.
      At least three: *Reduce Motion* against *Remove animations* (each
      platform's own setting name), iCloud Drive against Google Drive, and the
      app-icon note. The spec's *a difference the platform forces* clause exists
      for exactly this.
      Verify: re-run 4.1's comparison; the marked rows are annotated, not
      changed.
- [ ] **4.5** Retire the two dead keys.
      `catalogue.strip.hint` and `catalogue_strip_hint` are drawn nowhere on
      either platform — the strip that used them is gone. Confirm with a search
      over both trees before deleting, not from this line.
      Verify: `pnpm strings:ios`, `pnpm lint:android`.
- [ ] **4.6** The publication page's vocabulary, **after `publication-detail`
      archives.** iOS composes a place clause and an availability clause
      (`detail.availability.*`, `detail.provenance.alsoIn %@`); Android ships
      four whole sentences plus a wrapper (`detail_provenance_*`). The refusal
      diverges too — *This cannot be opened until it is on this device* against
      *This one has to be on your device before it opens* — and so does the
      gone screen, one string against three.
      That page's requirements are still in `publication-detail`'s delta and not
      yet in a main spec, which is why this is last and why it is the one item
      that can become a follow-up without leaving a seam half-done.
      Verify: the two platforms' detail pages captured side by side, French,
      for each of the four availability states.

## 5. The check that has to be able to fail

Last, because a gate that fails on pre-existing code blocks eight in-flight
changes.

- [x] **5.1** Write the check with its `--self-test` in the same commit.
      `scripts/` beside `delta-drop-check.mjs` and `partial-tasks-check.mjs`. It
      guards the drawing surface only — bare literals in `Text(`, `alert(`,
      `Button(` labels, `accessibilityLabel`, `contentDescription =`.
      **State its limit in its own header**, as `ios-strings.mjs` does: it cannot
      see a sentence that reaches a view through a variable. The census found
      zero literals in these positions, so this check would have caught none of
      the thirty — it is a backstop against the next one, and claiming otherwise
      is the vacuous shape.
      **Done:** `scripts/drawn-strings-check.mjs`. One script reads Swift and
      Kotlin, because SwiftUI and Compose spell `Text(` the same way. The header
      names six blind spots, and says plainly that the check would have caught
      none of the thirty.
- [x] **5.2** Prove it fails, by name.
      Introduce a bare literal in a drawing position, watch the check name the
      file and line, revert. AGENTS.md §5 requires this in the change that adds
      the guard, and names three checks here that could not fail.
      Verify: `node scripts/<name>.mjs --self-test`.
      **Done, in both directions.** `node scripts/drawn-strings-check.mjs`
      reports `apps/ios/App/RefusedFile.swift:55` and `:58` on the committed
      tree. A copy of `SkippedNotice.swift` with one key replaced by prose is
      reported at line 50, and the reverted copy reports nothing.
      `--self-test` passes 15 of 15 cases.
- [~] **5.3** Wire it into `pnpm lint` and add the `:selftest` script.
      `package.json`, matching how `delta:drop` and `partial:tasks` are wired.
      Verify: `pnpm lint` passes on a clean tree and fails on 5.2's mutation.
      **Half done, and the missing half is blocked by task 2.2.** `package.json`
      gains `strings:drawn` and `strings:drawn:selftest`. The `lint` chain is
      **not** changed, because the check reports two literals that are already
      committed: the refused-file alert's title and its OK button, at
      `apps/ios/App/RefusedFile.swift:55` and `:58`. Wiring it in today fails
      `pnpm lint` for every one of the eight in-flight changes, which is the
      exact hazard this section is ordered last to avoid. Task 2.2 removes both
      literals. After it lands, add `&& pnpm strings:drawn` to the `lint` script
      and tick this task; that is the whole remaining edit. A suppression list or
      a baseline of allowed violations is refused — it would turn the check into
      decoration.

## 6. Gates

- [ ] **6.1** `pnpm lint` — the contract gate, including the new check.
- [ ] **6.2** iOS: `pnpm test:ios`, `pnpm build:ios`, `pnpm build:ios:tests`
      (nothing else compiles the UI tests), `pnpm lint:ios` **from the
      repository root**. A `SIGSEGV` here is a stale build before it is a bug —
      `pnpm clean:swift`, per AGENTS.md §3b.
- [ ] **6.3** Android: `pnpm lint:android`, `pnpm test:android`, and
      `pnpm build:android:tests` — nothing else compiles `androidTest`.
- [ ] **6.4** `pnpm lines:check` — the 800-line cap is a ratchet and this change
      moves code between modules.
- [ ] **6.5** Every capture from 1.7, 2.4, 3.4 and 4.6 referenced in the handoff,
      each with the control it needs. AGENTS.md §6 binds the change, not the
      task: neither exception applies here — nothing is behind a flag, and the
      screenshots are not byte-identical, which is the whole point of them.
- [ ] **6.6** Update `localization`'s row in `docs/openspec/STATUS.md` from the
      verify report, in the same pass as `/opsx:verify`. The row currently
      records five scenarios "built and asserted by nothing" and *Long
      translations* as the unsettled one; 1.7 and 1.8 move both.
