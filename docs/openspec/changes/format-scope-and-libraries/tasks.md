# Tasks

Phase 0 is a build-engineering spike, and it gates everything. If libarchive
cannot be built cleanly for all six ABIs, CBR and CBT stay unsupported and the
rest of this change does not happen.

## Phase 0 — libarchive integration spike

- [x] **0.1a** Build libarchive for iOS device and simulator, and for Android
      arm64-v8a. **Done** — 131/131 sources compile for both iOS slices, Android
      builds via CMake + NDK 29, and a real TAR reads correctly with the right
      entry names, sizes and format identification.
- [x] **0.1b** The remaining three Android ABIs. **Done, and all four build from
      the vendored sources** with NDK 29 and the hand-authored `config.h`: 26/26
      files compile clean for `aarch64`, `armv7a`, `x86_64` and `i686`. Sizes in
      6.2.
- [x] **0.1c** Read an actual RAR. **Done, and no hand-made fixture was needed.**
      libarchive reads a real WinRAR-produced RAR5 `.cbr` — four entries, right
      names and sizes — and reads all three of the store-mode fixtures in 1.1
      byte-identically. Same reader, same code path.
- [x] **0.2** Trim the build. **Done, and the plan was wrong**: libarchive exposes
      no per-format CMake toggles, so nothing can be "compiled out". Dead-code
      stripping does it instead — 7.24 MB of objects becomes **235 KB per Android
      ABI and 202 KB on iOS**, because only the RAR, RAR5 and TAR readers are
      reachable.
- [x] **0.3** Confirm the licence. **Done, per file rather than per project**,
      because libarchive's own `COPYING` warns of "widely varying licensing
      terms". The three readers we use are all BSD-2-Clause with no UnRAR
      reference: `rar.c` (Kientzle, Mejia), `rar5.c` (Antoniak), `tar.c`.
      Recorded in `THIRD_PARTY_NOTICES.md`.
- [x] **0.4** Add a `SECURITY.md` entry: libarchive parses untrusted input in C.
      **Done** — `SECURITY.md` records RAR and TAR parsing as an untrusted-input
      surface, with the mitigation and the reason libarchive was chosen over the
      UnRAR-derived decoders.
- [x] **0.5** Decide how the library is vendored. **Done — copied sources, one
      hand-authored `config.h`, one copy shared by both builds.** Recorded in
      [`third_party/libarchive/VENDORING.md`](../../../../third_party/libarchive/VENDORING.md).

      Not prebuilt binaries: iOS has to compile the sources anyway, and six `.a`
      files plus an `.xcframework` are blobs no reviewer can check against
      upstream. Not a submodule: `git clone` without `--recursive` would leave an
      empty directory, and this task's own test is whether a contributor can
      build the app. Copied sources make plain `git clone` enough; the price is
      manual CVE tracking, which `VENDORING.md` states rather than hides.

      The sources live in a nested SwiftPM package because SwiftPM will not
      compile C outside its own package and the files must be shared with the
      Android build rather than duplicated. `StoryArcKit` depends on it by
      relative path; `core:format` compiles the same files with CMake.

      **26 of libarchive's 132 sources**, not all of them. The other 106 are
      parsers and writers for formats StoryArc never opens, and leaving them out
      is a smaller attack surface rather than only a smaller repository.

## Phase 1 — Fixture corpus

- [x] **1.1** Extend `packages/test-fixtures/scripts/generate.py` with CBR
      fixtures. **Done, and the premise was wrong**: a RAR *compressor* is
      proprietary, but the RAR *container* is documented, and store mode has no
      Huffman coding and no LZ window — so the generator writes its own RAR4 and
      RAR5 headers in about eighty lines. No hand-made fixture, no downloaded
      artwork, no new dependency, and the corpus stays synthetic and tiny.
      `rar4-store.cbr` and `rar5-store.cbr` extract byte-identical pages through
      libarchive.
- [x] **1.2** CBT fixtures. **Done** — `tar-store.cbt` and
      `tar-nested-chapters.cbt`, written with stdlib `tarfile`.
- [x] **1.3** A CB7 fixture. **Done** — `refused.cb7` carries a valid 7z
      signature and nothing else, because detection fires on the signature before
      any entry is read.
