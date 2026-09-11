# Tasks

**What a tick means here.** A tick means the code exists, something asserts it,
and the named command passed. Where a task carries a capture, a tick also means
somebody looked at the picture — not that a preview was rendered. A tick does
**not** mean a translation was reviewed by a speaker of that language; where a
task ships a translation, the tick covers that the four locales resolve and the
layout survives them, and nothing more.

**One open question binds one task**, and it does not block the rest: **4.2** carries
the judgement calls the owner may want to see, and 4.1's table names each one. The
triage itself — *which of the divergences are deliberate* — was answerable from the
tree and is answered in 4.1 and 4.4. The other question — what the offline destination
is called — was answered on 2026-09-06, and design decision 6 records it.

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
- [x] **3.5** Record a refusal's cause where a maintainer reaches it.
      3.3 removed the exception from the screen and put it nowhere. One `[Last
      failure]` section in `Diagnostic.text`, or one `Log.w` call at
      `ReaderViewModel.kt:436` and `:494`, closes it.
      **Blocked on a shorter file.** Either route adds a line to
      `ReaderViewModel.kt`, which `scripts/line-cap.mjs` records at 811 lines.
      Raising that record weakens the ratchet, so this slice shortens the file first.
      Verify: `pnpm gradle :feature:reader:testDebugUnitTest` and `pnpm lines:check`.

      **Done 2026-09-11, the `Log.w` route.** Both catches now name the cause and hand
      it to `logcat` under the tag `StoryArcReader`, which `adb logcat -s StoryArcReader`
      reads and no reader sees. The `[Last failure]` route was refused: `Diagnostic.text`
      is assembled from state the settings module holds, so a refusal in the reader would
      have to be stored somewhere both modules can see, and that is a store for one line
      of English.
      **The file was shortened first, by moving something real.**
      `ReaderViewModel.openPdfText` moved to `PdfTextState.opened(…)`, a factory on the
      type it builds — which is also where iOS builds its twin, in `PdfTextControls.swift`
      rather than in `ReaderModel`. `ReaderViewModel.kt` is **798** lines, so
      `scripts/line-cap.mjs` lost its entry: `pnpm lines:check` said *under the cap at
      last. Delete its line* and now reports *3 recorded file(s), none grew*.
      **Watched red first.** `ReaderFailureSaysNothingInternalTest` gained *the refusal's
      cause reaches a maintainer*, which failed by name on the old tree — *These catches
      discard the exception: [} catch (\_: Exception) {, } catch (\_: Exception) {]* — and
      passes now. It is a source guard for the reason the other three are: this module's
      unit tests run on a bare JVM and a `ReaderViewModel` cannot be built there.
      `pnpm gradle :feature:reader:lint :feature:reader:testDebugUnitTest` — *BUILD
      SUCCESSFUL*, 95 tests, 0 failures.
      **Four resource comments and one test comment said the cause was known to nobody.**
      That was true for five days and is not true now. All five say where it goes, and the
      diagnostic export still does not carry it — which is the half this task did not
      close.

## 4. One state, one name

