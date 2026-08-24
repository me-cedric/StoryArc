## MODIFIED Requirements

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

CB7 is **not** supported. It is rare, and it is the worst streaming case — solid
blocks mean one page can require decompressing everything around it. It receives
the same named refusal as any other unsupported container.

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

## ADDED Requirements

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
- **WHEN a** publication cannot be read with ranged reads
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