- [x] **1.4** Record every expectation in `manifest.json`. **Done** — 19 comic
      archives, still no hashes.
- [x] **1.5** A **solid RAR5** fixture. **Done, vendored rather than made by
      hand.** Solid means nothing without compression and a RAR compressor is
      proprietary, so `generate.py` cannot write an honest one. Instead
      `comics/rar5-solid.cbr` is `test_read_format_rar5_solid.rar` from
      libarchive 3.8.1's own test suite, BSD-2-Clause, 1050 bytes, committed
      verbatim with its provenance in `generate.py` and the corpus README. Better
      provenance than a hand-made file: known origin, known licence, and the exact
      archive libarchive's suite reads. Its entries are `.bin` rather than images,
      so it pins solid *parsing* and the solid flag, not a solid comic opening —
      recorded in the manifest, and the reason its expected page count is zero.

## Phase 2 — Format layer

CBT does not need libarchive at all, so it shipped first — see 2.6. What is left
here is RAR, which is the only format that genuinely needs a decoder.

- [x] **2.1** C interop layer, **both platforms done**. `RarDecoder` is the whole
      of libarchive's job on each side — a path in, entry bytes out — with only
      the two RAR readers registered, so no other parser is reachable. iOS goes
      through SwiftPM's C target; Android through CMake and a JNI shim built for
      all four ABIs. `RarComicArchive` decodes compressed pages when it has a
      local file and reports them as skipped when it does not, so a remote CBR
      still indexes from headers alone. Android also checks that the native
      library actually loaded, since a missing `.so` is a packaging problem rather
      than a bad archive and must not be reported as one.
- [x] **2.2** Read RAR and TAR entries through `RandomAccessSource`. **Done** —
      both readers take a source rather than a file, so indexing a CBR or CBT on
      an SMB share reads headers only.
- [x] **2.3** Detect solid RAR and record the publication as non-streamable at
      index time. **Done, natively** — `RarReader` reads the archive-level solid
      flag and every entry's own flag, on both generations, so the answer arrives
      before any decoder is involved. That matters because of the finding below:
      libarchive would list the first entry and only then fail. A solid archive is
      now refused as `solidArchive`, which is named separately from
      `unsupportedContainer` because the container *is* supported.
- [x] **2.4** Remove CB7 from the supported set; assert the named refusal.
      **Done** — `Container.displayName` carries the name on both platforms, so a
      7-Zip comic is refused as "7-Zip" rather than as a parse failure.
- [x] **2.5** Mirror the tests on both platforms against the same fixtures, as
      the ZIP layer does. **Done** for TAR and RAR. iOS 98 tests, Android 85, both
      reading the same `manifest.json`.
- [x] **2.6** **CBT, with no C at all.** TAR is 512-byte blocks with fixed-offset
      ASCII fields — no compression, no central directory, no bit-packing — so
      `TarReader` is written on both platforms for the same reason ADR-0008 gives
      for the ZIP reader. Reads go through `RandomAccessSource`, so indexing a CBT
      on an SMB share fetches one 512-byte header per entry instead of the file.
      GNU long names and pax `path=` records are handled, every header checksum is
      verified, and a header claiming more bytes than the file holds yields no
      entry. Format sniffing now reads 265 bytes rather than 8, because TAR's
      magic sits at offset 257 and one 265-byte read is the same single round trip.
      iOS: 86 tests pass. Android: 73 pass.
- [x] **2.7** **RAR headers, also with no C.** Everything indexing needs — page
      names, page sizes, the cover, solid, encrypted, and whether an entry is
      stored — lives in RAR headers, and headers carry no compression. `RarReader`
      parses both RAR4 and RAR5 on both platforms and reads stored entries
      directly; a compressed entry throws `needsDecoder`, which is the one seam
      libarchive fills. A CBR therefore indexes today, and `RarComicArchive`
      opens whatever is stored while counting compressed pages as skipped, which
      is what `publication-formats` asks for. Guards: entry count capped, header
      size capped, the vint reader cannot spin on a run of continuation bytes,
      and a header claiming a size past the end of the file stops the walk.
