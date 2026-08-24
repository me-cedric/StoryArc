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

#### Scenario: Page rendering is identical across platforms
- **WHEN** the same PDF page is rendered on both platforms
- **THEN** it appears at the same aspect ratio, fit and zoom behaviour, because only the text layer differs — not the page
