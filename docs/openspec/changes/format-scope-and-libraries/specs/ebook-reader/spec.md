## MODIFIED Requirements

### Requirement: PDF rendering

The app SHALL render PDF as a paged publication. Text-layer features are
**iOS-only in 1.0**: Android renders PDF pages as images, because the platform
offers no PDF text API that is also a renderer rather than a prebuilt viewer.

#### Scenario: Text-based PDF
- **WHEN** a PDF containing a text layer is opened on iOS
- **THEN** text selection, in-publication search, and the document outline work
- **AND** on Android the same publication renders without them, per the scenario below

#### Scenario: Text-based PDF on Android
- **WHEN** a PDF containing a text layer is opened on Android
- **THEN** it renders with the image-reader behaviour of [`comic-reader`](../comic-reader/spec.md), and text-dependent controls are hidden rather than shown disabled
- **AND** the reader does not claim a capability it does not have — nothing in the UI suggests text search is available and failing

#### Scenario: Scanned PDF
- **WHEN** a PDF is images only
- **THEN** it is read with the image-reader behaviour of [`comic-reader`](../comic-reader/spec.md), and text-dependent controls are hidden
- **AND** this is the behaviour on both platforms, because there is no text layer to expose

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
- **THEN** it appears at the same aspect ratio, fit and zoom behaviour, because only the text layer differs — not the page
- **AND** page geometry is reported in PDF points rather than pixels, so the two platforms are comparable without reference to a screen

#### Scenario: A text layer is detected rather than assumed
- **WHEN** a PDF is opened on iOS
- **THEN** whether it has a text layer is determined by looking for text, not by the file extension
- **AND** a scanned PDF therefore offers no selection or search on either platform, because there is nothing to select or find