- [x] **2.8** **A plain folder of images**, which `publication-formats` lists
      alongside the archive formats and which had a name in the enum and no
      reader. `ImageFolderArchive` sits behind the same `ComicArchiveReading`
      interface with the same page filter, natural sort and `ComicInfo.xml`
      handling, so `ch10` follows `ch2` in a folder exactly as it does inside a
      CBZ. Symbolic links are not followed, and the resolved path is re-checked
      against the root at read time: a folder is chosen by the user but is still
      untrusted input, and a link is how one would read a file outside the
      publication.
- [x] **2.9** **EPUB structure, with no Readium.** An EPUB is a ZIP holding XML,
      so `EpubReader` reads metadata, reading order, table of contents, cover and
      the fixed-layout flag with no dependency — which is everything the *library*
      needs to shelve a book. Readium remains necessary only to lay out reflowable
      XHTML, which is a rendering engine rather than a parser, and stays in the
      reader-theming change.

      Both EPUB generations are handled explicitly rather than by assuming the
      modern shape, because they differ in exactly the places a parser gets wrong:
      EPUB 2 keeps its contents in an NCX reached through the spine's `toc`
      attribute where EPUB 3 uses a nav document found by a manifest property, and
      names its cover with a metadata `meta` where EPUB 3 uses
      `properties="cover-image"`. A reader that assumed EPUB 3 would silently lose
      the contents and cover of every older book on a shelf.

      Four new fixtures: EPUB 3, EPUB 2, fixed-layout, and one with no package
      document — which is refused by name rather than opened as an empty book.
- [x] **2.10** **`ComicInfo.xml`, parsed rather than merely excluded.** The archive
      readers already pulled the bytes out; nothing read them. `ComicInfo` reads
      every field `publication-formats` names — series, number, volume, title,
      summary, writer, penciller, publisher, release date, page count, language —
      plus the two parts of the `<Pages>` list that change behaviour: a designated
      cover that is not page 1, and explicitly-marked double-page spreads, which
      are believed in preference to `PageDecoder.isSpread`'s aspect-ratio guess.

      Reading direction resolves through the domain's existing
      `ReadingDirection.inferred`, so the format layer does not get a second
      opinion. `Manga=YesAndRightToLeft` declares right-to-left and `Manga=No`
      declares left-to-right, but **`Manga=Yes` declares nothing** — it says the
      publication is manga, not which way it reads, and translated manga is
      routinely left-to-right — so it falls through to the language rule. All three
      branches are tested.

      Issue number stays a string: "3.5" and "Annual 1" are both real, and turning
      either into a number loses the publication's identity.
- [x] **2.11** **Filename metadata, for publications that carry none.**
      `FilenameMetadata` infers series, volume, issue and year from a filename, and
      every value it produces is marked inferred — which is the part
      `publication-formats` actually cares about, because an authoritative source
      has to be able to replace a guess without raising a conflict the app
      invented.

      The case table lives in the corpus manifest rather than in either test file,
      so both platforms agree on what "common naming pattern" means instead of each
      inventing its own list. Eight real-world shapes, including three awkward ones
      chosen on purpose: a series whose own name ends in digits, scanlation-group
      brackets that are not part of the title, and a zero-padded issue that must
      sort with its unpadded twin.

      Two guesses are deliberately conservative, and both are marked `ponytail:`
      with their ceiling. A year is only read from parentheses, because a bare
      four-digit number is more often part of a title. A trailing bare number is
      capped at three digits for the same reason — a four-digit chapter needs an
      explicit `c` marker, which every convention that goes that high uses.
