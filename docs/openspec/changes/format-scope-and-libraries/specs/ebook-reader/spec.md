## MODIFIED Requirements

### Requirement: PDF rendering

The app SHALL render PDF as a paged publication. The text layer comes from each
platform's own PDF library — PDFKit on one, `android.graphics.pdf` on the other.
The document outline is the one part of it only PDFKit exposes, which
[ADR-0011](../../../../decisions/0011-pdf-text-on-android.md) records.

#### Scenario: Text-based PDF
- **WHEN** a PDF contains a text layer
- **THEN** text selection, in-publication search, and the document outline work
- **AND** a selection offers the same four things a reflowable selection does — highlight in several colours, add a note, copy, and search-in-publication — stored as the same record and exported by the same document
- **AND** where a platform's PDF library exposes no document outline, that control is absent rather than empty, which [ADR-0011](../../../../decisions/0011-pdf-text-on-android.md) records

#### Scenario: Scanned PDF
- **WHEN** a PDF is images only
- **THEN** it is read with the image-reader behaviour of [`comic-reader`](../comic-reader/spec.md), and text-dependent controls are hidden
- **AND** a reader who presses on a word expecting to select it is told in one sentence that the file is images of pages, rather than being met with silence
- **AND** this is the behaviour on both platforms, because there is no text layer to expose

#### Scenario: A device that cannot read PDF text
- **WHEN** the platform's PDF text API is absent on this device
- **THEN** the publication behaves exactly as a scanned PDF does: no search control, no selection, and the same one-sentence statement
- **AND** nothing names the missing API, because a reader can act on neither that nor the file's contents and only the second is about the book

#### Scenario: Large PDF
- **WHEN** a PDF of several hundred megabytes is opened from a remote source
- **THEN** pages render on demand rather than the whole document being loaded
- **AND** opening the document rasterises nothing, so page count and page geometry are available before any page is drawn

#### Scenario: A rendered page is bounded by what it is shown at
- **WHEN** a page is rendered for display
- **THEN** it is rasterised to at most the size it will occupy, never to the page's full resolution regardless of the screen
- **AND** asking for more pixels than the page has does not upscale it, matching how an image page is decoded

#### Scenario: Page rendering is identical across platforms
- **WHEN** the same PDF page is rendered on both platforms
- **THEN** it appears at the same aspect ratio, fit and zoom behaviour, because only the document outline differs — not the page
- **AND** page geometry is reported in PDF points rather than pixels, so the two platforms are comparable without reference to a screen

#### Scenario: A text layer is detected rather than assumed
- **WHEN** a PDF is opened
- **THEN** whether it has a text layer is determined by looking for text, not by the file extension
- **AND** a scanned PDF therefore offers no selection or search on either platform, because there is nothing to select or find
