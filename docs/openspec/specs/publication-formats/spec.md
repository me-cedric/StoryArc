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
| CBR | RAR | RAR4 and RAR5, except solid RAR4 — see below |
| CBT | TAR | |
| EPUB | ZIP | EPUB 2 and EPUB 3, reflowable and fixed-layout |
| PDF | — | Including scanned, image-only PDFs |
| Plain folder | — | A directory of ordered images treated as one publication |

CB7 is **not** opened. It receives the same named refusal as any other container
the app does not read. Whether to add it is a product decision that has not been
made — see the Open Questions below.

**Solid RAR4 is not supported either**, and unlike CB7 that is a decoder limit
rather than a choice. The only RAR decoder with an OSI-approved licence does not
implement solid RAR4 at all, so no amount of downloading makes such a file
readable. Solid RAR5 *is* fully supported; it simply cannot be streamed.

#### Scenario: Detecting format
- **WHEN** a publication is opened
- **THEN** the format is determined from the file's contents, not its extension
- **AND** a mis-named file — a ZIP called `.cbr` — still opens

#### Scenario: An unsupported container is named, not merely rejected
- **WHEN** a user opens a CB7, or any other container StoryArc does not read
- **THEN** the app names the container it detected and states which formats it does support
- **AND** it never reports a generic failure, because "7-Zip is not supported" tells the user what to do and "could not open file" does not

#### Scenario: A solid RAR4 is refused before any page is shown
- **WHEN** a solid RAR4 is opened
- **THEN** the app states that the comic uses solid compression and cannot be opened, naming that as the reason
- **AND** it does not present the first page, because only the first entry of a solid archive is readable and a one-page comic that fails on the second turn is worse than a clear refusal
- **AND** the refusal is distinct from an unsupported container, because RAR *is* supported and this particular file is not

#### Scenario: A damaged archive is not reported as an unsupported one
- **WHEN** a file carries a recognised container signature but nothing parseable behind it
- **THEN** the app reports it as damaged rather than as a format it does not support
- **AND** it does not suggest converting the file, because a truncated download is not a format problem

#### Scenario: Encrypted or password-protected archive
- **WHEN** an archive requires a password
- **THEN** the app states that the archive is protected and does not prompt for a password, because StoryArc does not manage archive passwords

#### Scenario: Corrupt archive
- **WHEN** an archive is truncated or its index is unreadable
- **THEN** the app opens whatever pages it can read and states how many were skipped, rather than refusing the whole publication
- **AND** the count is shown in the reader's own controls, where it recedes with them,
  because it is a fact about the file rather than about the page in front of the reader

### Requirement: Streaming capability per format

Ranged reads are not uniformly possible, so the app SHALL know which formats can
be read remotely and SHALL be honest when one cannot.

Capability has **three** states, not two. A format that cannot be streamed is
not necessarily a format that cannot be read, and one that cannot be read is not
merely slow.

| Format | Remote reading | State |
| --- | --- | --- |
| CBZ, EPUB | Index at the end, entries stored independently | Streams |
| PDF | Cross-reference table at the end | Streams |
| CBT | Once an index is built by hopping headers | Streams |
| CBR, non-solid | Headers indexed remotely; entries read independently | Streams |
| Plain folder | Each page is its own file | Streams |
| CBR, solid RAR5 | Every entry before the target must be decompressed | Download only |
| CBR, solid RAR4 | No available decoder reads one, local or remote | Refused |

The **index** is streamable in every case, including the two that are not. A CBR's
page names, page count, sizes and cover all come from its headers, which are read
with ranged reads and no decompression — so the library can catalogue a remote
comic, and decide which of the three states it is in, without transferring it.

#### Scenario: Opening a streamable publication from a remote source
- **WHEN** a user opens a streamable publication on a network share or a server
- **THEN** the first page renders without the whole publication being transferred

#### Scenario: Opening a solid archive from a remote source
- **WHEN** a publication cannot be read with ranged reads
- **THEN** the app says the format has to be downloaded before it can be read, states the size, and offers to download it
- **AND** it does not begin streaming badly and leave the user watching a stalled page

#### Scenario: A solid archive already downloaded
- **WHEN** a publication that cannot stream is already available offline
- **THEN** it opens directly with no notice, because the constraint was never about the format being readable
- **AND** this holds for solid RAR5, which is download-only; it does not hold for solid RAR4, which is refused whether local or remote

#### Scenario: A remote publication is catalogued without being transferred
- **WHEN** a CBR is indexed from a network share or a server
- **THEN** its page count, page order, sizes and cover are read from its headers alone, with no entry decompressed
- **AND** its streaming state is determined at the same time, from the same headers

#### Scenario: Streaming capability is known before the first page is requested
- **WHEN** a publication is indexed
- **THEN** whether it can be read remotely is recorded with it, so the library can warn before a user taps rather than after

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
  are in [ADR-0013](../../../decisions/0013-cb7-support.md). **Still open**: it is a
  product decision, not an engineering one. Until it is made a `.cb7` is refused by
  name rather than reported as a broken file, which the *An unsupported container is
  named, not merely rejected* scenario requires and the app already does.
