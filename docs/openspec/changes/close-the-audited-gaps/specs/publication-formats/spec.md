## MODIFIED Requirements

### Requirement: Streaming capability per format

Ranged reads are not uniformly possible, so the app SHALL know which formats can
be read remotely and SHALL be honest when one cannot.

Capability has **three** states, not two. A format that cannot be streamed is
not necessarily a format that cannot be read, and one that cannot be read is not
merely slow.

| Format | Remote reading | State |
| --- | --- | --- |
| CBZ, EPUB | Index at the end, entries stored independently | Streams |
| PDF | Cross-reference table at the end | Streams on Android; fetched whole on iOS |
| CBT | Once an index is built by hopping headers | Streams |
| CBR, non-solid | Headers indexed remotely; entries read independently | Streams |
| Plain folder | Each page is its own file | Streams |
| CBR, solid RAR5 | Every entry before the target must be decompressed | Download only |
| CBR, solid RAR4 | No available decoder reads one, local or remote | Refused |

The **index** is streamable in every case, including the two that are not. A CBR's
page names, page count, sizes and cover all come from its headers, which are read
with ranged reads and no decompression — so the library can catalogue a remote
comic, and decide which of the three states it is in, without transferring it.

A PDF on iOS is the one platform difference. PDFKit opens a document only from a
whole file or from whole data in memory, and it alone gives the PDF reader its
selection, search, outline and marks. iOS therefore fetches a remote PDF whole
before it opens it, rather than trade those features for a page renderer that
reads ranges.

#### Scenario: Opening a streamable publication from a remote source
- **WHEN** a user opens a streamable publication on a network share or a server
- **THEN** the first page renders without the whole publication being transferred

#### Scenario: Opening a remote PDF on iOS
- **WHEN** a user opens a PDF on a network share or a server on iOS
- **THEN** the app fetches the whole file first, shows how far the fetch has come, and opens the PDF reader when it ends
- **AND** a fetch that fails is stated as a connection failure, not as a fault in the file

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