- [x] **2.12** **Truncated-archive recovery**, which was a standing spec
      violation. `publication-formats` requires opening whatever pages can be read
      and stating how many were skipped; both readers instead threw `unreadable`
      when a ZIP's central directory was missing, and the corpus's `truncated.cbz`
      already recorded `isRecoverable: true` against that.

      `ZipReader.recovering` now rebuilds an index by scanning for local file
      headers. The fixture is 60% of a twelve-page archive and yields **eleven
      pages, all of which decode** — asserted rather than assumed, because an index
      rebuilt by scanning is worthless if the bytes behind it do not come out.

      Two properties are deliberately given up, and both are recorded in the code:
      the scan is linear, so recovery is the one place this layer abandons ranged
      reads — inherent, since it exists because there is no index to seek with; and
      local headers are trusted for sizes, which ADR-0008 otherwise forbids,
      because in recovery there is nothing better. It is a separate entry point
      rather than a silent fallback for exactly that reason, and `isRecovered` tells
      a caller which kind of index it is holding.

      A local header that used a data descriptor declares no size, so `inflate`
      grew a path for an unknown output length: the buffer starts at a multiple of
      the compressed size and doubles while the result exactly fills it.
- [x] **2.13** **Cover selection**, the rule `publication-formats` states and no
      container implemented: the first page *in reading order*, unless
      `ComicInfo.xml` designates another. Now one function shared by every
      container, so a CBZ and a CBT cannot disagree about which page a reader sees
      first.

      A designated index outside the page list is **ignored rather than clamped**.
      `ComicInfo` counts archive entries while the page list has had non-page
      entries filtered out, so a stale index is a real possibility — and showing an
      arbitrary middle page would look like a bug in the reader rather than in the
      file.

      EPUB uses its declared cover. The spec's fallback — render the first spine
      item when nothing is declared — needs a renderer, so it lands with the
      reflowable reader; the test says so rather than leaving it silently missing.
      Lazy extraction is an indexer concern, not a format-layer one.
- [x] **2.14** **`PublicationIndexer`**, the seam between this layer and the
      library: a file in, a `Publication` out. Everything below it knows about
      containers; everything above it knows about books.

      Metadata precedence is the point of it. Embedded beats a filename guess,
      **field by field rather than wholesale** — a `ComicInfo` carrying only a
      series must not discard a year the filename knows — and every record carries
      a `MetadataOrigin` so an authoritative source can replace it later without
      raising a conflict the app invented.

      Two behaviours are deliberate and easy to mistake for bugs. A solid RAR4 is
      **indexed and listed** rather than dropped, marked `refused` and not openable,
      because a comic the user can see in the folder and not in the library sends
      them hunting. And identity is **path-keyed**, not content-digested: hashing a
      400 MB archive during a scan of 10 000 files would break `local-library`'s
      three-second requirement outright. `contentDigest` exists for the background
      pass that upgrades an identity later, marked `ponytail:` with the cost of not
      having it yet — a moved file loses its place until then.
- [x] **2.15** **`LibraryScanner`**, which walks a folder and emits publications as
      it finds them. `local-library` asks for four things at once — progress as a
      count, browsing what is already found, cancellation, and resumability — and a
      stream delivers all four rather than three. `AsyncStream` on iOS, `Flow` on
      Android.

      A directory holding images and no publication files is **itself one
      publication**; a directory holding publication files is a shelf. Deciding per
      directory is what lets an unpacked comic sit beside packed ones.

      A refused publication is reported as *found* and marked unopenable, not
      skipped: the library should list it and say why. Only a file that could not be
      indexed at all is skipped, and always with a reason a person can act on.

      One real bug, caught by the cancellation test on Android: emitting from inside
      a broad `catch` swallowed `AbortFlowException`, so a downstream `take` would
      appear to cancel while the scan carried on and reported the cancellation
      itself as a skipped file. The emit is now outside the `try` and
      `CancellationException` is re-thrown.
- [x] **2.16** **`CoverLoader`**, which is what makes the cover requirement
      affordable. `publication-formats` asks for the first screen of a 10 000-item
      scan within three seconds *and* for covers extracted lazily as rows approach
      the viewport — so indexing records where a cover is and this reads it only
      when a row is about to be seen. Every load is bounded by the size it will be
      drawn at, because a 2000×3000 page costs 24 MB of pixels to fill a thumbnail.

      PDF is separated deliberately: its cover is *rendered*, not read, and a caller
      batching thumbnails should know which it is doing. `anyCover` hides the
      difference for a grid cell, which has no reason to care.

      **A device-only bug, and the reason the instrumented suite is not optional.**
      Android's regex engine is ICU rather than the JVM's, and it rejects
      `\{[^}]*}` where the desktop JVM accepts it — so `FilenameMetadata` passed
      every unit test and threw `ExceptionInInitializerError` the first time it ran
      on hardware. A green JVM suite is not evidence that a regex works.

