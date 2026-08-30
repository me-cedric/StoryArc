# publication-formats Specification

## Purpose

Reading the container formats people actually have. Everything above this
capability — readers, library, downloads — works against a uniform publication
model; this capability is what turns a heterogeneous pile of archives into that
model.

## Requirements

### Requirement: Supported formats

The app SHALL open the following formats:

| Format | Container | Notes |
| --- | --- | --- |
| CBZ | ZIP | Primary comic format |
| CBR | RAR | RAR4 and RAR5 |
| CB7 | 7-Zip | |
| CBT | TAR | |
| EPUB | ZIP | EPUB 2 and EPUB 3, reflowable and fixed-layout |
| PDF | — | Including scanned, image-only PDFs |
| Plain folder | — | A directory of ordered images treated as one publication |

#### Scenario: Detecting format
- **WHEN** a publication is opened
- **THEN** the format is determined from the file's contents, not its extension
- **AND** a mis-named file — a ZIP called `.cbr` — still opens

#### Scenario: Encrypted or password-protected archive
- **WHEN** an archive requires a password
- **THEN** the app states that the archive is protected and does not prompt for a password, because StoryArc does not manage archive passwords

#### Scenario: Corrupt archive
- **WHEN** an archive is truncated or its index is unreadable
- **THEN** the app opens whatever pages it can read and states how many were skipped, rather than refusing the whole publication
- **AND** the count is shown in the reader's own controls, where it recedes with them,
  because it is a fact about the file rather than about the page in front of the reader

### Requirement: Page ordering

The app SHALL order the images in an archive the way a human would.

#### Scenario: Natural sort
- **WHEN** an archive contains `page1.jpg`, `page2.jpg` … `page10.jpg`
- **THEN** page 10 sorts after page 9, not after page 1

#### Scenario: Nested directories in an archive
- **WHEN** an archive contains images inside subdirectories
- **THEN** pages are ordered by full path using natural sort, so chapter folders stay in order

#### Scenario: Non-image entries
- **WHEN** an archive contains `ComicInfo.xml`, `Thumbs.db`, `__MACOSX/` entries, or other non-page files
- **THEN** they are excluded from the page list and never displayed as a page

### Requirement: Metadata extraction

The app SHALL extract embedded metadata and use it to populate the library.

#### Scenario: ComicInfo.xml
- **WHEN** a comic archive contains `ComicInfo.xml`
- **THEN** series, number, volume, title, summary, writer, penciller, publisher, release date, page count, language, and reading direction are read from it

#### Scenario: EPUB package metadata
- **WHEN** an EPUB is opened
- **THEN** title, author, language, publisher, description, series and series index, and the cover are read from its package document

#### Scenario: No embedded metadata
- **WHEN** a publication carries no metadata
- **THEN** series, volume, chapter, and year are parsed from the filename using common naming patterns
- **AND** the app marks these values as inferred, so a later authoritative source can replace them without a conflict prompt

#### Scenario: Right-to-left publication
- **WHEN** metadata declares a right-to-left reading direction, or the language is Japanese and the direction is unspecified
- **THEN** the reader opens right-to-left by default, and the user can override it per publication

### Requirement: Cover extraction

The app SHALL produce a cover for every publication.

#### Scenario: Comic cover
- **WHEN** a comic archive is indexed
- **THEN** the first page in reading order becomes the cover unless `ComicInfo.xml` designates a different one

#### Scenario: EPUB cover
- **WHEN** an EPUB declares a cover image
- **THEN** that image is used; otherwise the image shown by the first item in the spine
  becomes the cover, and is cached like any other
- **AND** a first spine item that shows no image leaves the publication with no cover,
  because rasterising arbitrary XHTML needs a web view on both platforms and that is a
  larger decision than a thumbnail

#### Scenario: Cover generation cost
- **WHEN** a folder of 10,000 publications is scanned
- **THEN** covers are extracted lazily as rows approach the viewport, not all at once during the scan

### Requirement: Page decoding

The app SHALL decode pages without exhausting memory, regardless of source image size.

#### Scenario: Very large page
- **WHEN** a page is larger than the device can hold at full resolution
- **THEN** it is downsampled to the display's needs for viewing and re-decoded at higher resolution when the user zooms
- **AND** the re-decoded copy is held only while the zoom is, up to a ceiling the
  memory-pressure prefetch window sets, so a magnified page never costs more than one
  extra page

#### Scenario: Supported image codecs
- **WHEN** a page is JPEG, PNG, WebP, AVIF, GIF, or HEIC
- **THEN** it renders
- **AND** a page in an unsupported codec displays a placeholder naming the codec — read
  from the page's own bytes, not from its file name — and does not break pagination
- **AND** a page whose bytes could not be read at all keeps its place in the reading order
  and is retried, because an unreachable source is not a broken file

#### Scenario: Wide double-page image
- **WHEN** a single image is materially wider than it is tall in a portrait publication
- **THEN** it is treated as a double-page spread per [`comic-reader`](../comic-reader/spec.md)

## Open Questions

- CB7 depends on a 7-Zip decoder on both platforms, and the spike answered the
  question it was asked: a decoder exists and is permissively licensed, but reaching
  it means vendoring a second C library on both platforms for a format that is rare
  and cannot be streamed. The cost, the three ways to answer it and a recommendation
  are in [ADR-0011](../../../decisions/0011-cb7-support.md). **Still open**: it is a
  product decision, not an engineering one. Until it is made a `.cb7` is refused by
  name rather than reported as a broken file, which the *Detecting format* scenario
  already requires.
