# Tasks

Phase 0 is a build-engineering spike, and it gates everything. If libarchive
cannot be built cleanly for all six ABIs, CBR and CBT stay unsupported and the
rest of this change does not happen.

## Phase 0 — libarchive integration spike

- [x] **0.1a** Build libarchive for iOS device and simulator, and for Android
      arm64-v8a. **Done** — 131/131 sources compile for both iOS slices, Android
      builds via CMake + NDK 29, and a real TAR reads correctly with the right
      entry names, sizes and format identification.
- [ ] **0.1b** The remaining three Android ABIs. Same CMake invocation with a
      different `ANDROID_ABI`; mechanical.
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
- [ ] **0.5** Decide how the library is vendored: sources plus a per-target
      `config.h`, or prebuilt binaries. Phase 0 found that iOS must compile the
      sources itself — libarchive's CMake cannot configure for iOS — which argues
      for sources on both sides with a generated config per target. Record it,
      because the answer determines whether a contributor can build the app.

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
- [ ] **1.5** A **solid RAR5** fixture, which is the one item that still needs a
      real compressor. Solid means nothing without compression, and libarchive
      only implements solid RAR5 through the LZ window that store mode never
      allocates, so the generator cannot produce an honest one. Create it by hand
      with `rar a -s`, from the same synthetic pages, and record its provenance.
      Until then Phase 5 rests on `rar4-solid.cbr`, which pins a stronger
      outcome — see the finding below.

## Phase 2 — Format layer

CBT does not need libarchive at all, so it shipped first — see 2.6. What is left
here is RAR, which is the only format that genuinely needs a decoder.

- [ ] **2.1** C interop layer per platform, exposing libarchive behind the same
      `ComicArchiveReading` interface the ZIP reader already implements. Scope
      narrowed twice: by 2.6, libarchive is not needed for TAR; by 2.7, it is not
      needed for RAR *headers* either. What is left is one function — packed bytes
      in, unpacked bytes out — behind `RarReader.data`, which already throws
      `needsDecoder` at exactly that seam.
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
- [ ] **3.3** Compare a decoded fixture page across platforms and record the
      tolerance. This is where image decoding stops being *Assumed* in ADR-0005.

## Phase 4 — PDF

- [ ] **4.1** iOS: PDFKit, with text selection, in-publication search and outline.
- [ ] **4.2** Android: system `PdfRenderer`, pages as images, page-on-demand
      verified on a large document.
- [ ] **4.3** Hide text-dependent controls on Android. Hidden, never disabled —
      the spec forbids implying a capability that is absent.
- [ ] **4.4** Assert the same page renders at the same aspect ratio and fit on
      both platforms.

## Phase 5 — Streaming honesty

- [ ] **5.1** Surface streaming capability in the library, so a non-streamable
      remote publication is flagged before the user taps it. The format layer now
      answers the question — `RarReader.isSolid`, from headers alone — so what is
      left is carrying it into the library model and the UI.
- [ ] **5.2** The download-instead-of-stream flow, with the size stated.
- [ ] **5.3** A downloaded solid archive opens with no notice at all. **True for
      RAR5, false for RAR4** — see the finding below. A solid RAR4 must be
      refused by name at index time, whether it is remote or already downloaded.

## Finding — libarchive cannot read a solid RAR4 at all

Found while building the 1.1 fixtures, and it changes what Phase 5 can promise.

`read_header()` in `archive_read_support_format_rar.c` (libarchive 3.8.1) returns
`ARCHIVE_FATAL` on any file header carrying `FHD_SOLID`. There is no
compression-method check and no fallback: the RAR4 reader does not implement
solid archives. Downloading the file changes nothing.

Two consequences, both pinned by `rar4-solid.cbr`:

1. **Solid RAR4 is unsupported, not un-streamable.** The `Streaming capability
   per format` requirement needs a third state — supported, download-only, and
   refused — rather than a streamable boolean. Task 2.3 and the delta spec both
   assume two.
2. **Detection cannot be delegated.** The first entry of a solid archive is not
   itself solid, so a reader that hands the file straight to libarchive lists
   page 1 and *then* fails with a generic fatal error. The `FHD_SOLID` flag has
   to be read from the headers before any entry is surfaced, or the user sees a
   one-page comic that breaks on the second turn.

Solid RAR5 is unaffected: `rar5.c` implements it through its LZ window. That is
also why there is no solid RAR5 fixture yet — see 1.5.

## Phase 6 — Validation

- [ ] **6.1** `pnpm lint`, `pnpm test:ios`, `pnpm test:android`, both app builds,
      `swiftlint --strict`, `./gradlew lint`.
- [ ] **6.2** Binary size before and after, per ABI, reported not assumed.
- [ ] **6.3** Open a real CBR, CBT and PDF on a simulator and an emulator, with
      screenshots. A fixture proves parsing; a screenshot proves reading.
- [ ] **6.4** Update ADR-0005: promote the rows this change proves, and state
      what still blocks acceptance.
- [ ] **6.5** `/opsx:sync` to merge the delta specs into the main specs.