## Phase 3 — Page decoding

- [x] **3.1** iOS: `CGImageSource` decode with `ThumbnailMaxPixelSize`
      downsampling, and re-decode at higher resolution on zoom. **Done** —
      `PageDecoder` on ImageIO. A 2000x3000 corpus page decodes to exactly that,
      downsamples to 400x600 when bounded to 600 on the long edge, refuses to
      upscale, and rejects non-image bytes with a named error. ImageIO runs on the
      macOS host, so this is a unit test.
- [x] **3.2** Android: `ImageDecoder` with `setTargetSize`, same behaviour. No
      Coil. **Done** — identical numbers to iOS. `ImageDecoder` and `Bitmap` are
      framework stubs off-device, so the decode assertions run as 7 instrumented
      tests on an emulator, in a CI job on `main` only. The size arithmetic is
      unit-tested on both platforms, which is why `targetSize` returns a plain
      `PageSize` rather than `android.util.Size`.
- [x] **3.3** Compare a decoded fixture page across platforms and record the
      tolerance. **Done, and the tolerance is recorded in both test files.**

      `large-page.cbz` is one flat colour, which is what makes the comparison
      mean anything: a full-size decode has nothing to interpolate, so any
      difference would be a colour-space conversion rather than resampling. Both
      platforms read the expected triple from the shared manifest — hard-coding it
      twice would let the two drift by editing one file — and both assert
      `(185, 199, 243)` **exactly** at full size.

      **Downsampled tolerance: ±1 per channel.** ImageIO and `ImageDecoder` are
      different resamplers, so at a 5:1 reduction their rounding is not required
      to agree bit for bit. On a flat colour one step is the honest bound: wider
      would hide a real difference, narrower would assert an implementation detail
      of one platform. Measured, both are within it.

## Phase 4 — PDF

Both platforms render PDF with a system framework, so this phase adds no
dependency at all. Fixtures: `text-pages.pdf` (a real text layer and an outline)
and `image-pages.pdf` (the scanned-comic case), both written by `generate.py`.

- [x] **4.1** iOS: PDFKit, with text selection, in-publication search and
      outline. **Done at the format layer.** `PdfDocumentReader` exposes
      `hasTextLayer`, per-page `text`, a case-insensitive `search` returning page
      indices, and the outline with resolved destinations. Text *selection* is a
      reader-UI affordance over that text layer; the layer is here and tested,
      the gesture is not, because no reader UI exists yet.
- [x] **4.2** Android: system `PdfRenderer`, pages as images. **Done**, verified
      on an emulator: 9 instrumented tests. Page-on-demand is structurally proven
      — nothing rasterises when a document opens, and any single page renders
      without touching the others — but **not** yet measured on a
      several-hundred-megabyte document. That measurement needs a large fixture,
      which the corpus deliberately does not carry; do it against a real file
      before 1.0.
- [x] **4.3** Hide text-dependent controls on Android. **Done, and by absence
      rather than by a branch.** The reader UI now exists on both platforms and
      Android's reader has no text, search or outline control to hide, because
      `PdfDocumentReader` there exposes no API for any of them and no
      `hasTextLayer` either. There is nothing for a control to bind to, so there is
      no state in which one could appear disabled. A property that always returned
      `false` would have invited a caller to treat it as a real answer; the
      strongest form of "hidden, never disabled" is a capability that does not
      exist in the type system.
- [x] **4.4** Assert the same page renders at the same aspect ratio and fit on
      both platforms. **Done, exactly rather than within a tolerance.** Both
      readers report page size in *points* rather than pixels, so both assert 612
      x 792 and 200 x 300 from the same manifest; both bound the longest edge with
      the same never-upscale rule and assert 100 x 150 at a 150-pixel bound; and
      both sample the centre pixel of a rendered page and assert the same
      `(37, 91, 151)`, which proves the raster happened rather than a blank
      surface of the right size coming back.

## Phase 5 — Streaming honesty

