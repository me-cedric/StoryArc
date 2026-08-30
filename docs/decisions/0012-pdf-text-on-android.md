---
status: accepted
date: 2026-08-30
deciders: Cédric Meyer
---

# ADR-0012 — PDF text on Android comes from the platform's own PDF module

## Context and problem statement

[`ebook-reader`](../openspec/specs/ebook-reader/spec.md) says a PDF that carries
a text layer gets "text selection, in-publication search, and the document
outline". Until now this repository carried a written assumption, in the spec, in
both `PdfDocumentReader`s and in the shared fixture manifest, that the Android
half of that was impossible:

> Android offers no PDF text API that is also a renderer — `PdfRenderer` draws
> pages and exposes nothing else.

That was true when it was written and is no longer true. `android.graphics.pdf`
has gained text extraction, text search and text selection:

| API | Available from |
| --- | --- |
| `PdfRenderer.Page.getTextContents()`, `searchText()`, `selectContent()` | API 35 |
| `PdfRendererPreV` and `PdfRendererPreV.Page`, the same three | API 31 with `framework-pdf` **SDK extension 13**; API 35 in the platform |

`framework-pdf` is a mainline module delivered by a Google Play system update, so
"can this device read the text in a PDF" is a question about the *device* rather
than about its API level: an Android 12 phone with an up-to-date module can, and
an Android 15 phone always can. `SdkExtensions.getExtensionVersion(VERSION_CODES.S)`
answers it, and that call arrived in API 30 — below this app's floor of 31
([ADR-0003](0003-platform-floors.md)).

So the question is no longer *whether* Android can read PDF text. It is what to
read it with, and what to do on a device that still cannot.

## Decision drivers

- The spec's own rule that a control which cannot deliver what it promises is
  hidden rather than disabled.
- [ADR-0008](0008-ranged-reads-and-own-zip-reader.md): archive and document
  parsing runs on untrusted input, and every parser added is a parser to keep
  safe.
- [ADR-0001](0001-independent-native-cores.md): the two apps mirror a behaviour,
  and a divergence has to be a stated one rather than a silent one.
- The floor stays at API 31. No capability raises it.

## Considered options

1. Add a PDF library that reads text.
2. Leave PDF text iOS-only, as previously recorded.
3. Use the platform's PDF module, gated on the SDK extension.

### Add a PDF library

- Good, because the answer would be the same on every supported device, with no
  extension check anywhere.
- Bad, because PDFBox-Android, PdfiumAndroid and Readium's
  `readium-adapter-pdfium` each bring a native blob of a megabyte or more.
- Bad, because it is a second PDF parser over untrusted input, which ADR-0008
  spends its whole argument avoiding.
- Bad, because none of them is on the dependency list, and none earns a place on
  it for something the platform now does.

### Leave PDF text iOS-only

- Good, because it is honest and already written down.
- Bad, because it withholds a working capability from most of the Android
  install base for no reason other than a note in this repository being out of
  date.

### Use the platform's PDF module

- Good, because it costs no runtime dependency and no second parser.
- Good, because the same class answers for Android 12 through 16.
- Bad, because a device whose PDF module predates extension 13 gets nothing, so
  two Android phones can disagree about one file.
- Bad, because the module still exposes no document outline, so one third of the
  spec's scenario stays iOS-only.

## Decision Outcome

We chose **the platform's PDF module**, through `PdfRendererPreV`, gated on SDK
extension 13 of `framework-pdf`. Where the extension is absent the app behaves
exactly as it does for a PDF with no text layer at all.

And explicitly **not** a PDF library, because ADR-0008's argument against a
second parser over untrusted input has not weakened, and a megabyte of native
code to duplicate a platform capability is a cost with nothing on the other side.

As built:

- **One class, not two.** `PdfRendererPreV` exists at every level this app
  supports once the module is there, 35 included, so there is no second code
  path for "the platform version" to keep true.
- **A second document handle.** `PdfDocumentReader` keeps its own `PdfRenderer`
  for drawing; `PdfTextReader` opens the same file again for text. `PdfRenderer`
  permits one open page at a time, and a selection waiting behind a page render
  would arrive after the finger had moved. Two read-only descriptors on one file
  cost a file descriptor.
- **The capability is named, not the class.** `PdfTextReading` is an interface
  and the annotated implementation is internal to `:core:format`.
  `@RequiresExtension` travels to every caller of the type it sits on, and
  without the interface an extension check would have appeared in the reader
  screen, in the view model, and in everything either hands the reader to.
  `PdfTextReading.open(...)` returns `null`, and the rest of the app holds
  something that is either present or absent.
- **One new dependency, annotations only.** `androidx.annotation`, for
  `@RequiresExtension` and `@ChecksSdkIntAtLeast`. Without them lint cannot see
  that an extension check is a real guard, and the alternative is a suppression
  — a lie that outlives the reason for it. Nothing is added at runtime.

## What stays asymmetric, on purpose

**The document outline.** PDFKit reads one; `android.graphics.pdf` exposes
links, text, form fields and page objects, and no outline. So the find sheet has
three tabs on iOS — search, marks, contents — and two on Android, and the third
is absent rather than empty. This is the one part of the "Text-based PDF"
scenario one platform cannot honour, and the spec now says so rather than
implying both do.

**A device without extension 13.** It gets the scanned-PDF behaviour: no search
control, no selection, and the same one-sentence statement if a reader presses on
a word expecting to select it. The statement names what the file is rather than
what the device lacks, because a reader can act on neither and the first is at
least about the book.

## Consequences

- Positive: both platforms now offer selection, copy, highlight, note and
  in-publication search over a PDF's text, through the same `Annotation` record,
  the same `AnnotationStore`, the same `AnnotationExport`, and the same
  `SearchSnippet` rule the EPUB reader uses. One export covers a novel and a
  manual.
- Negative: the platform PDF text APIs cannot be exercised by a JVM unit test —
  they are framework classes that are stubs off-device — so Android's coverage of
  them is instrumented (`PdfTextReaderInstrumentedTest`) and skips itself with an
  assumption where the extension is absent. The parts that *are* pure — the
  locator, the snippet rule, the page-to-view geometry — are unit-tested on both
  platforms, case for case.
- Negative: two Android devices can disagree about whether one PDF has selectable
  text. Nothing in the UI explains that, and nothing should: the reader cannot
  act on it.
- Neutral: `minSdk` does not move. ADR-0003 stands.
- Follow-up: if an outline ever appears in the platform's PDF API, the third tab
  is one list away — supersede this ADR rather than amending it.

## Links

- Spec: [`ebook-reader`](../openspec/specs/ebook-reader/spec.md), "PDF rendering"
- Related decisions: [ADR-0003](0003-platform-floors.md) (the floor this does not
  move), [ADR-0005](0005-format-and-rendering-libraries.md) (why PDF is the
  platform's own on both sides), [ADR-0008](0008-ranged-reads-and-own-zip-reader.md)
  (why a second parser is not free)
- Affected modules: `apps/android/core/format`, `apps/android/feature/reader`,
  `apps/ios/Packages/StoryArcKit/Sources/Formats`,
  `apps/ios/Packages/StoryArcKit/Sources/ReaderFeature`