- [x] **4.1** Regenerate the divergence list and commit it as the work item.
      629 keys pair across the two catalogues by normalised name, 595 carry
      identical English, **34 do not**. Regenerate rather than trusting the
      number here — five changes are in flight and it moves.
      Verify: the list is in this task, with each row marked *wording*,
      *placeholder syntax*, or *platform forces it*.

      **Regenerated 2026-09-11, and the number had moved — as predicted, and further
      than predicted.** `pnpm strings:divergence` (`scripts/catalogue-divergence.mjs`)
      pairs keys by name with separators and format specifiers taken out. On the tree
      before this slice: **824 iOS keys, 836 Android keys, 708 paired, 568 identical
      English, 140 differ** — 27 worded differently, 5 differing only in typography, and
      **108** differing only in each platform's format spelling. The 34 in the line above
      was a count of the first two groups against a smaller tree; it never held the 108.
      The tool is a report and not a gate, and it is wired into no `pnpm lint` chain,
      because a row it prints can be a difference the platform forces. Its header names
      four things it cannot see, the first of which bounds every figure here: **it
      compares English only.**

      **The 108 marked *placeholder syntax* are one rule, not 108 decisions.** iOS writes
      `%@` and `%lld`, Android writes `%1$s` and `%1$d`, and a reader sees the same words.
      Spot-checked across every module; nothing else hides in that group. They are left
      alone, and `ios-strings.mjs`'s own header says why iOS cannot simply adopt the
      positional form: a *key* written `%1$@` is one nothing can ever look up.

      **The 27 marked *wording*, and the 5 marked typography, row by row.** *Reconciled*
      rows are 4.2's; *platform forces it* rows are 4.4's; the rest carry the reason they
      are neither.

      | Row, iOS / Android | Mark | State |
      | --- | --- | --- |
      | `downloads.total` / `downloads_total` | wording | **Reconciled.** Android takes iOS's *Space used by downloads* |
      | `player.back` / `player_back` | wording | **Reconciled.** Android takes iOS's *Back to the book* |
      | `open.in.protected` / `open_in_protected` | wording | **Reconciled.** Android takes iOS's *so StoryArc cannot open it*, which states the cause |
      | `reader.transition` / `reader_transition` | wording | **Reconciled.** iOS takes *Page turn*, which its own EPUB reader and Android both already say |
      | `downloads.manageInDestination` / `downloads_manage_in_destination` | wording | **Reconciled.** Both platforms now state what the figure counts *and* what is still arriving |
      | `theme.pageColour.clear`, `theme.publisherStyles.action`, `theme.publisherStyles.title` / their twins | typography | **Reconciled.** iOS's English takes the typographic apostrophe its own French and German already use |
      | `theme.fontSize.percent` / `theme_font_size_percent` | typography | **Reconciled** with the three above; what is left is the placeholder |
      | `theme.pageTurn.reduceMotion` / `theme_page_turn_reduce_motion` | platform forces it | **Annotated.** Each platform names its own setting |
      | `reader.transition.reduceMotion` / `reader_transition_reduce_motion` | platform forces it | **Annotated.** The same setting, the same two names |
      | `source.kind.localFolder.explanation` / `source_kind_local_folder_explanation` | platform forces it | **Annotated.** iCloud Drive against Google Drive |
      | `appIcon.note` / `app_icon_note` | platform forces it | **Annotated.** Each platform states what its own system does after the change |
      | `catalogue.error.http` / `catalogue_error_http` | platform forces it | **Annotated.** iOS's second value is `HTTPURLResponse.localizedString(forStatusCode:)`, which Android has no localised counterpart for |
      | `home.keepReading` / `home_keep_reading` | wording | **Open, the owner's call.** *Continue reading* against *Keep reading*, which `design.md`'s third open question names as the clearest of them |
      | `reader.fit.screen`, `.width`, `.height`, `.original` / their twins | wording | **Open, the owner's call.** Both rows are labelled *Fit*, so iOS's *Screen* does not repeat it and Android's *Fit to screen* does. Four rows, one choice |
      | `library.cell.progress` / `library_cell_progress` | wording | **Open, blocked.** iOS says *%lld percent read* where Android and both EPUB readers say *%% read*. `AuditWalk.swift:206` and `ReadingContinuityUITests.swift:104` pick covers by matching *100 percent read*, and `AuditWalk.swift` is one of the three shared-harness files AGENTS.md §5 says earns a broad UI run. It belongs to the capture pass |
      | `open.in.unreadable`, `open.in.unsupported` / their twins | wording | **Reconciled, still reported.** Android draws the list of formats iOS draws, M4B and *other audiobooks* included. iOS reaches it through a placeholder, so the two values differ as text while the reader sees the same words — the second thing the tool's header says it cannot see |
      | `player.skip.back`, `player.skip.forward` / their twins | wording | **Open, not a value.** iOS interpolates a formatted interval into *%@ back*; Android pluralises a count into *Back %1$d seconds*. The word order differs because the composition does |
      | `player.speed` / `player_speed` | wording | **Not a divergence.** iOS draws a label and a value, `player.speed` plus `player.speed.value`; Android holds both in one string. The reader sees the same two words |
      | `shelves.delete` / `shelves_delete` | wording | **Open, not a value.** Android draws one string as the long-press label *and* the menu item, so its menu item names the shelf. Splitting it is an edit to `ShelfCover.kt` |
      | `library.folderUnavailable` / `library_folder_unavailable` | wording | **Open, not a value.** iOS names one folder and quotes it; Android joins several names into one sentence, where a quotation mark would read wrong. Two notice shapes, not two words |
      | `sources.removeDownloads.title` / `sources_remove_downloads_title` | wording | **Open, a convention.** Android's confirmation titles name the source and iOS's do not, on this key and on `sources.remove` beside it. Reconciling it changes a convention on two keys and a Swift signature |
      | `settings.reset.body` / `settings_reset_body` | typography | **Open, a presentation difference.** The same words; Android breaks them into two paragraphs. `SourceDetail.swift` records a confirmation body that stopped at *No files* at the largest text size and does not scroll, so the blank line is not free on iOS |
      | `downloads.failed` / `downloads_failed` | placeholder syntax | **Not a divergence.** Each platform carries one pluralised copy and one flat copy of this sentence, so the words agree and only the plural machinery differs. The flat copy reads *1 attempts* on **both** platforms, which is a defect of each against itself and belongs to `offline-downloads` |
      | `library.filter.decade` / `library_filter_decade` | placeholder syntax | **Not a divergence, a key name.** iOS's second key is `library.filter.decade %lld` and Android's twin is `library_filter_decade_label`; all four languages agree. The pairing rule strips specifiers, so the two iOS keys land on one name |
      | `shelves.addTo` / `shelves_add_to` | placeholder syntax | **Not a divergence, a key name.** `shelves.addTo %@ %@` is iOS-only and pairs with nothing; the two `Add to…` values are identical |

      **After 4.2 and 4.4: 823 iOS keys, 836 Android keys, 708 paired, 575 identical
      English, 133 differ** — 22 wording, 1 typography, 110 placeholder syntax. Two rows
      moved into the placeholder group rather than out of the list, because reconciling
      the words left the format spelling as the only difference.
