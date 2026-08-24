# Tasks

Phase 0 is a build-engineering spike, and it gates everything. If libarchive
cannot be built cleanly for all six ABIs, CBR and CBT stay unsupported and the
rest of this change does not happen.

## Phase 0 — libarchive integration spike

- [ ] **0.1** Build libarchive for iOS device and simulator, and for the four
      Android ABIs. Deliverable: it links and reads a real CBR on both platforms,
      or a clear reason it cannot.
- [ ] **0.2** Trim the build: disable every format reader except RAR and TAR,
      **including 7-Zip**, and every compression backend not needed by those.
      Deliverable: measured bytes per ABI.
- [ ] **0.3** Confirm the licence and record it verbatim in
      `THIRD_PARTY_NOTICES.md`, plus a note that its RAR readers are not
      UnRAR-derived.
- [ ] **0.4** Add a `SECURITY.md` entry: libarchive parses untrusted input in C.
      State the mitigation — bounded reads, no allocation from file-supplied
      lengths, and the fact that it is the most audited RAR implementation
      available.
- [ ] **0.5** Decide how the library is vendored: a binary XCFramework and
      prebuilt `.so` set, or built from source in CI. Record it, because the
      answer determines whether a contributor can build the app.

## Phase 1 — Fixture corpus

- [ ] **1.1** Extend `packages/test-fixtures/scripts/generate.py` with CBR
      fixtures: non-solid RAR4, non-solid RAR5, and a **solid** RAR to pin the
      cannot-stream path. Generating these needs a RAR *compressor*, which is
      proprietary — so these fixtures are created once, by hand, from freely
      redistributable input and committed with their provenance recorded.
- [ ] **1.2** CBT fixtures: plain TAR, and one with nested chapter directories.
- [ ] **1.3** A CB7 fixture, used only to assert the **named refusal**.
- [ ] **1.4** Record every expectation in `manifest.json`. No hashes — the
      manifest pins meaning, not bytes.

## Phase 2 — Format layer

- [ ] **2.1** C interop layer per platform, exposing libarchive behind the same
      `ComicArchiveReading` interface the ZIP reader already implements.
- [ ] **2.2** Read RAR and TAR entries through `RandomAccessSource`, so remote
      sources work wherever the container allows it.
- [ ] **2.3** Detect solid RAR and record the publication as non-streamable at
      index time, per the new `Streaming capability per format` requirement.
- [ ] **2.4** Remove CB7 from the supported set; assert the named refusal.
- [ ] **2.5** Mirror the tests on both platforms against the same fixtures, as
      the ZIP layer does.

## Phase 3 — Page decoding

- [ ] **3.1** iOS: `CGImageSource` decode with `ThumbnailMaxPixelSize`
      downsampling, and re-decode at higher resolution on zoom.
- [ ] **3.2** Android: `ImageDecoder` with `setTargetSize`, same behaviour. No
      Coil.
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
      remote publication is flagged before the user taps it.
- [ ] **5.2** The download-instead-of-stream flow, with the size stated.
- [ ] **5.3** A downloaded solid archive opens with no notice at all.

## Phase 6 — Validation

- [ ] **6.1** `pnpm lint`, `pnpm test:ios`, `pnpm test:android`, both app builds,
      `swiftlint --strict`, `./gradlew lint`.
- [ ] **6.2** Binary size before and after, per ABI, reported not assumed.
- [ ] **6.3** Open a real CBR, CBT and PDF on a simulator and an emulator, with
      screenshots. A fixture proves parsing; a screenshot proves reading.
- [ ] **6.4** Update ADR-0005: promote the rows this change proves, and state
      what still blocks acceptance.
- [ ] **6.5** `/opsx:sync` to merge the delta specs into the main specs.