- [x] **5.1** Surface streaming capability in the library, so a non-streamable
      remote publication is flagged before the user taps it. **Done as far as the
      model goes.** `StreamingCapability` is a domain type with the three states
      the finding forced, `Publication` carries one, and `PublicationIndexer` sets
      it from what the container reported — all from headers, so a remote CBR is
      classified without being transferred. What remains is a UI to show it in,
      which does not exist yet.
- [ ] **5.2** The download-instead-of-stream flow, with the size stated.
      **Blocked on there being a remote source to download from.** Every source in
      the app today is local, so there is no flow to enter and nothing whose size
      could be stated. `offline-downloads` and one of the remote source
      capabilities have to land first.
- [ ] **5.3** A downloaded solid archive opens with no notice at all. **True for
      RAR5, false for RAR4** — see the finding below, and note that the finding
      was corrected once a real solid RAR5 could be tested. The format layer is
      ready: `isReadableWhenLocal` refuses solid RAR4 only, and `isStreamable`
      flags both. What is left is the download flow itself.

## Finding — solid RAR4 is unreadable, solid RAR5 is fine

Found while building the 1.1 fixtures, then **corrected** once a real solid RAR5
could be tested. The first version of this finding said solid archives were
unreadable in general. That was half right, and the half that was wrong would
have cost users every solid RAR5 comic they own.

What is measured, against libarchive 3.8.1 compiled from source:

- **Solid RAR4: unreadable.** `read_header()` in
  `archive_read_support_format_rar.c` returns `ARCHIVE_FATAL` on any file header
  carrying `FHD_SOLID`, with no compression-method check and no fallback. The
  RAR4 reader does not implement solid archives, so downloading the file changes
  nothing.
- **Solid RAR5: fully readable.** `test_read_format_rar5_solid.rar` from
  libarchive's own suite yields all seven entries with correct sizes and data.
  `rar5.c` implements solid through its LZ window.

The earlier confusion came from a fixture, not from libarchive: a *store-mode*
solid RAR5 fails as "no window buffer initialized yet", because store mode never
allocates the window. No real compressor emits solid-without-compression, so that
combination only ever existed in the generator.

Three consequences:

1. **`Streaming capability per format` needs three states, not a boolean** —
   streamable, download-only, and refused. Solid RAR5 is download-only; solid
   RAR4 is refused. The delta spec still assumes two.
2. **Detection cannot be delegated.** The first entry of a solid archive is not
   itself solid, so a reader that hands the file straight to libarchive lists
   page 1 and *then* fails with a generic fatal error. The `FHD_SOLID` flag has to
   be read from the headers before any entry is surfaced, or the user sees a
   one-page comic that breaks on the second turn.
3. **The refusal is generation-specific.** `RarReader.isReadableWhenLocal` is
   false only for solid RAR4; `isSolid` alone drives the non-streamable flag. Both
   platforms assert both cases against `rar4-solid.cbr` and `rar5-solid.cbr`.

## Phase 6 — Validation

- [x] **6.1** Full sweep. **Run, with two honest gaps named rather than glossed.**

      | Check | Result |
      | --- | --- |
      | `pnpm lint` | 15 specs validate, tokens in sync, corpus current |
      | `pnpm test:ios` | 145 tests in 22 suites pass |
      | `pnpm test:android` | 108 JVM tests pass |
      | `:core:format:connectedDebugAndroidTest` | 29 instrumented tests pass on an emulator |
      | `./gradlew lint` | passes — see the note below |
      | `./gradlew assembleDebug` | passes, all four ABIs |
      | iOS app build for the simulator | passes, via XcodeGen |
      | `swiftlint --strict` | **not run.** Not installed on this machine |

      **Gap 1: neither app links its format module yet**, so neither app build
      exercises libarchive. `:app` depends on `:core:designsystem`, `:core:model`
      and `:feature:library`; the iOS app target on `DesignSystem`, `StoryArcCore`
      and `LibraryFeature`. The iOS app binary is 40 kB with no libarchive symbols,
      and the debug APK carries no `.so`. That is correct today — nothing in either
      app opens a publication — and the dependency should be added when the reader
      needs it, not before, so the apps do not ship 140 kB per ABI of code nothing
      calls.

      The native code is verified anyway, and more directly: the instrumented test
      APK **does** package `libstoryarc_rar.so` for all four ABIs (169–239 kB
      each), installs on a device, and `dlopen`s it — `RarDecoder.isAvailable` is
      asserted true before any decode test runs. On iOS, `swift test` links
      libarchive into the test binary and decodes real archives. So packaging is
      proven by the test artefacts rather than by the app artefacts.

      **Gap 2: `./gradlew lint` was failing on the passage of time.** Two errors,
      both `AndroidGradlePluginVersion`: AGP 9.3.2 had been published while the
      catalogue pinned 9.3.1. With `warningsAsErrors` on, that makes the same
      commit pass today and fail tomorrow, for a reason not in the repository.
      `AndroidGradlePluginVersion` and `GradleDependency` are now ignored in
      `lint.xml` with that reasoning written down: dependency freshness is a
      deliberate decision taken in the version catalogue, not a lint gate.