- [~] **4.2** Reconcile the rows marked *wording*, one state at a time.
      A state whose two platforms agree is better than one where they do not,
      whatever else is open — so this is the one group in the change that may
      land partly without leaving a seam open.
      Verify: `pnpm strings:ios` and `pnpm lint:android`; re-run 4.1's
      comparison and watch the reconciled rows leave the list.

      **Nine states reconciled on 2026-09-11, and each row in 4.1's table says which way
      it went and why.** The rule in every case is the spec's: *the more informative one
      is the agreed wording*, and where both were equally informative, the words the app
      already uses for that state elsewhere won.

      - `downloads.total`. Android said *Space used* and iOS says what the figure counts.
        4.3 judged this key to name a completed transfer, so keeping the word *downloads*
        is that judgement applied. Both Android modules that draw it moved, in four
        languages each.
      - `player.back`. Android said *Go back*; iOS says where the button goes.
      - `open.in.protected`. Android said *and StoryArc cannot open it*; iOS says *so*,
        which names the protection as the cause. 2.2's record claimed iOS took this
        sentence from Android word for word, and the conjunction is where that was not
        true.
      - `reader.transition`. iOS's comic reader said *Transition* while its **own** EPUB
        reader says *Page turn*, in all four languages, and so does Android. Three
        surfaces of four already agreed, so iOS's fourth moved to them. This is the
        spec's first scenario — one condition, one name — as much as its cross-platform
        one.
      - `downloads.manageInDestination`. iOS states what the figure counts and Android
        stated what is still arriving. Neither sentence was wrong, so both survive: the
        third sentence now reads *Everything on this device, and anything still arriving,
        is in Downloads.* Every clause was already translated on one platform or the
        other, so nothing here is a new translation.
      - The four typography rows. iOS's English said `publisher's` where its own French
        and German say `l’éditeur` and Android says `publisher’s`.

      **Two consequences, both real.**
      `reader.transition` is drawn as a row a UI walk reaches by its label, so
      `SweepComicReader.swift`, `CurlWalk.swift` and one comment in `SweepWalk.swift`
      moved with it. `pnpm build:ios:tests` compiles them and exits 0. **No UI run proved
      those two walks still reach the row**; the simulator is serialised and this pass did
      not take it. That is the one thing 4.2 leaves unproven.

      **Verified.** `pnpm strings:ios` — *every key resolves, in en, fr, de, es*.
      `pnpm lint:android` — *BUILD SUCCESSFUL*, so no `MissingTranslation` and no
      `ExtraTranslation` in any of the five modules that changed. `pnpm test:android` —
      2326 tests, 0 failures. `pnpm test:ios` — 2501 tests in 328 suites passed.
      `pnpm strings:divergence` shows every reconciled row gone from the list.

      **Open, and why: thirteen rows.** Two are the owner's call (`home.keepReading`, and
      `reader.fit.*` as one choice of four), one is blocked on a shared-harness UI run
      (`library.cell.progress`), and the rest are not value edits at all — a composition,
      a convention, or a notice shape. 4.1's table carries the reason for each. A tick
      here would claim a reconciliation that has not happened.
- [x] **4.3** Reconcile the offline destination's vocabulary.
      iOS: *Nothing in your library is on this device yet*
      (`library.empty.onDevice`), *Nothing downloaded*, *%@ downloaded*.
      Android: *Nothing in your library can be read without a connection*,
      *Nothing on this device*, *%1$s on this device*. These are two different
      promises, not two phrasings.
      **Decided 2026-09-06 by the owner. The open question is answered, not
      guessed, and this paragraph is the record of it.** The destination is named
      by its **location** — *on this device* — and the empty state carries the
      **capability**. *On this device* is short, concrete, and is the vocabulary
      both platforms already use for this idea in their own interfaces; it is
      what a reader scans a list for. *Can be read without a connection* is the
      more truthful promise but the poorer label: it reads as a sentence rather
      than a place, and it wraps badly at the largest text size, where Spanish is
      this app's measured worst case for length. So the promise moves to the one
      surface with room to read it — the empty state, which exists to say what a
      place is for.
      **Done.** Three keys a side, four languages each, same meaning and same
      placeholder count. iOS `settings.downloads.none` and
      `settings.downloads.summary %@` take Android's *Nothing on this device* and
      *%@ on this device*. Both platforms' empty state becomes *Nothing in your
      library is on this device yet. What you keep here can be read without a
      connection.* — the location, then the promise, two sentences and not a
      paragraph. Two register slips went with the rewrite because the sentence
      was being written anyway: iOS's German said *deiner* where 104 of its 107
      German strings say *Ihre*, and Android's Spanish said *su biblioteca* where
      both catalogues otherwise say *tu biblioteca*.
      **Judged to mean a completed transfer, so kept as *downloaded*:**
      `downloads.total`, `privacy.downloads %@`, `downloads.failed %@ %lld`,
      `downloads.pending` and `library.filter.download.*`. The last is the axis a
      reader filters by — whether the app fetched a file — which is a different
      question from where the file is.
      **Judged to name the place, and already agreed on both platforms:**
      `downloads.onDevice`, `catalogue.entry.downloaded`, `kavita.kept`,
      `source.onThisDevice` and `library.availability.onDevice` all draw *On this
      device*, and `tab.downloads` / `destination_downloads` both name the
      destination *Downloads*. Nothing to reconcile.
      **The accessibility labels were checked, not assumed.** Neither platform
      gives these three surfaces a label of their own: the settings row, the
      empty sentence and the destination's tab are announced from the text they
      draw, so the drawn name and the announced name are one string.
      **One consequence for 4.2 to carry.** The figure in the settings row counts
      what `DownloadStore.bytesOnDisk()` weighs — what StoryArc fetched or
      imported, not a folder the reader added. iOS states that on the screen the
      row opens, in `downloads.manageInDestination`; Android's mirror of that key
      does not. That row is already on 4.2's list as *wording*, and it matters
      more now that both platforms name the device.
      Verify: `pnpm strings:ios` — *every key resolves, in en, fr, de, es*;
      `pnpm test:ios` — 2148 tests in 280 suites passed; `pnpm gradle
      :feature:library:testDebugUnitTest` — build successful.
      `OfflineDestinationNameTests` and `OfflineDestinationNameTest` were watched
      red first: iOS on *en states settings.downloads.none as "Nothing
      downloaded", which does not name the location*, Android on *en states the
      empty shelf as "Nothing in your library can be read without a connection.",
      which does not name the location*.
- [x] **4.4** Record the rows marked *platform forces it* as deliberate, in the
      key's own comment, so the next comparison does not re-report them.
      At least three: *Reduce Motion* against *Remove animations* (each
      platform's own setting name), iCloud Drive against Google Drive, and the
      app-icon note. The spec's *a difference the platform forces* clause exists
      for exactly this.
      Verify: re-run 4.1's comparison; the marked rows are annotated, not
      changed.

      **Done 2026-09-11. Five rows, and the fifth was not on this line.** Each one is
      annotated on **both** platforms — an `xcstrings` `comment` on iOS, an XML comment
      above the string on Android — and every annotation names the other platform's
      wording, says which platform facility forces it, and cites `localization` / One
      state, one name. No value changed.

      - *Reduce Motion* against *Remove animations*, in **two** places rather than one:
        `reader.transition.reduceMotion` in the comic reader and
        `theme.pageTurn.reduceMotion` in the EPUB reader, with their Android twins. The
        line above counted this as one row; the catalogues carry two.
      - iCloud Drive against Google Drive, on `source.kind.localFolder.explanation`.
      - The app-icon note. Android's comment already explained its own half — *this
        platform has no way to change an icon in place* — and now says the iOS half is
        deliberate too.
      - **`catalogue.error.http`, found by the regeneration.** iOS's sentence carries a
        second value, the status phrase from
        `HTTPURLResponse.localizedString(forStatusCode:)`. Android has no localised
        counterpart, so its value states the code alone. The proposal reads this row as
        Android having *dropped* the reason phrase, and that is not what it is: the phrase
        comes from a platform facility only one platform has. Reconciling it would mean
        writing a status-code table into `feature/library` in four languages, which is a
        change nobody has proposed.

      Verify: `pnpm strings:divergence` still reports all five, which is correct — the
      tool is a report and cannot read a comment. What the annotation stops is the **next
      reader** re-opening a settled question, which is what the task asks for.
- [x] **4.5** Retire the two dead keys.
      `catalogue.strip.hint` and `catalogue_strip_hint` are drawn nowhere on
      either platform — the strip that used them is gone. Confirm with a search
      over both trees before deleting, not from this line.
      Verify: `pnpm strings:ios`, `pnpm lint:android`.

      **Done 2026-09-11, and there was one key rather than two.** A search over both
      trees for `catalogue.strip.hint`, `catalogue_strip_hint`, `strip_hint` and
      `stripHint` found the iOS entry in `LibraryFeature`'s catalogue and **nothing at all
      on Android**: `catalogue_strip_hint` had already left every `values*/strings.xml`.
      The only other mention is the design document that retired it,
      `docs/designs/ui-revamp-2026-08.md:804`, which records it as retired and is right.
      The iOS entry is deleted, in all four languages.
      `pnpm strings:ios` — *every key resolves, in en, fr, de, es*; the iOS key count went
      from 824 to 823. `pnpm lint:android` — *BUILD SUCCESSFUL*, with nothing to remove.
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

      **Left open on 2026-09-11, deliberately.** `publication-detail` is still active and
      is being worked in another worktree, so its delta is still the only place that
      page's requirements exist. Touching those keys now would reconcile a vocabulary that
      change is still writing. The pass that closed 4.1, 4.2, 4.4 and 4.5 did not read
      this row's keys and did not change one of them.

## 5. The check that has to be able to fail

Last, because a gate that fails on pre-existing code blocks eight in-flight
changes.

- [x] **5.1** Write the check with its `--self-test` in the same commit.
      `scripts/` beside `delta-drop-check.mjs` and `partial-tasks-check.mjs`. It
      guards the drawing surface only — bare literals in `Text(`, `alert(`,
      `Button(` labels, `accessibilityLabel`, `contentDescription =`.
      **State its limit in its own header**, as `ios-strings.mjs` does: it cannot
      see a sentence that reaches a view through a variable. It is a backstop
      against the next leak, and claiming more for it is the vacuous shape.
      **Done:** `scripts/drawn-strings-check.mjs`. One script reads Swift and
      Kotlin, because SwiftUI and Compose spell `Text(` the same way. The header
      names six blind spots.
      **The census in `design.md` is wrong on one file, and this task repeated
      the error.** Both said zero literals in these positions, so the check
      would have caught none of the thirty. It catches two: the refused-file
      alert's title and its OK button, at `apps/ios/App/RefusedFile.swift:55`
      and `:58`, which are two of the six that file holds. Both are
      `Text(verbatim:)`, so neither becomes a key and `strings:ios` is blind to
      them. This check is the only thing that reports them. The other
      twenty-eight do reach a view through a variable, and section 1 is their
      gate.
- [x] **5.2** Prove it fails, by name.
      Introduce a bare literal in a drawing position, watch the check name the
      file and line, revert. AGENTS.md §5 requires this in the change that adds
      the guard, and names three checks here that could not fail.
      Verify: `node scripts/<name>.mjs --self-test`.
      **Done, in both directions.** `node scripts/drawn-strings-check.mjs`
      reports `apps/ios/App/RefusedFile.swift:55` and `:58` on the committed
      tree. A copy of `SkippedNotice.swift` with one key replaced by prose is
      reported at line 50, and the reverted copy reports nothing.
      `--self-test` passes 19 of 19 cases. Delete any one of the five position
      patterns and a named case fails.
- [x] **5.3** Wire it into \`pnpm lint\` and add the \`:selftest\` script.
      \`package.json\`, matching how \`delta:drop\` and \`partial:tasks\` are wired.
      Verify: \`pnpm lint\` passes on a clean tree and fails on 5.2's mutation.
      **Done on 2026-09-06, after task 2.2 landed.** The \`lint\` chain now ends
      \`&& pnpm strings:ios && pnpm strings:drawn\`. The self-test stays out of
      \`lint\` and runs in CI, because that is how \`openspec:workflows:check\` and
      \`openspec:workflows:selftest\` are split. \`.github/workflows/contract.yml\`
      gains its own \`pnpm strings:drawn\` step: no workflow runs \`pnpm lint\`, so
      the \`lint\` clause alone would leave the check in no automated gate.
      Proved able to fail at the \`lint\` level, not only in the self-test. A
      \`Text("This sentence was never translated")\` added to
      \`SkippedNotice.swift\` gave \`pnpm lint\` exit 1 and this line:
      \`SkippedNotice.swift:207  Text(  "This sentence was never translated"\`.
      Reverted; the clean tree gives exit 0.
      A suppression list or a baseline of allowed violations is refused — it
      would turn the check into decoration.

## 6. Gates

- [x] **6.1** `pnpm lint` — the contract gate, including the new check.
      **2026-09-11.** Exit 0, all twenty checks, `strings:ios` and `strings:drawn`
      among them: *iOS strings: every key resolves, in en, fr, de, es* and
      *drawn-strings: no bare sentence in a drawing position under apps/*.
- [x] **6.2** iOS: `pnpm test:ios`, `pnpm build:ios`, `pnpm build:ios:tests`
      (nothing else compiles the UI tests), `pnpm lint:ios` **from the
      repository root**. A `SIGSEGV` here is a stale build before it is a bug —
      `pnpm clean:swift`, per AGENTS.md §3b.
      **2026-09-11.** `pnpm test:ios` — *2501 tests in 328 suites passed*.
      `pnpm build:ios` and `pnpm build:ios:tests` — exit 0, no `error:` line in either.
      `swiftlint lint --strict --no-cache` from the repository root — *0 violations, 0
      serious in 811 files*. No `SIGSEGV`. `pnpm test:ios:epub` was **not** run: it needs
      a booted simulator, and the EPUB module's change here is four catalogue values and
      two comments, with no Swift touched.
- [x] **6.3** Android: `pnpm lint:android`, `pnpm test:android`, and
      `pnpm build:android:tests` — nothing else compiles `androidTest`.
      **2026-09-11.** `pnpm lint:android` — *BUILD SUCCESSFUL*, so no
      `MissingTranslation` and no `ExtraTranslation` in the five modules that changed. The
      `ViewModelConstructorInComposable` error 1.5 recorded in `:feature:library:lint` is
      **gone**; that file was fixed on `main` in the meantime. `pnpm test:android` —
      2326 tests, 0 failures, 0 errors, across nine modules.
      `pnpm build:android:tests` — *BUILD SUCCESSFUL*.
- [x] **6.4** `pnpm lines:check` — the 800-line cap is a ratchet and this change
      moves code between modules.
      **2026-09-11.** *3 recorded file(s), none grew, nothing new crossed its language's
      cap.* The record is three rather than four because 3.5 took
      `ReaderViewModel.kt` from 811 lines to 798 and deleted its line, which the check
      asked for by name. `pnpm lines:selftest` — *15 checks passed*.
- [ ] **6.5** Every capture from 1.7, 2.4, 3.4 and 4.6 referenced in the handoff,
      each with the control it needs. AGENTS.md §6 binds the change, not the
      task: neither exception applies here — nothing is behind a flag, and the
      screenshots are not byte-identical, which is the whole point of them.

      **Still owed, and 4.2 added one frame to the list.** `reader.transition` now draws
      *Page turn* in the comic reader's menu on iOS, and the two UI walks that reach that
      row by its label were edited with it. They compile; no run has reached the row. The
      capture pass wants `-only-testing:StoryArcUITests/CurlWalk` and
      `-only-testing:StoryArcUITests/SweepComicReaderTests` before it takes anything else.
- [ ] **6.6** Update `localization`'s row in `docs/openspec/STATUS.md` from the
      verify report, in the same pass as `/opsx:verify`. The row currently
      records five scenarios "built and asserted by nothing" and *Long
      translations* as the unsettled one; 1.7 and 1.8 move both.
