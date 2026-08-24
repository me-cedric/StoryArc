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
- [ ] **0.1c** Read an actual RAR. Blocked on a hand-made `.cbr` fixture — see 1.1.
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