- [x] **6.2** Binary size, per ABI, **reported not assumed**. Measured from the
      vendored sources with dead-code stripping on, which is what actually ships:

      | Target | Objects | Contribution to a stripped binary |
      | --- | --- | --- |
      | Apple arm64 | 1136 kB | **~180 kB** |
      | Android arm64-v8a | 444 kB | **140 kB** |
      | Android armeabi-v7a | 412 kB | **137 kB** |
      | Android x86_64 | 456 kB | **146 kB** |
      | Android x86 | 384 kB | **149 kB** |

      And the packaged `libstoryarc_rar.so` that Gradle actually produces,
      including the JNI shim: arm64-v8a 219 kB, armeabi-v7a 164 kB, x86_64 231 kB,
      x86 233 kB. Larger than the stripped-binary figures above because a shared
      library keeps its dynamic symbol table and relocations.

      Better than Phase 0's 202 kB on iOS and 235 kB per Android ABI, because 26
      files are vendored rather than 132 — the linker no longer has to strip what
      was never compiled.
- [x] **6.3** Open a real CBR, CBT and PDF on a simulator and an emulator, with
      screenshots. **Done on the emulator for all three**, in the reader rather
      than the library: `rar5-store.cbr` and `tar-store.cbt` both open at "1 of 3",
      and `text-pages.pdf` renders "Chapter One" and turns to "Chapter Two". EPUB
      reads too, which was not part of this change.

      **On the simulator, partially.** The library screenshot shows CBR, CBT, PDF
      and EPUB rows with covers, which proves the containers parsed and a page
      decoded. Opening one in the reader could not be captured: this machine grants
      `osascript` no assistive access and the simulator MCP device access was
      declined, so there is no way to inject a tap. The iOS reader is instead held
      to `ReaderFeatureTests`, which opens an archive and a PDF, decodes the first
      page, and asserts the prefetch window — the same claim, asserted rather than
      photographed. Re-take the screenshot on a machine that can drive the
      simulator before 1.0.
- [x] **6.4** Update ADR-0005: promote the rows this change proves, and state
      what still blocks acceptance. **Done.** The libarchive and ABI rows are
      marked done with the evidence; the Readium row moved from "blocked on the
      reader existing" to "partly done", because both toolkits now render the same
      EPUB in a real reader and what remains is a pagination comparison under
      matched typography, which needs the type controls of
      `reader-theming-and-page-transitions`. A new row records the packaging
      consequence that Readium is iOS-only, which forced a second SwiftPM package.
      The two spikes that still block acceptance are the SMB time-to-first-page
      measurement and the AMSMB2 linkage check — both belong to sources that are
      not built.
- [ ] **6.5** `/opsx:sync` to merge the delta specs into the main specs.
      **Held, and not because of the specs.** The change validates and every task
      in Phases 0 to 4 and 6 is done. What is open is 5.2 and 5.3, both blocked on
      a remote source existing to download from — which is a different capability
      and arguably a different change. Syncing now would archive a change with two
      unfinished tasks; moving those two into an `offline-downloads` change and
      syncing this one is the other option, and that is a call for whoever owns the
      backlog rather than one to make in passing.
